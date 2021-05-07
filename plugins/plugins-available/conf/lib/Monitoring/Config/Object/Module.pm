package Monitoring::Config::Object::Module;

use warnings;
use strict;

use parent 'Monitoring::Config::Object::Parent';

=head1 NAME

Monitoring::Config::Object::Module - Module Object Configuration

=head1 DESCRIPTION

Defaults for module objects

=cut

##########################################################

$Monitoring::Config::Object::Module::Defaults = {
    'name'                            => { type => 'STRING', cat => 'Extended' },
    'use'                             => { type => 'LIST', link => 'host', cat => 'Basic' },
    'register'                        => { type => 'BOOL', cat => 'Extended' },
};

$Monitoring::Config::Object::Module::IcingaSpecific = {
    'module_name'                     => { type => 'STRING', cat => 'Basic' },
    'path'                            => { type => 'STRING', cat => 'Basic' },
    'args'                            => { type => 'STRING', cat => 'Basic' },
    'module_type'                     => { type => 'CHOOSE', values => ['neb'], keys => [ 'neb' ], cat => 'Basic' },
};

$Monitoring::Config::Object::Module::ShinkenSpecific = {
    'module_name'                     => { type => 'STRING', cat => 'Basic' },
    'module_type'                     => { type => 'STRING', cat => 'Basic' },
    'modules'                         => { type => 'STRING', cat => 'Basic' },
    # Parameters used by various modules:
    'host'                            => { type => 'STRING', cat => 'Basic' },
    'port'                            => { type => 'INT', cat => 'Basic' },
    'mapping_command'                 => { type => 'STRING', cat => 'Basic' },
    'command_file'                    => { type => 'STRING', cat => 'Basic' },
    'config_file'                     => { type => 'STRING', cat => 'Basic' },
    'database_file'                   => { type => 'STRING', cat => 'Basic' },
    'ip_range'                        => { type => 'STRING', cat => 'Basic' },
    'mapping_command_interval'        => { type => 'STRING', cat => 'Basic' },
    'mapping_command_timeout'         => { type => 'STRING', cat => 'Basic' },
    'mapping_file'                    => { type => 'STRING', cat => 'Basic' },
    'max_logs_age'                    => { type => 'STRING', cat => 'Basic' },
    'method'                          => { type => 'STRING', cat => 'Basic' },
    'path'                            => { type => 'STRING', cat => 'Basic' },
    'property'                        => { type => 'STRING', cat => 'Basic' },
    'socket'                          => { type => 'STRING', cat => 'Basic' },
    'value'                           => { type => 'STRING', cat => 'Basic' },
};

##########################################################

=head1 METHODS

=head2 BUILD

return new object

=cut
sub BUILD {
    my $class    = shift || __PACKAGE__;
    my $coretype = shift;

    return unless($coretype eq 'any' or $coretype eq 'icinga' or $coretype eq 'shinken');

    my $standard = [];
    if($coretype eq 'any' or $coretype eq 'icinga') {
        $standard = [ 'module_name', 'path', 'args', 'module_type' ];
        for my $key (keys %{$Monitoring::Config::Object::Module::IcingaSpecific}) {
            $Monitoring::Config::Object::Module::Defaults->{$key} = $Monitoring::Config::Object::Module::IcingaSpecific->{$key};
        }
    } else {
        for my $key (keys %{$Monitoring::Config::Object::Module::IcingaSpecific}) {
            delete $Monitoring::Config::Object::Module::Defaults->{$key};
        }
    }

    if($coretype eq 'any' or $coretype eq 'shinken') {
        $standard = [ 'module_name', 'module_type', 'modules' ];
        for my $key (keys %{$Monitoring::Config::Object::Module::ShinkenSpecific}) {
            $Monitoring::Config::Object::Module::Defaults->{$key} = $Monitoring::Config::Object::Module::ShinkenSpecific->{$key};
        }
    } else {
        for my $key (keys %{$Monitoring::Config::Object::Module::ShinkenSpecific}) {
            delete $Monitoring::Config::Object::Module::Defaults->{$key};
        }
    }

    my $self = {
        'type'        => 'module',
        'primary_key' => 'module_name',
        'default'     => $Monitoring::Config::Object::Module::Defaults,
        'standard'    => $standard,
    };
    bless $self, $class;
    return $self;
}

##########################################################

1;
