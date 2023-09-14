#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2023 KUSANAGI Mitsuhisa <mikkun@mbg.nifty.com>
# SPDX-License-Identifier: Artistic-2.0

use 5.012;
use warnings;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

our $VERSION = '1.0.0';

use File::Basename;
use File::Spec;
use lib File::Spec->catdir( dirname(__FILE__), 'local/lib/perl5' );

use Array::Utils qw( array_minus );
use Authen::SASL qw( Perl );
use Encode       qw( decode encode );
use Encode::IMAPUTF7;
use Encode::MIME::Header;
use English    qw( -no_match_vars );
use HTTP::Date qw( time2isoz );
use IO::Socket::SSL;
use MIME::Base64 qw( encode_base64 );
use Mail::IMAPClient;
use Net::SMTP;

# Define configuration information
my $CONFIG = {
    IMAP => {
        USERNAME  => 'username@example.com',
        PASSWORD  => 'imap-password',
        TIMEOUT   => 30,
        NEEDS_SSL => 1,
        SERVER    => 'imap.example.com',
        PORT      => 993,
        FOLDERS   => [ 'FOO', 'BAR', 'BAZ', 'QUX' ],
    },
    SMTP => {
        USERNAME   => 'username@example.com',
        PASSWORD   => 'smtp-password',
        TIMEOUT    => 30,
        NEEDS_SSL  => 1,
        SERVER     => 'smtp.example.com',
        PORT       => 465,
        RECIPIENTS => [ 'alice@example.net', 'bob@example.org' ],
    },
    FILE =>
        { UID => File::Spec->catdir( dirname(__FILE__), '.uids.sav' ) },
    OUTPUT => 'STDERR',    # "JSON" or "STDERR"
};

local $OUTPUT_AUTOFLUSH = 1;

my $uid_file  = $CONFIG->{FILE}{UID};
my @prev_uids = ();

# Read previous unread message UIDs from the file
if ( -e $uid_file ) {
    open my $read_fh, '<', $uid_file
        or error("Cannot open $uid_file for reading.");
    chomp( @prev_uids = <$read_fh> );
    close $read_fh or error("Could not close $uid_file.");
}
else {
    open my $empty_fh, '>', $uid_file or error("Cannot create $uid_file.");
    close $empty_fh or error("Could not close $uid_file.");
}

# Connect to the IMAP server
my $imap = Mail::IMAPClient->new(
    User     => $CONFIG->{IMAP}{USERNAME},
    Password => $CONFIG->{IMAP}{PASSWORD},
    Timeout  => $CONFIG->{IMAP}{TIMEOUT},
    Ssl      => $CONFIG->{IMAP}{NEEDS_SSL},
    Server   => $CONFIG->{IMAP}{SERVER},
    Port     => $CONFIG->{IMAP}{PORT},
) or error('Could not connect to IMAP server.');

my @curr_uids = ();
my %header_fields_for;

if ( $imap->IsAuthenticated ) {
    my @folders
        = map { encode( 'IMAP-UTF-7', $_ ) } @{ $CONFIG->{IMAP}{FOLDERS} };

    # Retrieve UIDs of unread messages within the specified folders
FOLDER:
    for my $folder (@folders) {
        $imap->select($folder) or next FOLDER;

        my @unseen_uids = $imap->unseen;
        next FOLDER if !@unseen_uids;

        # Retrieve header information for each unread message
        for my $unseen_uid (@unseen_uids) {
            $header_fields_for{$unseen_uid}
                = $imap->parse_headers( $unseen_uid,
                    'Date', 'From', 'Subject' );
            if ( defined $header_fields_for{$unseen_uid} ) {
                push @curr_uids, $unseen_uid;
            }
        }
    }

    $imap->logout;
}

# Write current unread message UIDs to the file
open my $write_fh, '>', $uid_file
    or error("Cannot open $uid_file for writing.");
for my $curr_uid (@curr_uids) {
    print {$write_fh} $curr_uid, "\n";
}
close $write_fh or error("Could not close $uid_file.");

# Calculate and count new unread message UIDs
my @new_uids = array_minus( @curr_uids, @prev_uids );
our $new_msg_count = scalar @new_uids;
success('0 new message(s) found. No notification sent.') if !$new_msg_count;

# If there are new unread messages, generate the content of notifications
my $EMAIL_HEADER = <<"END_EMAIL_HEADER";
From: imap-email-notifier <$CONFIG->{SMTP}{USERNAME}>
To: $CONFIG->{SMTP}{RECIPIENTS}[0], other-recipients:;
Subject: $new_msg_count new message(s) arrived
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: base64
END_EMAIL_HEADER

