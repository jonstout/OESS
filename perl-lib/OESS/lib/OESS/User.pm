#!/usr/bin/perl

use strict;
use warnings;

package OESS::User;

use OESS::DB::User;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        user_id => undef,
        username => undef,
        db => undef,
        model => undef,
        logger => Log::Log4perl->get_logger("OESS.User"),
        @_
    };
    bless $self, $class;

    if (!defined $self->{db}) {
        $self->{logger}->debug('Optional argument `db` is missing. Cannot save object to database.');
    }

    if (defined $self->{db} && (defined $self->{user_id} || defined $self->{username})) {
        eval {
            $self->{model} = OESS::DB::User::get(
                db => $self->{db},
                user_id => $self->{user_id},
                username => $self->{username}
            );
        };
        if ($@) {
            $self->{logger}->error("Couldn't load user: $@");
            return;
        }
        if (!defined $self->{model}) {
            $self->{logger}->error("Couldn't find user.");
            return;
        }

        #if (!$self->{shallow}) {
            eval {
                $self->{model}->{workgroups} = OESS::DB::User::get_workgroups(
                    db => $self->{db},
                    user_id => $self->{user_id}
                );
            };
            if ($@) {
                $self->{logger}->warn("Couldn't load workgroups for user $self->{user_id}.");
                $self->{model}->{workgroups} = [];
            }
        #}

    } elsif (!defined $self->{model}) {
        $self->{logger}->debug('Optional argument `model` is missing.');
        return;
    }

    $self->from_hash($self->{model});

    return $self;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    my $args = {
        shallow => 0,
        @_
    };

    my $obj = {
        user_id    => $self->user_id(),
        username   => $self->username(),
        first_name => $self->first_name(),
        last_name  => $self->last_name(),
        email      => $self->email(),
        type       => $self->type(),
        is_admin   => $self->is_admin()
    };

    if (!$args->{shallow}) {
        $obj->{workgroups} = [];
        foreach my $wg (@{$self->workgroups()}){
            push @{$obj->{workgroups}}, $wg->to_hash(shallow => 1);
        }
    }

    return $obj;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{user_id}    = $hash->{user_id};
    $self->{username}   = $hash->{username};
    $self->{first_name} = $hash->{first_name};
    $self->{last_name}  = $hash->{last_name};
    $self->{email}      = $hash->{email};
    $self->{type}       = $hash->{type};
    $self->{is_admin}   = $hash->{is_admin};

    $self->{'workgroups'} = [];
    foreach my $model (@{$hash->{workgroups}}) {
        push @{$self->{workgroups}}, OESS::Workgroup->new(db => $self->{db}, model => $model);
    }

    return 1;
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;


    return;
}

=head2 first_name

=cut
sub first_name{
    my $self = shift;
    return $self->{'first_name'};
}

=head2 last_name

=cut
sub last_name{
    my $self = shift;
    return $self->{'last_name'};

}

=head2 user_id

=cut
sub user_id{
    my $self = shift;
    return $self->{'user_id'};
}

=head2 username

=cut
sub username{
    my $self = shift;
    return $self->{'username'};
}

=head2 workgroups

=cut
sub workgroups{
    my $self = shift;
    return $self->{'workgroups'} || [];
}

=head2 email

=cut
sub email{
    my $self = shift;
    return $self->{'email'};
}

=head2 is_admin

=cut
sub is_admin{
    my $self = shift;
    return $self->{'is_admin'};
}

=head2 in_workgroup

=cut
sub in_workgroup{
    my $self = shift;
    my $workgroup_id = shift;

    foreach my $wg (@{$self->workgroups()}){
        if($wg->workgroup_id() == $workgroup_id){
            return 1;
        }
    }
    return 0;
}

=head2 type

=cut
sub type{
    my $self = shift;
    return $self->{'type'};
}

1;
