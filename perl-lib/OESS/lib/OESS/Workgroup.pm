#!/usr/bin/perl

use strict;
use warnings;

package OESS::Workgroup;

use OESS::DB::Workgroup;
use Data::Dumper;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        db => undef,
        model => undef,
        logger => Log::Log4perl->get_logger("OESS.Workgroup"),
        @_
    };
    bless $self, $class;

    if (!defined $self->{db}) {
        $self->{logger}->debug('Optional argument `db` is missing. Cannot save object to database.');
    }

    if (defined $self->{db} && defined $self->{workgroup_id}) {
        eval {
            $self->{model} = OESS::DB::Workgroup::fetch(
                db => $self->{db},
                workgroup_id => $self->{workgroup_id}
            );
        };
        if ($@) {
            $self->{logger}->error("Couldn't load workgroup: $@");
        }
        if (!defined $self->{model}) {
            $self->{logger}->error("Couldn't find workgroup.");
            return;
        }

    } elsif (!defined $self->{model}) {
        $self->{logger}->debug('Optional argument `model` is missing.');
        return;
    }

    $self->from_hash($self->{model});

    return $self;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'workgroup_id'} = $hash->{'workgroup_id'};
    $self->{'name'} = $hash->{'name'};
    $self->{'type'} = $hash->{'type'};
    $self->{'max_circuits'} = $hash->{'max_circuits'};
    $self->{'external_id'} = $hash->{'external_id'};

    if (defined $hash->{interfaces}) {
        $self->{interfaces} = [];
        foreach my $int (@{$hash->{interfaces}}) {
            push @{$self->{interfaces}}, OESS::Interface->new(db => $self->{db}, model => $int);
        }
    }

    if (defined $hash->{users}) {
        $self->{users} = [];
        foreach my $user (@{$hash->{users}}) {
            push @{$self->{users}}, OESS::User->new(db => $self->{db}, model => $user);
        }
    }
    return 1;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $obj = {
        workgroup_id => $self->workgroup_id,
        name         => $self->name,
        type         => $self->type,
        external_id  => $self->external_id,
        max_circuits => $self->max_circuits
    };

    if (defined $self->users) {
        $obj->{users} = [];
        foreach my $user (@{$self->users}) {
            push @{$self->{users}}, $user->to_hash;
        }
    }

    if (defined $self->interfaces) {
        $obj->{interfaces} = [];
        foreach my $int (@{$self->interfaces}) {
            push @{$obj->{interfaces}}, $int->to_hash;
        }
    }

    return $obj;
}

=head2 max_circuits

=cut
sub max_circuits{
    my $self = shift;
    return $self->{'max_circuits'};
}

=head2 workgroup_id

=cut
sub workgroup_id{
    my $self = shift;
    my $workgroup_id = shift;

    if(!defined($workgroup_id)){
        return $self->{'workgroup_id'};
    }else{
        $self->{'workgroup_id'} = $workgroup_id;
        return $self->{'workgroup_id'};
    }
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;

    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

=head2 users

=cut
sub users{
    my $self = shift;
    return $self->{'users'};
}

=head2 interfaces

=cut
sub interfaces{
    my $self = shift;
    return $self->{'interfaces'};
}

=head2 load_interfaces

=cut
sub load_interfaces {
    my $self = shift;

    eval {
        my $interfaces = OESS::DB::Interface::get_interfaces_hash(
            db => $self->{db},
            workgroup_id => $self->{workgroup_id}
        );

        $self->{interfaces} = [];
        foreach my $interface (@$interfaces) {
            warn Dumper($interface);
            push @{$self->{interfaces}}, OESS::Interface->new(db => $self->{db}, model => $interface);
        }
    };
    if ($@) {
        return "Couldn't load interfaces for workgroup $self->{workgroup_id}: $@";
    }
    return;
}

=head2 type

=cut
sub type{
    my $self = shift;
    my $type = shift;

    if(!defined($type)){
        return $self->{'type'};
    }else{
        $self->{'type'} = $type;
        return $self->{'type'};
    }
}

=head2 external_id

=cut
sub external_id{
    my $self = shift;
    return $self->{'external_id'};
}

1;
