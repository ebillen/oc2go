#!/usr/bin/perl -w


# Use "cpan -i <module_name>" to install any missing modules together with their dependencies...
# When installed locally (as desktop user, not as root), you might have to set 
# PERL5LIB to help perl locating the modules:
# export PERL5LIB=~/perl5/lib/perl5/
use strict;
use lib qw(lib);
use File::chmod;
use File::HomeDir;
use File::Path;
use Getopt::Std;


# global variables:

my $CONFIGDIR;
my $AUTHCONFIG;
my %tokens=();
my $oc2go;
my $bookmarkfile;
my $zipfile;

$CONFIGDIR = File::HomeDir->my_home . "/.oc2go";
$AUTHCONFIG = $CONFIGDIR . "/oc2go_auth.cfg";

# default values for input/output files:
$bookmarkfile="oc2go_bookmarks.txt";
$zipfile="oc2go_caches.zip";

# parse command line options:
my %options=();
getopts("hiaf:", \%options);

if (defined $options{h}) {
    # print usage information and exit
    oc2go_usage();
    exit 0;
}

if (defined $options{i}) {
    # setup directories and configuration file(s) (if needed),
    # authorize to opencaching.de (if needed),
    # then exit.
    # 
    oc2go_install();
    oc2go_check_authorization();
    exit 0;
}

if (defined $options{f}) {
    # file name for bookmark list defined at the command line
    $bookmarkfile=$options{f};
    print "using $bookmarkfile for input...\n";
}


# ok, here we go...
# first, make sure that we are authorized:
oc2go_check_authorization();

# Ok, we should be authorized here.
# time to download some cool caches from opencaching.de...
oc2go_download_caches();

# that's it.
# bye...
exit 0;

######################################################################
# some subroutines:

sub oc2go_download_caches {
    my @bookmarklist;
    my $occachecode;

    open (BOOKMARKLIST, $bookmarkfile) or 
	die "Fatal: could not open " . $bookmarkfile . "\n" . $!;

    @bookmarklist = <BOOKMARKLIST>;


    foreach my $line (@bookmarklist) {
	next if $line =~ /^#/;    # skip comment lines
	next if $line =~ /^$/;    # skip empty lines
	($occachecode) = ($line =~ /\A(.*?) /);

	my $localfile = $CONFIGDIR . "/wrk/" . $occachecode . ".gpx";

	# download only, if local cache download is older than 1 day:
	my $now = time;
	my @stat = stat($localfile);

	if (-r $localfile) {
	    my $age_in_days = ($now - $stat[9])/86400;
	    if ($age_in_days < 1.0) {
		print "skipped $occachecode (last download was less then 24h ago)\n";
		next;
	    }
	}

	print "Trying to download " . $occachecode . "...\n";
	
	# download cache:
	my $occache=$oc2go->download_gpx($occachecode);

	# write cache to file:
	open(my $fh, ">", $localfile) or
	    die "Could not open " . $localfile . " for writing\n" . $!;
	print $fh $occache;
	close $fh;

	print "done.\n";
    
	# add result to zip file:
	print "zipping $occachecode...";
	system ("zip -q -j " . $zipfile . " " . $localfile);
	print "done.\n";

	# just be nice to the okapi server:
	sleep 1;
    }
}

sub oc2go_check_authorization {
    ### check of set authorization against opencaching.de... ###

    # Get the tokens from the command line, a config file or wherever 
    %tokens  = get_tokens(); 
    $oc2go     = Ocdl->new(%tokens);

    # Check to see we have a consumer key and secret
    unless ($oc2go->consumer_key && $oc2go->consumer_secret) {
	die "You must go get a consumer key and secret from opencacing.de\n";
    } 

    # If the app is authorized (i.e has an access token and secret),
    # skip the authorization stuff. Otherwise, prompt the user to
    # authorize at opencaching.de before downloading caches.

    if (!$oc2go->authorized) {
	# seems that we are not yet authorized at opencaching.de...
	print "You have to register at opencaching.de to use this script.\n\n";
#	print "URL : ".$oc2go->get_authorization_url( callback => 'oob' )."\n\n";
	print "DBG: " . $oc2go->authorization_url. "\n";
	print "URL: " . $oc2go->get_authorization_url( callback => 'oob' )."\n\n";
	print "Please go to the above URL and authorize using your opencaching.de credentials.\n";
	print "It will give you a code. Please type it here: ";
	my $verifier = <STDIN>; print "\n";
	chomp($verifier); $verifier =~ s!(^\s*|\s*$)!!g;
	$oc2go->verifier($verifier);
	
	my ($access_token, $access_token_secret) = $oc2go->request_access_token();

	print "You have now authorized this app.\n";
	print "Your access token and secret are:\n\n";
	print "access_token=$access_token\n";
	print "access_token_secret=$access_token_secret\n";
	print "\n";
	if (-f $AUTHCONFIG) {
	    save_tokens($oc2go);
	    print "You should note these down but they have also been saved in $AUTHCONFIG\n\n";
	} else {
	    print "You should note these down or put them in $AUTHCONFIG with your consumer key and secret\n\n";
	}
    
    }
    else {
	print "You are already authorized at opencaching.de to use this script\n";
	# TODO: print some information about the user,
	# like 'you are authorized with your opencaching account <alias>'...
    }
}


