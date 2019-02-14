#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use JSON;
use JSON::Validator;
use Log::Log4perl;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;


my $test_obj = {
    "name"         => "test8",
    "description"  => "",
    "workgroup_id" => 1,
    "schedule"     => { "start" => -1, "end" => -1 },
    "endpoints"    => [
        {
            "bandwidth"        => 0,
            "outer_tag"        => 1,
            "inner_tag"        => 1,
            "cloud_account_id" => "***",
            "node"             => "mx960-1",
            "interface"        => "aws"
        },
        {
            "bandwidth"        => 0,
            "outer_tag"        => 1,
            "cloud_account_id" => "",
            "entity"           => "second"
        }
    ]
};


my $server = GRNOC::WebService::Dispatcher->new();

my $method = GRNOC::WebService::Method->new(
	name            => 'provision',
	description     => 'provision a layer2 circuit',
	callback        => sub {
        my $method = shift;
        my $params = shift;

        warn Dumper($method);
        warn Dumper($method->{dispatcher}->{cgi}->param);

        eval {
            my $validator = JSON::Validator->new;
            $validator->schema({
                type       => "object",
                required   => [ "name", "workgroup_id", "endpoints" ],
                properties => {
                    "name"         => { type => "string" },
                    "workgroup_id" => { type => "integer", minimum => 1 },
                    "endpoints"    => {
                        type  => "array",
                        items => {
                            anyOf => [
                                {
                                    type       => "object",
                                    required   => [ "bandwidth", "outer_tag", "entity" ],
                                    properties => {
                                        bandwidth => { type => "integer", minimum => 0, maximum => 10000 },
                                        inner_tag => { type => "integer", minimum => 1, maximum =>  4095 },
                                        outer_tag => { type => "integer", minimum => 1, maximum =>  4095 },
                                        entity    => { type => "string" },
                                        cloud_account_id => { type => "string" }
                                    }
                                },
                                {
                                    type       => "object",
                                    required   => [ "bandwidth", "outer_tag", "node", "interface" ],
                                    properties => {
                                        bandwidth => { type => "integer", minimum => 0, maximum => 10000 },
                                        inner_tag => { type => "integer", minimum => 1, maximum =>  4095 },
                                        outer_tag => { type => "integer", minimum => 1, maximum =>  4095 },
                                        node      => { type => "string" },
                                        interface => { type => "string" },
                                        cloud_account_id => { type => "string" }
                                    }
                                }
                            ]
                        }
                    },
                    "description"  => { type => "string" },
                    "schedule"     => {
                        type       => "object",
                        required   => [ "start", "end" ],
                        properties => {
                            start => { type => "integer" },
                            end   => { type => "integer" }
                        }
                    }
                }
            });

            my $data = $method->{dispatcher}->{cgi}->param('payload');
            my $json = decode_json($data);

            my @errs = $validator->validate($json);
            die "@errs" if @errs;

            warn Dumper($json);
        };
        if ($@) {
            $method->set_error($@);
            return;
        }

        return { status => "ok" };
    }
);


$server->register_method($method);
$server->handle_request();
