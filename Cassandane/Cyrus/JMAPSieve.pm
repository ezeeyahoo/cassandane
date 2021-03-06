#!/usr/bin/perl
#
#  Copyright (c) 2011-2019 FastMail Pty Ltd. All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#
#  3. The name "Fastmail Pty Ltd" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
#      FastMail Pty Ltd
#      PO Box 234
#      Collins St West 8007
#      Victoria
#      Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Fastmail Pty. Ltd."
#
#  FASTMAIL PTY LTD DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
#  INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY  AND FITNESS, IN NO
#  EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE FOR ANY SPECIAL, INDIRECT
#  OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
#  USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
#  TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
#  OF THIS SOFTWARE.
#

package Cassandane::Cyrus::JMAPSieve;
use strict;
use warnings;
use DateTime;
use JSON;
use JSON::XS;
use Mail::JMAPTalk 0.13;
use Data::Dumper;
use Storable 'dclone';
use File::Basename;
use IO::File;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;

use charnames ':full';

sub new
{
    my ($class, @args) = @_;

    my $config = Cassandane::Config->default()->clone();

    my ($maj, $min) = Cassandane::Instance->get_version();
    if ($maj == 3 && $min == 0) {
        # need to explicitly add 'body' to sieve_extensions for 3.0
        $config->set(sieve_extensions =>
            "fileinto reject vacation vacation-seconds imap4flags notify " .
            "envelope relational regex subaddress copy date index " .
            "imap4flags mailbox mboxmetadata servermetadata variables " .
            "body");
    }
    elsif ($maj < 3) {
        # also for 2.5 (the earliest Cyrus that Cassandane can test)
        $config->set(sieve_extensions =>
            "fileinto reject vacation vacation-seconds imap4flags notify " .
            "envelope relational regex subaddress copy date index " .
            "imap4flags body");
    }

    $config->set(caldav_realm => 'Cassandane',
                 conversations => 'yes',
                 httpmodules => 'carddav caldav jmap',
                 httpallowcompress => 'no',
                 jmap_nonstandard_extensions => 'yes');

    return $class->SUPER::new({
        config => $config,
        jmap => 1,
        adminstore => 1,
        services => [ 'imap', 'sieve', 'http' ]
    }, @args);
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
    $self->{jmap}->DefaultUsing([
        'urn:ietf:params:jmap:core',
        'https://cyrusimap.org/ns/jmap/sieve',
    ]);
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub test_sieve_get
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    my $target = "INBOX.target";

    xlog $self, "Install a sieve script filing all mail into a folder";
    my $script = <<EOF;
require ["fileinto"];\r
fileinto "$target";\r
EOF
    $self->{instance}->install_sieve_script($script);

    xlog "get all scripts";
    my $res = $jmap->CallMethods([
        ['SieveScript/get', {
            properties => ['name', 'isActive'],
         }, "R1"]]);
    $self->assert_not_null($res);
    $self->assert_str_equals('SieveScript/get', $res->[0][0]);
    $self->assert_str_equals('R1', $res->[0][2]);
    $self->assert_num_equals(1, scalar @{$res->[0][1]{list}});
    $self->assert_str_equals('test1', $res->[0][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[0][1]{list}[0]{isActive});

    my $id = $res->[0][1]{list}[0]{id};

    xlog "get script by id";
    $res = $jmap->CallMethods([
        ['SieveScript/get', {
            ids => [$id],
         }, "R2"]]);
    $self->assert_not_null($res);
    $self->assert_str_equals('SieveScript/get', $res->[0][0]);
    $self->assert_str_equals('R2', $res->[0][2]);
    $self->assert_num_equals(1, scalar @{$res->[0][1]{list}});
    $self->assert_str_equals('test1', $res->[0][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[0][1]{list}[0]{isActive});
    $self->assert_str_equals($script, $res->[0][1]{list}[0]{content});
}

sub test_sieve_set
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $script = <<EOF;
keep;\r
EOF

    my $jmap = $self->{jmap};

    xlog "create script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "$script"
                }
            }
         }, "R1"],
        ['SieveScript/get', {
            'ids' => [ '#1' ]
         }, "R2"]
    ]);
    $self->assert_not_null($res);
    $self->assert_equals(JSON::false, $res->[0][1]{created}{1}{isActive});

    $self->assert_num_equals(1, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals('foo', $res->[1][1]{list}[0]{name});
    $self->assert_equals(JSON::false, $res->[1][1]{list}[0]{isActive});

    my $id = $res->[0][1]{created}{"1"}{id};

    xlog "rename script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            update => {
                $id => {
                    name => "bar"
                }
            }
         }, "R3"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_null($res->[0][1]{notUpdated});

    $script = <<EOF;
