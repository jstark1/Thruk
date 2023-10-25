package Thruk::Agents::SNClient;

use warnings;
use strict;
use Carp qw/confess/;
use Cpanel::JSON::XS qw/decode_json/;

use Monitoring::Config::Object ();
use Thruk::Controller::conf ();
use Thruk::Utils ();
use Thruk::Utils::Agents ();
use Thruk::Utils::Log qw/:all/;

=head1 NAME

Thruk::Agents::SNClient - implements snclient based agent configuration

=cut

my $settings = {
    'type'          => 'snclient',
    'icon'          => 'snclient.png',
    'icon_dark'     => 'snclient_dark.png',
    'default_port'  => 8443,
    'check_nsc_web_extra_options' => '-t 35',
};

=head1 METHODS

=cut

##########################################################

=head2 new

    new($c, $host)

returns agent object from livestatus host

=cut
sub new {
    my($class, $host) = @_;
    my $self = {};
    bless $self, $class;
    return($self);
}

##########################################################

=head2 settings

    settings()

returns settings for this agent

=cut
sub settings {
    return($settings);
}

##########################################################

=head2 get_config_objects

    get_config_objects($c, $data, $checks_config)

returns list of Monitoring::Objects for the host / services along with list of objexts to remove

=cut
sub get_config_objects {
    my($self, $c, $data, $checks_config, $fresh) = @_;

    my $backend  = $data->{'backend'}  || die("missing backend");
    my $hostname = $data->{'hostname'} || die("missing hostname");
    my $ip       = $data->{'ip'}       // '';
    my $section  = $data->{'section'}  // '';
    my $password = $data->{'password'} // '';
    my $port     = $data->{'port'}     || $settings->{'default_port'};

    my $filename = $section ? sprintf('agents/%s/%s.cfg', $section, $hostname) : sprintf('agents/%s.cfg', $hostname);
    my $objects  = $c->{'obj_db'}->get_objects_by_name('host', $hostname);
    my $hostobj;
    if(!$objects || scalar @{$objects} == 0) {
        # create new one
        $hostobj = Monitoring::Config::Object->new( type    => 'host',
                                                   coretype => $c->{'obj_db'}->{'coretype'},
                                                );
        my $file = Thruk::Controller::conf::get_context_file($c, $hostobj, $filename);
        die("creating file failed") unless $file;
        $hostobj->set_file($file);
        $hostobj->set_uniq_id($c->{'obj_db'});
        $hostobj->{'conf'}->{'host_name'} = $hostname;
        $hostobj->{'conf'}->{'alias'}     = $hostname;
        $hostobj->{'conf'}->{'use'}       = ['generic-host'];
        $hostobj->{'conf'}->{'address'}   = $ip || $hostname;
    } else {
        $hostobj = $objects->[0];
    }

    my @list = ($hostobj);
    my @remove;

    my $hostdata = $hostobj->{'conf'} // {};

    my $services = Thruk::Utils::Agents::get_host_agent_services($c, $hostobj);

    # save services
    my $checks = Thruk::Utils::Agents::get_services_checks($c, $backend, $hostname, $hostobj, "snclient", $password, $fresh);
    my $checks_hash = Thruk::Base::array2hash($checks, "id");

    confess("missing host config") unless $checks_hash->{'_host'};
    for my $key (sort keys %{$checks_hash->{'_host'}->{'conf'}}) {
        $hostdata->{$key} = $checks_hash->{'_host'}->{'conf'}->{$key};
    }
    $hostdata->{'_AGENT_SECTION'}  = $section;
    $hostdata->{'_AGENT_PORT'}     = $port;
    my $settings = $hostdata->{'_AGENT_CONFIG'} ? decode_json($hostdata->{'_AGENT_CONFIG'}) : {};

    for my $id (sort keys %{$checks_hash}) {
        next if $id eq '_host';
        my $type = $checks_config->{'check.'.$id} // 'off';
        my $args = $checks_config->{'args.'.$id}  // '';
        my $chk  = $checks_hash->{$id};
        confess("no name") unless $chk->{'name'};
        my $svc = $services->{$chk->{'name'}};
        if(!$svc && $type eq 'on') {
            # create new one
            $svc = Monitoring::Config::Object->new( type     => 'service',
                                                    coretype => $c->{'obj_db'}->{'coretype'},
                                                    );
            my $file = Thruk::Controller::conf::get_context_file($c, $svc, $filename);
            die("creating file failed") unless $file;
            $svc->set_file($file);
            $svc->set_uniq_id($c->{'obj_db'});
        }

        if($type eq 'new') {
            $settings->{'disabled'} = Thruk::Base::array_remove($settings->{'disabled'}, $id);
            push @remove, $svc if $svc;
        }

        if($type eq 'off') {
            push @remove, $svc if $svc;
            push @{$settings->{'disabled'}}, $id;
        }
        next unless($type eq 'on' || ($chk->{'svc_conf'}->{'_AGENT_ARGS'}//'') ne ($args//''));

        # always set right file name
        my $file = Thruk::Controller::conf::get_context_file($c, $svc, $filename);
        die("creating file failed") unless $file;
        $svc->set_file($file);
        $svc->{'conf'} = $chk->{'svc_conf'};
        $chk->{'svc_conf'}->{'_AGENT_ARGS'} = $args;
        $chk->{'svc_conf'}->{'check_command'} .= " ".$args if $args;

        push @list, $svc;
    }

    my $json = Cpanel::JSON::XS->new->canonical;
    $settings->{'disabled'} = Thruk::Base::array_uniq($settings->{'disabled'}) if $settings->{'disabled'};
    $settings = $json->encode($settings);
    if($settings ne ($hostdata->{'_AGENT_CONFIG'}//"")) {
        $hostdata->{'_AGENT_CONFIG'} = $settings;
    }
    $hostobj->{'conf'} = $hostdata;

    return(\@list, \@remove);
}

##########################################################

=head2 get_services_checks

    get_services_checks($c, $hostname, $hostobj, $password, $fresh)

returns list of Monitoring::Objects for the host / services

=cut
sub get_services_checks {
    my($self, $c, $hostname, $hostobj, $password, $fresh) = @_;
    my $datafile = $c->config->{'tmp_path'}.'/agents/hosts/'.$hostname.'.json';
    my $checks = [];
    if(-r $datafile) {
        my $data = Thruk::Utils::IO::json_lock_retrieve($datafile);
        $checks = _extract_checks($c, $data->{'inventory'}, $hostname, $password, $fresh) if $data->{'inventory'};
    }
    return($checks);
}

##########################################################

=head2 get_inventory

    get_inventory($c, $c, $address, $hostname, $password, $port)

returns json structure from inventory api call.

=cut
sub get_inventory {
    my($self, $c, $address, $hostname, $password, $port) = @_;

    die("no password supplied") unless $password;
    my $command  = "check_snclient";
    my $args     = sprintf("%s -p '%s' -r -u 'https://%s:%d/api/v1/inventory'",
        _check_nsc_web_extra_options($c),
        $password,
        ($address || $hostname),
        $port,
    );

    my $cmd = {
        command_name => 'check_snclient',
        command_line => '$USER1$/check_nsc_web $ARG1$',
    };
    Thruk::Utils::Agents::check_for_check_commands($c, [$cmd]);

    _debug("scan command: %s!%s", $command, $args);
    my $output = $c->{'obj_db'}->get_plugin_preview($c,
                                        $command,
                                        $args,
                                        $hostname,
                                        '',
                                    );
    if($output =~ m/^\{/mx) {
        my $data;
        eval {
            $data = decode_json($output);
        };
        my $err = $@;
        if($err) {
            die($err);
        }
        return $data;
    }
    die($output);
}

##########################################################
sub _extract_checks {
    my($c, $inventory, $hostname, $password, $fresh) = @_;
    my $checks = [];

    # get available modules
    my $modules = Thruk::Utils::find_modules('Thruk/Agents/SNClient/Checks/*.pm');
    for my $mod (@{$modules}) {
        require $mod;
        $mod =~ s/\//::/gmx;
        $mod =~ s/\.pm$//gmx;
        $mod->import;
        push @{$checks}, @{$mod->get_checks($c, $inventory, $hostname, $password)};
    }

    # compute host configuration
    my $hostdata = {};
    $hostdata->{'_AGENT'} = 'snclient';
    $password = '' unless defined $password;
    $hostdata->{'_AGENT_PASSWORD'} = $password if($password ne ''); # only if changed
    push @{$checks}, {
        'id'       => '_host',
        'conf'     => $hostdata,
    };

    # compute service configuration
    for my $chk (@{$checks}) {
        next if $chk->{'id'} eq '_host';
        my $svc_password = '$_HOSTAGENT_PASSWORD$';
        if($password ne '' && $password =~ m/^\$.*\$$/mx) {
            $svc_password = $password;
        }
        my $command = sprintf("check_snclient!%s -p '%s' -u 'https://%s:%s' %s",
                _check_nsc_web_extra_options($c),
                $svc_password,
                '$HOSTADDRESS$',
                '$_HOSTAGENT_PORT$',
                $chk->{'check'},
        );
        my $interval = $c->config->{'Thruk::Agents'}->{'snclient'}->{'check_interval'} // 1;
        if($chk->{'check'} eq 'inventory') {
            $command  = sprintf("check_thruk_agents!agents check inventory '%s'", $hostname);
            $interval = $c->config->{'Thruk::Agents'}->{'snclient'}->{'inventory_interval'} // 60;
        }
        if($chk->{'args'}) {
            if(ref $chk->{'args'} eq 'ARRAY') {
                for my $arg (@{$chk->{'args'}}) {
                    $command .= sprintf(" %s", $arg);
                }
            } else {
                for my $arg (sort keys %{$chk->{'args'}}) {
                    $command .= sprintf(" %s='%s'", $arg, $chk->{'args'}->{$arg});
                }
            }
        }

        $chk->{'name'} =~ s|[`~!\$%^&*\|'"<>?,()=]*||gmx; # remove nasty chars from object name
        $chk->{'name'} =~ s|\\$||gmx; # remove trailing slashes from service names, in windows drives

        $chk->{'svc_conf'} = {
            'host_name'           => $hostname,
            'service_description' => $chk->{'name'},
            'use'                 => ['generic-service'],
            'check_interval'      => $interval,
            'check_command'       => $command,
            '_AGENT_AUTO_CHECK'   => $chk->{'id'},
        };
        $chk->{'svc_conf'}->{'parents'} = $chk->{'parent'} if $chk->{'parent'};
        $chk->{'args'} = "";

        for my $attr (qw/contacts contactgroups/) {
            my $data = Thruk::Base::list($c->config->{'Thruk::Agents'}->{'snclient'}->{'default_'.$attr});
            $data    = Thruk::Base::comma_separated_list(join(",", @{$data}));
            if(scalar @{$data} > 0) {
                $chk->{'svc_conf'}->{$attr} = join(",", @{$data});
            }
        }
    }

    return $checks;
}

##########################################################

=head2 make_info

    make_info($data)

returns check info as string

=cut
sub make_info {
    my($data) = @_;
    return(Thruk::Utils::dump_params($data, 5000, 0));
}

##########################################################

=head2 make_name

    make_name($template, $macros)

returns check name based on template

=cut
sub make_name {
    my($tmpl, $macros) = @_;
    my $name = $tmpl;
    if($macros) {
        for my $key (sort keys %{$macros}) {
            my $val = $macros->{$key};
            $name =~ s|$key|$val|gmx;
        }
    }
    $name =~ s/\s*$//gmx;
    $name =~ s/^\s*//gmx;
    return($name);
}

##########################################################

=head2 check_host_match

    check_host_match($config)

returns true if checks is enabled on this host

=cut
sub check_host_match {
    my($hosts) = @_;
    return(Thruk::Utils::Agents::check_wildcard_match($Thruk::Globals::HOSTNAME, $hosts));
}

##########################################################
sub _check_nsc_web_extra_options {
    my($c) = @_;
    return(    $c->config->{'Thruk::Agents'}->{'snclient'}->{'check_nsc_web_extra_options'}
            // $settings->{'check_nsc_web_extra_options'}
    );
}

##########################################################

1;