#!/usr/bin/perl
#
#  Copyright (c) 2011 Opera Software Australia Pty. Ltd.  All rights
#  reserved.
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
#  3. The name "Opera Software Australia" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
# 	Opera Software Australia Pty. Ltd.
# 	Level 50, 120 Collins St
# 	Melbourne 3000
# 	Victoria
# 	Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Opera Software
#     Australia Pty. Ltd."
#
#  OPERA SOFTWARE AUSTRALIA DISCLAIMS ALL WARRANTIES WITH REGARD TO
#  THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS, IN NO EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE
#  FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
#  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
#  OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

use strict;
use warnings;
package Cassandane::Cyrus::Conversations;
use base qw(Cassandane::Cyrus::TestCase);
use DateTime;
use URI::Escape;
use Digest::SHA1 qw(sha1_hex);
use Cassandane::ThreadedGenerator;
use Cassandane::Util::Log;
use Cassandane::Util::DateTime qw(to_iso8601 from_iso8601
				  from_rfc822
				  to_rfc3501 from_rfc3501);

sub new
{
    my ($class, @args) = @_;
    my $config = Cassandane::Config->default()->clone();
    $config->set(conversations => 'on');
    return $class->SUPER::new({ config => $config }, @args);
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
    $self->{store}->set_fetch_attributes('uid', 'cid');
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

# Calculate a CID from a message - this is the CID that the
# first message in a new conversation will be assigned.
sub calc_cid
{
    my ($msg) = @_;
    return substr(sha1_hex($msg->as_string()), 0, 16);
}

# The resulting CID when a clash happens is supposed to be
# the MAXIMUM of all the CIDs.  Here we use the fact that
# CIDs are expressed in a form where lexical order is the
# same as numeric order.
sub choose_cid
{
    my (@cids) = @_;
    @cids = sort { $b cmp $a } @cids;
    return $cids[0];
}

#
# Test APPEND of messages to IMAP
#
sub test_append
{
    my ($self) = @_;
    my %exp;

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($self->{store}->get_client()->capability()->{xconversations});

    xlog "generating message A";
    $exp{A} = $self->make_message("Message A");
    $exp{A}->set_attributes(uid => 1, cid => calc_cid($exp{A}));
    $self->check_messages(\%exp);

    xlog "generating message B";
    $exp{B} = $self->make_message("Message B");
    $exp{B}->set_attributes(uid => 2, cid => calc_cid($exp{B}));
    $self->check_messages(\%exp);

    xlog "generating message C";
    $exp{C} = $self->make_message("Message C");
    $exp{C}->set_attributes(uid => 3, cid => calc_cid($exp{C}));
    my $actual = $self->check_messages(\%exp);

    xlog "generating message D";
    $exp{D} = $self->make_message("Message D");
    $exp{D}->set_attributes(uid => 4, cid => calc_cid($exp{D}));
    $self->check_messages(\%exp);
}


#
# Test APPEND of messages to IMAP which results in a CID clash.
#
sub test_append_clash
{
    my ($self) = @_;
    my %exp;

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($self->{store}->get_client()->capability()->{xconversations});

    xlog "generating message A";
    $exp{A} = $self->make_message("Message A");
    $exp{A}->set_attributes(uid => 1, cid => calc_cid($exp{A}));
    $self->check_messages(\%exp);

    xlog "generating message B";
    $exp{B} = $self->make_message("Message B");
    $exp{B}->set_attributes(uid => 2, cid => calc_cid($exp{B}));
    my $actual = $self->check_messages(\%exp);

    xlog "generating message C";
    my $ElCid = choose_cid($exp{A}->get_attribute('cid'),
			   $exp{B}->get_attribute('cid'));
    $exp{C} = $self->make_message("Message C",
				  references =>
				       $exp{A}->get_header('message-id') .  ", " .
				       $exp{B}->get_header('message-id'),
				 );
    $exp{C}->set_attributes(uid => 3, cid => $ElCid);

    # Since IRIS-293, inserting this message will have the side effect
    # of renumbering some of the existing messages.  Predict and test
    # which messages get renumbered.
    my $nextuid = 4;
    foreach my $s (qw(A B))
    {
	if (calc_cid($actual->{"Message $s"}) ne $ElCid)
	{
	    $exp{$s}->set_attributes(uid => $nextuid, cid => $ElCid);
	    $nextuid++;
	}
    }

    $self->check_messages(\%exp);
}

#
# Test APPEND of messages to IMAP which results in multiple CID clashes.
#
sub test_double_clash
{
    my ($self) = @_;
    my %exp;

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($self->{store}->get_client()->capability()->{xconversations});

    xlog "generating message A";
    $exp{A} = $self->make_message("Message A");
    $exp{A}->set_attributes(uid => 1, cid => calc_cid($exp{A}));
    $self->check_messages(\%exp);

    xlog "generating message B";
    $exp{B} = $self->make_message("Message B");
    $exp{B}->set_attributes(uid => 2, cid => calc_cid($exp{B}));
    $self->check_messages(\%exp);

    xlog "generating message C";
    $exp{C} = $self->make_message("Message C");
    $exp{C}->set_attributes(uid => 3, cid => calc_cid($exp{C}));
    my $actual = $self->check_messages(\%exp);

    xlog "generating message D";
    my $ElCid = choose_cid($exp{A}->get_attribute('cid'),
			   $exp{B}->get_attribute('cid'),
			   $exp{C}->get_attribute('cid'));
    $exp{D} = $self->make_message("Message D",
				  references =>
				       $exp{A}->get_header('message-id') .  ", " .
				       $exp{B}->get_header('message-id') .  ", " .
				       $exp{C}->get_header('message-id'),
				 );
    $exp{D}->set_attributes(uid => 4, cid => $ElCid);

    # Since IRIS-293, inserting this message will have the side effect
    # of renumbering some of the existing messages.  Predict and test
    # which messages get renumbered.
    my $nextuid = 5;
    foreach my $s (qw(A B C))
    {
	if (calc_cid($actual->{"Message $s"}) ne $ElCid)
	{
	    $exp{$s}->set_attributes(uid => $nextuid, cid => $ElCid);
	    $nextuid++;
	}
    }

    $self->check_messages(\%exp);
}

#
# Test that a CID clash resolved on the master is replicated
#
sub test_replication_clash
{
    my ($self) = @_;
    my %exp;

    xlog "set up a master and replica pair";
    my $conf = $self->{instance}->{config};
    my ($master, $replica, $master_store, $replica_store) =
	Cassandane::Instance->start_replicated_pair(config => $conf);

    $master_store->set_fetch_attributes('uid', 'cid');
    $replica_store->set_fetch_attributes('uid', 'cid');

    # Double check that we're connected to the servers
    # we wanted to be connected to.
    $self->assert($master_store->{host} eq $replica_store->{host});
    $self->assert($master_store->{port} != $replica_store->{port});

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($master_store->get_client()->capability()->{xconversations});
    $self->assert($replica_store->get_client()->capability()->{xconversations});

    xlog "generating message A";
    $exp{A} = $self->make_message("Message A", store => $master_store);
    $exp{A}->set_attributes(uid => 1, cid => calc_cid($exp{A}));
    Cassandane::Instance->run_replication($master, $replica,
					  $master_store, $replica_store);
    $self->check_messages(\%exp, store => $master_store);
    $self->check_messages(\%exp, store => $replica_store);

    xlog "generating message B";
    $exp{B} = $self->make_message("Message B", store => $master_store);
    $exp{B}->set_attributes(uid => 2, cid => calc_cid($exp{B}));
    Cassandane::Instance->run_replication($master, $replica,
					  $master_store, $replica_store);
    $self->check_messages(\%exp, store => $master_store);
    $self->check_messages(\%exp, store => $replica_store);

    xlog "generating message C";
    $exp{C} = $self->make_message("Message C", store => $master_store);
    $exp{C}->set_attributes(uid => 3, cid => calc_cid($exp{C}));
    Cassandane::Instance->run_replication($master, $replica,
					  $master_store, $replica_store);
    my $actual = $self->check_messages(\%exp, store => $master_store);
    $self->check_messages(\%exp, store => $replica_store);

    xlog "generating message D";
    my $ElCid = choose_cid($exp{A}->get_attribute('cid'),
			   $exp{B}->get_attribute('cid'),
			   $exp{C}->get_attribute('cid'));
    $exp{D} = $self->make_message("Message D",
				  store => $master_store,
				  references =>
				       $exp{A}->get_header('message-id') .  ", " .
				       $exp{B}->get_header('message-id') .  ", " .
				       $exp{C}->get_header('message-id')
				 );
    $exp{D}->set_attributes(uid => 4, cid => $ElCid);

    # Since IRIS-293, inserting this message will have the side effect
    # of renumbering some of the existing messages.  Predict and test
    # which messages get renumbered.
    my $nextuid = 5;
    foreach my $s (qw(A B C))
    {
	if (calc_cid($actual->{"Message $s"}) ne $ElCid)
	{
	    $exp{$s}->set_attributes(uid => $nextuid, cid => $ElCid);
	    $nextuid++;
	}
    }

    Cassandane::Instance->run_replication($master, $replica,
					  $master_store, $replica_store);
    $self->check_messages(\%exp, store => $master_store);
    $self->check_messages(\%exp, store => $replica_store);
}

sub test_xconvfetch
{
    my ($self) = @_;
    my $store = $self->{store};

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($store->get_client()->capability()->{xconversations});

    xlog "generating messages";
    my $generator = Cassandane::ThreadedGenerator->new();
    $store->write_begin();
    while (my $msg = $generator->generate())
    {
	$store->write_message($msg);
    }
    $store->write_end();

    xlog "reading the whole folder again to discover CIDs etc";
    my %cids;
    my %uids;
    $store->read_begin();
    while (my $msg = $store->read_message())
    {
	my $uid = $msg->get_attribute('uid');
	my $cid = $msg->get_attribute('cid');
	my $threadid = $msg->get_header('X-Cassandane-Thread');
	if (defined $cids{$cid})
	{
	    $self->assert_num_equals($threadid, $cids{$cid});
	}
	else
	{
	    $cids{$cid} = $threadid;
	    xlog "Found CID $cid";
	}
	$self->assert_null($uids{$uid});
	$uids{$uid} = 1;
    }
    $store->read_end();

    xlog "Using XCONVFETCH on each conversation";
    foreach my $cid (keys %cids)
    {
	xlog "XCONVFETCHing CID $cid";

	my $result = $store->xconvfetch_begin($cid);
	$self->assert_not_null($result->{xconvmeta});
	$self->assert_num_equals(1, scalar keys %{$result->{xconvmeta}});
	$self->assert_not_null($result->{xconvmeta}->{$cid});
	$self->assert_not_null($result->{xconvmeta}->{$cid}->{modseq});
	while (my $msg = $store->xconvfetch_message())
	{
	    my $muid = $msg->get_attribute('uid');
	    my $mcid = $msg->get_attribute('cid');
	    my $threadid = $msg->get_header('X-Cassandane-Thread');
	    $self->assert_str_equals($cid, $mcid);
	    $self->assert_num_equals($cids{$cid}, $threadid);
	    $self->assert_num_equals(1, $uids{$muid});
	    $uids{$muid} |= 2;
	}
	$store->xconvfetch_end();
    }

    xlog "checking that all the UIDs in the folder were XCONVFETCHed";
    foreach my $uid (keys %uids)
    {
	$self->assert_num_equals(3, $uids{$uid});
    }
}

#
# Test APPEND of a new composed draft message to the Drafts folder by
# the Fastmail webui, which sets the X-ME-Message-ID header to thread
# conversations but not any of Message-ID, References, or In-Reply-To.
#
sub test_fm_webui_draft
{
    my ($self) = @_;
    my %exp;

    # check IMAP server has the XCONVERSATIONS capability
    $self->assert($self->{store}->get_client()->capability()->{xconversations});

    xlog "generating message A";
    $exp{A} = $self->{gen}->generate(subject => 'Draft message A');
    $exp{A}->remove_headers('Message-ID');
#     $exp{A}->add_header('X-ME-Message-ID', '<fake.header@i.am.a.draft>');
    $exp{A}->add_header('X-ME-Message-ID', '<fake1700@fastmail.fm>');
    $exp{A}->set_attribute(cid => calc_cid($exp{A}));

    $self->{store}->write_begin();
    $self->{store}->write_message($exp{A});
    $self->{store}->write_end();
    $self->check_messages(\%exp);

    xlog "generating message B";
    $exp{B} = $exp{A}->clone();
    $exp{B}->set_headers('Subject', 'Draft message B');
    $exp{B}->set_body("Completely different text here\r\n");

    $self->{store}->write_begin();
    $self->{store}->write_message($exp{B});
    $self->{store}->write_end();
    $self->check_messages(\%exp);
}

1;