# comment\r
discard;\r
EOF

    xlog "rewrite and activate script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            update => {
                $id => {
                    content => "$script",
                    isActive => JSON::true
                }
            }
         }, "R4"],
        ['SieveScript/get', {
         }, "R5"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_null($res->[0][1]{notUpdated});
    $self->assert_num_equals(1, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals('bar', $res->[1][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[1][1]{list}[0]{isActive});
    $self->assert_str_equals($script, $res->[1][1]{list}[0]{content});

    xlog "deactivate script and delete script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            update => {
                $id => {
                    isActive => JSON::false
                }
            },
            destroy => [ $id ]
         }, "R6"],
        ['SieveScript/get', {
         }, "R7"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_null($res->[0][1]{notUpdated});
    $self->assert_not_null($res->[0][1]{destroyed});
    $self->assert_null($res->[0][1]{notDestroyed});
    $self->assert_num_equals(0, scalar @{$res->[1][1]{list}});
}

sub test_sieve_set_bad_script
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    xlog "create bad script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "keepme;\r\n"
                }
            }
         }, "R1"]
    ]);
    $self->assert_not_null($res);
    $self->assert_null($res->[0][1]{created});
    $self->assert_str_equals('invalidScript', $res->[0][1]{notCreated}{1}{type});

    xlog "update bad script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "keep;\r\n"
                }
            },
            update => {
                "#1" => {
                    content => "keepme;\r\n"
                }
            },
            destroy => [ "#1" ]
         }, "R2"]
    ]);
    $self->assert_not_null($res);

    my $id = $res->[0][1]{created}{"1"}{id};

    $self->assert_null($res->[0][1]{updated});
    $self->assert_str_equals('invalidScript', $res->[0][1]{notUpdated}{$id}{type});
    $self->assert_not_null($res->[0][1]{destroyed});
    $self->assert_str_equals($id, $res->[0][1]{destroyed}[0]);
    $self->assert_null($res->[0][1]{notDestroyed});
}

sub test_sieve_validate
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    xlog "validating scripts";
    my $res = $jmap->CallMethods([
        ['SieveScript/validate', {
            content => JSON::null
         }, "R1"],
        ['SieveScript/validate', {
            content => "keepme;\r\n",
            content => JSON::null
         }, "R2"],
        ['SieveScript/validate', {
            content => "keepme;\r\n"
         }, "R3"],
        ['SieveScript/validate', {
            content => "keep;\r\n"
         }, "R4"],
    ]);
    $self->assert_not_null($res);

    $self->assert_str_equals("error", $res->[0][0]);
    $self->assert_str_equals("invalidArguments", $res->[0][1]{type});

    $self->assert_str_equals("error", $res->[1][0]);
    $self->assert_str_equals("invalidArguments", $res->[1][1]{type});

    $self->assert_str_equals("SieveScript/validate", $res->[2][0]);
    $self->assert_equals(JSON::false, $res->[2][1]{isValid});
    $self->assert_not_null($res->[2][1]{errorDescription});

    $self->assert_str_equals("SieveScript/validate", $res->[3][0]);
    $self->assert_equals(JSON::true, $res->[3][1]{isValid});
    $self->assert_null($res->[3][1]{errorDescription});
}

1;