sub oc2go_install {
    ### set up directories and config file, if needed ###
    printf "Setting up directories and config file for oc2go.pl...\n";

    # create directory for config file etc., if needed:
#    $CONFIGDIR = File::HomeDir->my_home . "/.oc2go";
    if (-e $CONFIGDIR) {
	print "Configuration directory $CONFIGDIR already exists - ok.\n";
    }
    else {
	eval { File::Path->make_path($CONFIGDIR) };
	if ($@) {
	    print "Fatal: could not create configuration directory " . $CONFIGDIR . "!\n";
	    exit 1;
	}
	print "Created configuration directory $CONFIGDIR - ok.\n";
	eval { File::Path->make_path($CONFIGDIR . "/wrk") };
	if ($@) {
	    print "Fatal: could not create configuration directory " . $CONFIGDIR . "/wrk!\n";
	    exit 1;
	}
	print "Created work directory $CONFIGDIR/wrk - ok.\n";
    }



    # does the auth config file exist?
#    $AUTHCONFIG = $CONFIGDIR . "/oc2go_auth.cfg";
    if (-e $AUTHCONFIG) {
	print "Authorization config file $AUTHCONFIG already exists - ok.\n";
    }
    else {
	# create the authorization config file and put the consumer_key/consumer_secret
	# for oc2go.pl there:
	print "Info: configuration file " . $AUTHCONFIG . " does not exist.\n";
	print "Will create it now...\n";
	open(my $fh, ">", $AUTHCONFIG) or die "Could not open $AUTHCONFIG";
	# write the consumer_key and consumer_secret for oc2go to the config file:
	print $fh "consumer_key        = ZdVngbd6efEym7kUgmRE\n";
	print $fh "consumer_secret     = FJZCUcpPKVDBYqP7sS4wXyUaw6UCgB7NbXfVZvAB\n";
	close $fh;
	print "Config file created.\n\n";
    }

    # make sure that config file is readable and writable by user only:
    chmod("-rw-------", $AUTHCONFIG);

}


sub oc2go_usage {
    ### print usage ###
    print "Usage: oc2go.pl [OPTIONS]\n";
    print "Options:\n";
    print "  -f FILE\n";
    print "     use FILE as input for bookmarked caches\n";
    print "  -i\n";
    print "     create directories and config file (if needed)\n";
    print "  -h\n";
    print "     print (this) usage information and exit\n";
}

##############################################################

sub get_tokens {
    my %tokens = Ocdl->load_tokens($AUTHCONFIG);
    while (@ARGV && $ARGV[0] =~ m!^(\w+)\=(\w+)$!) {
        $tokens{$1} = $2;
        shift @ARGV;
    }
    return %tokens;
}

sub save_tokens {
    my $oc2go     = shift;
    my %tokens = $oc2go->tokens;
    Ocdl->save_tokens($AUTHCONFIG, %tokens);
}


#######################################

package Ocdl; # Openaching downloader...

use strict;
use base qw(Net::OAuth::Simple);


sub new {
    my $class  = shift;
    my %tokens = @_;
    
    return $class->SUPER::new( 
	tokens => \%tokens, 
	protocol_version => '1.0a',
	urls   => {
	    authorization_url => 'http://www.opencaching.de/okapi/services/oauth/authorize',
	    request_token_url => 'http://www.opencaching.de/okapi/services/oauth/request_token',
	    access_token_url  => 'http://www.opencaching.de/okapi/services/oauth/access_token',
	});
}

sub view_restricted_resource {
    my $self = shift;
    my $url = shift;
    print "URL: $url\n";
    return $self->make_restricted_request ($url, 'GET');
}

sub download_gpx {
    my $self = shift;
    my $cache_code = shift;
    my $gpx;

#    print "Cache: ". $cache_code . "\n";

    $gpx=$self->make_restricted_request("http://www.opencaching.de/okapi/services/caches/formatters/gpx",
					"GET",
					'cache_codes'      => $cache_code,
					'langpref'         => 'de',
					'ns_ground'        => 'true',
					'trackables'       => 'desc:list',
					'protection_areas' => 'desc:text',
					'images'           => 'descrefs:all',
					'recommendations'  => 'desc:count',
					'my_notes'         => 'gc:personal_note',
					'alt_wpts'         => 'true',
					'location_source'  => 'alt_wpt:user-coords',
					'location_change_prefix' => '(Solved) ',
					'mark_found'       => 'true',
					'latest_logs'      => 'true');

    return $gpx->content;
}


sub _make_restricted_request {
    my $self     = shift;
    my $response = $self->make_restricted_request(@_);
    return $response->content;
}


1;
