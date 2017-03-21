#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device;

use OESS::MPLS::Device::Juniper::MX;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant OESS_PW_FILE       => "/etc/oess/.passwd.xml";

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Device.' . $self->{'host_info'}->{'mgmt_addr'});
    $self->{'logger'}->debug("MPLS Device created");

    bless $self, $class;    
}

sub _get_credentials{
    my $self = shift;
    my $node_id = $self->{'node_id'};
    my $config = GRNOC::Config->new( config_file => OESS_PW_FILE );
    my $node = $config->{'doc'}->getDocumentElement()->find("/config/node[\@node_id='$node_id']")->[0];

    my $creds;
    if(!defined($node)){
        $creds = { username => $config->get("/config/\@default_user")->[0],
                   password => $config->get("/config/\@default_pw")->[0] };
    }else{
        $creds = XML::Simple::XMLin($node->toString(), ForceArray => 1);
    }

    if(!defined($creds)){
        warn "No Credentials found for node_id: " . $node_id . "\n";
	die;
    }

    return $creds;

}


sub connect{
    my $self = shift;

    $self->set_error("This device does not support connect");
    return;
}

sub disconnect{
    my $self = shift;

    $self->set_error("This device does not support disconnect");
    return;
}

sub get_system_information{
    my $self = shift;

    $self->set_error("This device does not support get_system_information");
    return;
}

sub get_interfaces{
    my $self = shift;

    $self->set_error("This device does not support get_interfaces");
    return;
}

sub get_isis_adjacencies{
    my $self = shift;
    
    $self->set_error("This device does not support get_isis_adjacencies");
    return;
}

sub get_LSPs{
    my $self = shift;

    $self->set_error("This device does not support get_LSPs");
    return;
}

sub add_vlan{
    my $self = shift;

    $self->set_error("This device does not support add_vlan");
    return;
}

sub remove_vlan{
    my $self = shift;

    $self->set_error("This device does not support remove_vlan");
    return;
}

sub diff {
    my $self = shift;

    $self->set_error("The device does not support diff");
    return;
}

=head2

Returns 1 if $diff may be applied without manual approval.

=cut
sub diff_approved {
    my $self = shift;
    my $diff = shift;

    $self->set_error("This device does not support large_diff");
}

sub set_error{
    my $self = shift;
    my $error = shift;
    $self->{'has_error'} = 1;
    push(@{$self->{'error'}}, $error);
}

sub has_error{
    my $self = shift;
    return $self->{'has_error'};
}

sub get_error{
    my $self = shift;

    my $errors = "";
    foreach my $error (@{$self->{'error'}}){
        $errors .= $error . "\n";
    }

    # Clear out the error for next time...
    $self->{'error'} = ();
    $self->{'has_error'} = 0;

    return $errors;
}

1;