my $n = 1;
my $header_fields_ref;
my $EMAIL_BODY = "# Found $new_msg_count new unread message(s)\n\n";

for my $new_uid (@new_uids) {
    $header_fields_ref = $header_fields_for{$new_uid};

    $EMAIL_BODY .= <<"END_EMAIL_BODY";
$n. @{ [ decode( 'MIME-Header', $header_fields_ref->{Subject}[0] ) ] }
    * From: @{ [ decode( 'MIME-Header', $header_fields_ref->{From}[0] ) ] }
    * Date: $header_fields_ref->{Date}[0]
END_EMAIL_BODY

    $n++;
}

# Connect to the SMTP server
my $smtp = Net::SMTP->new(
    Hello   => $CONFIG->{SMTP}{USERNAME},
    Timeout => $CONFIG->{SMTP}{TIMEOUT},
    SSL     => $CONFIG->{SMTP}{NEEDS_SSL},
    Host    => $CONFIG->{SMTP}{SERVER},
    Port    => $CONFIG->{SMTP}{PORT},
);

if ($smtp) {
    if (!$smtp->auth(
            $CONFIG->{SMTP}{USERNAME},
            $CONFIG->{SMTP}{PASSWORD},
        )
        )
    {
        $smtp->quit;
        error('SASL authentication failed.');
    }

    # Send notification emails
    $smtp->mail( $CONFIG->{SMTP}{USERNAME} );
    if ($smtp->recipient(
            @{ $CONFIG->{SMTP}{RECIPIENTS} },
            { SkipBad => 1 },
        )
        )
    {
        $smtp->data();
        $smtp->datasend($EMAIL_HEADER);
        $smtp->datasend("\n");
        $smtp->datasend( encode_base64( encode( 'UTF-8', $EMAIL_BODY ) ) );
        $smtp->dataend();
    }

    $smtp->quit;
}
else {
    error('Could not connect to SMTP server.');
}

success("$new_msg_count new message(s) found. Notification has been sent.");

# Constants and subroutines for reporting notification results
use constant HTTP_HEADER => <<'END_HTTP_HEADER';
Cache-Control: private, no-store, no-cache, must-revalidate
Content-Security-Policy: default-src 'none'; frame-ancestors 'none'
Content-Type: application/json
Referrer-Policy: no-referrer
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
END_HTTP_HEADER

sub error {
    my ($message) = @_;

    if ( uc $CONFIG->{OUTPUT} eq 'JSON' ) {
        my $HTTP_CONTENT = <<"END_HTTP_CONTENT";
{
    "status": "error",
    "emailSent": false,
    "messageCount": null,
    "error": "$message",
    "timestamp": "@{ [ _date_time() ] }"
}
END_HTTP_CONTENT

        print _http_response( HTTP_HEADER, $HTTP_CONTENT );
        exit;
    }
    else {
        die "$message ($!)\n";
    }
}

sub success {
    my ($message) = @_;

    if ( uc $CONFIG->{OUTPUT} eq 'JSON' ) {
        my $HTTP_CONTENT = <<"END_HTTP_CONTENT";
{
    "status": "success",
    "emailSent": @{ [ $new_msg_count ? 'true' : 'false' ] },
    "messageCount": $new_msg_count,
    "error": null,
    "timestamp": "@{ [ _date_time() ] }"
}
END_HTTP_CONTENT

        print _http_response( HTTP_HEADER, $HTTP_CONTENT );
        exit;
    }
    else {
        warn "$message\n";
        exit;
    }
}

sub _date_time {
    ( my $date_time = time2isoz() ) =~ tr/ /T/;

    return $date_time;
}

sub _http_response {
    my ( $header, $content ) = @_;

    my $response = $header . "\n" . $content;
    $response =~ s/\r?\n/\r\n/gsx;
    if ( "\r" ne "\015" ) {
        $response =~ tr/\r\n/\015\012/;
    }

    return $response;
}

__END__

=encoding utf8

=head1 NAME

imap-email-notifier - Email notifier for IMAP mailboxes

=head1 SYNOPSIS

    imap-email-notifier.pl

=head1 DESCRIPTION

This script connects to an IMAP server, retrieves unread messages
from specified folders, and sends notification emails about new
unread messages via an SMTP server.

=head1 OPTIONS

There are no command-line options for this script.
Configuration should be done within the script.

=head1 CONFIGURATION

The configuration information is stored in the C<$CONFIG> hash
within the script.

=head1 SEE ALSO

L<Mail::IMAPClient>, L<Net::SMTP>,
L<https://github.com/mikkun/imap-email-notifier>.

=cut
