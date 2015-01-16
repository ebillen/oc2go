#!/usr/bin/perl -w

use strict;
use LWP::UserAgent;
use JSON;
use DateTime::Format::ISO8601;
use utf8;

# ===========================================
# Hier Username bei opencaching.de eintragen:
#
my $oc_user = "hier_usernamen_eintragen";
#
# Hier den Consumer key eintragen:
#
my $oc_consumer_key = "hier_consumer_key_eintragen";
#
#
# Trennzeichen zwischen den Feldern in der csv-Datei:
# \t = Tab-Zeichen
my $separator = "\t"; 
# Zeichen, mit dem die Felder "geklammert" werden, z.B.
# Anfuerungszeichen. Default: leer.
my $quote = "";
#
#
my $filename = "oc_stat.csv";
#
#
# ===========================================

utf8::encode($oc_user);

my $okapi_url = "http://www.opencaching.de/okapi";

my $fh;
open($fh, ">", $filename) or die "Could not open $filename for writing!";

binmode($fh, ":utf8");

# los geht's:
my $ua = LWP::UserAgent->new();
my $json = JSON->new->utf8();
my $resp;

my $uuid; # User ID at opencaching.de

$resp = $ua->get($okapi_url . 
		 "/services/users/by_username?" .
		 "username=$oc_user&" .
		 "fields=uuid&" .
		 "consumer_key=$oc_consumer_key");

if ($resp->is_success) {
    my $data = $json->decode($resp->decoded_content);

    $uuid = $data->{uuid};

    print "Username: " . $oc_user . "\n";
    print "User-ID:  $uuid\n";
}
else {
    my $error = $json->decode($resp->decoded_content);

    print "Username:     " . $oc_user . "\n\n";
    
    print "Error:        " . $error->{error}->{status} . "\n";
    print "Parameter:    " . $error->{error}->{parameter} . "\n";
    print "What's wrong: " . $error->{error}->{whats_wrong_about_it} . "\n";
    print "Dev.-Message: " . $error->{error}->{developer_message} . "\n";

    die $resp->status_line;
}

my $more = 1;
my $limit = 10;
my $offset = 0;

while ($more) {
    my $n_logs = 0;
    
    $resp = $ua->get($okapi_url . 
		     "/services/logs/userlogs?" .
		     "user_uuid=$uuid&" .
		     "limit=$limit&" .
		     "offset=$offset&" .
		     "consumer_key=$oc_consumer_key");

    if ($resp->is_success) {
	my $data = $json->decode($resp->decoded_content);
	my $occode = "";

	foreach (@{$data}) {
	    $n_logs += 1;
	    my $log = $_;

	    my $dt = DateTime::Format::ISO8601->parse_datetime($log->{date});
	    
	    print $fh $quote . $log->{cache_code} . $quote . $separator;
	    print $fh $quote . $dt->ymd . $quote . $separator;
	    print $fh $quote . $dt->hms . $quote . $separator;
	    print $fh $quote . $log->{type} . $quote . $separator;


	    # $log enthaelt Cache-Code, Datum und Logtyp.
	    # Name und Besitzer muessen wir noch holen:
	
	    $resp = $ua->get($okapi_url . 
			     "/services/caches/geocache?" .
			     "cache_code=" . $log->{cache_code} . "&" .
			     "user_uuid=$uuid&" .
			     "fields=name|owner&" .
			     "consumer_key=$oc_consumer_key");
	    if ($resp->is_success) {
		my $data2 = $json->decode($resp->decoded_content);
		print $fh $quote . $data2->{name} . $quote . $separator;
		print $fh $quote . $data2->{owner}->{username} . $quote;
	    }
	    else {
		die $resp->status_line;
	    }  
	    print $fh "\n";
	}


	if ($n_logs < $limit) {
	    $more = 0;
	}
	else {
	    $more = 1;
	}

	$offset = $offset + $limit;

	print "Logs geladen: $offset...\n";
    }
    else {
	die $resp->status_line;
    }
}

close $fh;

