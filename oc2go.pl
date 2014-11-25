#!/usr/bin/perl -w


# Use "cpan -i <module_name>" to install any missing modules together with their dependencies...
# When installed locally (as desktop user, not as root), you might have to set 
# PERL5LIB to help perl locating the modules:
# export PERL5LIB=~/perl5/lib/perl5/
use strict;
use lib qw(lib);
use File::HomeDir;
use File::Path;
use Getopt::Std;


# global variables:

my %Cfg;  # to hold settings from config file
my $VERSION="oc2go version 0.03";
my $CONFIGDIR;
my $AUTHCONFIG;
my $CONFIGFILE;
my %tokens=();
my $oc2go;

# Are we using Windows or a real operating system?
my $DIRSEP;
my $ZIP;
my $ZIPARGS;

if ($^O eq "linux") {
    # running on linux...
    $DIRSEP = '/';
    $ZIP = "zip";
    $ZIPARGS = " -q -j ";
}
elsif ($^O eq "MSWin32") {
    # running on Windows...
    $DIRSEP = '\\';
    $ZIP = "7z.exe";
    $ZIPARGS = " a ";
}
else {
    die "Unsupported operating system ($^O)\n";
}

$CONFIGDIR = File::HomeDir->my_home . $DIRSEP . ".oc2go";
$AUTHCONFIG = $CONFIGDIR . $DIRSEP . "oc2go_auth.cfg";
$CONFIGFILE = $CONFIGDIR . $DIRSEP . "oc2go.cfg";

# Get configuration for this script.
# * first, set some default parameters.
# * next, try to read the config file. Entries in
#   the config file will overwrite the default parameters.
# * finally, parse the command line options.
oc2go_getconfig();


# print some nice logo and ascii art:
# source for the ascii art:
# http://wwwkammerl.de/ascii/AsciiSignature.php
# print "==============================================\n";
print "\n";
print "                  d8888b.                     \n";
print "                      `88                     \n";
print ".d8888b. .d8888b. .aaadP' .d8888b. .d8888b.   \n";
print "88'  `88 88'  `\"\" 88'     88'  `88 88'  `88   \n";
print "88.  .88 88.  ... 88.     88.  .88 88.  .88   \n";
print "`88888P' `88888P' Y88888P `8888P88 `88888P'   \n";
print "ooooooooooooooooooooooooooo~~~~.88~ooooooooo  \n";
print "                           d8888P             \n\n";
# print "==============================================\n\n";
print "This is " . $VERSION . "\n\n";


# parse command line options:
my %options=();
getopts("hiaf:", \%options);

if (defined $options{h}) {
    # print usage information and exit
    oc2go_usage();
    exit 0;
}

if (defined $options{i} || ! -e $AUTHCONFIG) {
    # Option "-i" => explicit "installation" wanted
    # No $AUTHCONFIG found => first call of this script? => "installation"
    #
    # Try to create 
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
    $Cfg{'bookmarkfile'} = $options{f};
#    print "using " . $Cfg{'bookmarkfile'} . " for input...\n";
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

sub oc2go_getconfig {
# Get configuration for this script.
# * first, set some default parameters.
# * next, try to read the config file. Entries in
#   the config file will overwrite the default parameters.
# * finally, parse the command line options.

# If there is no configuration file, create a sample file.

    # default settings:
    # parameters for the OKAPI gpx formatter.
    # see here:
    # http://www.opencaching.de/okapi/services/caches/formatters/gpx.html
    # for a documentation.
    $Cfg{'langpref'}               = 'de';
    $Cfg{'trackables'}             = 'desc:list';
    $Cfg{'protection_areas'}       = 'desc:text';
    $Cfg{'images'}                 = 'descrefs:all';
    $Cfg{'recommendations'}        = 'desc:count';
    $Cfg{'location_source'}        = 'alt_wpt:user-coords';
    $Cfg{'location_change_prefix'} = '(Solved)';

    # Minimal age (in hours) for a geocache, befor it will be downloaded again.
    # If the last download is less than 'minage' hours ago, 
    # the geocache will be skipped.
    $Cfg{'minage'} = 24;

    # default filename for bookmark file:
    $Cfg{'bookmarkfile'} = 'oc2go_bookmarks.txt';
    # default filename for zip file:
    $Cfg{'zipfile'} = 'oc2go_caches.zip';
    
    # create sample config file, if it does not exist..
    unless (-e $CONFIGFILE) {
	print "Info: no configuration file . " . $CONFIGFILE . " found.\n";
	print "This is not a problem.\n";
	print "I will create a sample configuration file for you.\n";
	
	open (my $cfgfh, ">", $CONFIGFILE) or 
	    die "Could not open $CONFIGFILE for writing!";
	print $cfgfh "# sample configuration file for oc2go.pl\n";
	print $cfgfh "# format: key = value\n";
	print $cfgfh "# uncomment any setting you want to change.\n\n";
	print $cfgfh "# these are some parameters for the OKAPI gpx formatter,\n";
	print $cfgfh "# see http://www.opencaching.de/okapi/services/caches/formatters/gpx.html\n";
	print $cfgfh "# for a documentation.\n";
	print $cfgfh "#\n";
	print $cfgfh "# langpref               = de\n";
	print $cfgfh "# trackables             = desc:list\n";
	print $cfgfh "# protectionreas         = desc:text\n";
	print $cfgfh "# images                 = descrefs:all\n";
	print $cfgfh "# recommendations        = desc:count\n";
	print $cfgfh "# location_source        = alt_wpt:user-coords\n";
	print $cfgfh "# location_change_prefix = (Solved)\n";
	print $cfgfh "\n\n";
	print $cfgfh "# If a geocache was downloaded less then 'minage' hours ago,\n";
	print $cfgfh "# the script will skip the download. Set 'minage = 0' to force a download\n";
	print $cfgfh "# minage = 24\n";

	print $cfgfh "# default filenames:\n";
	print $cfgfh "# bookmarkfile           = oc2go_bookmarks.txt\n";
	print $cfgfh "# zipfile                = oc2go_caches.zip\n";

	close $cfgfh;
    }

    # try to read any configuration parameters from the config file:
    open (CONFIGFILE, $CONFIGFILE) or 
	die "Fatal: could not open " . $CONFIGFILE . "\n" . $!;

    while (<CONFIGFILE>) {
	chomp;
	s/#.*//;
	s/<\s+//;
	s/\s+$//;
	next unless length;
	my ($key, $value) = split(/\s*=\s*/, $_, 2);
	# print "key = " . $key . "\n";
	# print "val = " . $value . "\n";
	$Cfg{$key} = $value;
    }
    close (CONFIGFILE);
    
    # DBG: print configuration
    # foreach my $key (keys %Cfg) {
    # 	print $key . " = " . $Cfg{$key} . "\n";
    # }

}

sub oc2go_download_caches {
    my @bookmarklist;
    my $occachecode;

    my $cnt = 0;
    my $cnt_skipped = 0;

    print "Input:  " . $Cfg{'bookmarkfile'} . "\n";
    print "Output: " . $Cfg{'zipfile'} . "\n\n";

    open (BOOKMARKLIST, $Cfg{'bookmarkfile'}) or 
	die "Fatal: could not open " . $Cfg{'bookmarkfile'} . "\n" . $!;

    @bookmarklist = <BOOKMARKLIST>;


    foreach my $line (@bookmarklist) {
	next if $line =~ /^#/;    # skip comment lines
	next if $line =~ /^$/;    # skip empty lines

	print ".";
	$cnt = $cnt + 1;
	if ($cnt % 72 == 0) {
	    print "\n";
	}

	($occachecode) = ($line =~ /\A(.*?) /);

	my $localfile = $CONFIGDIR . $DIRSEP . 
	    "wrk" . $DIRSEP . $occachecode . ".gpx";

	# download only, if local cache download is older than $Cfg{'minage'} hours:
	my $now = time;
	my @stat = stat($localfile);

	if (-r $localfile) {
	    my $age_in_hours = ($now - $stat[9])/3600;
	    if ($age_in_hours < $Cfg{'minage'}) {
#		print "skipped $occachecode (last download was less then " . 
#		    $Cfg{'minage'} . " hours ago)\n";
		$cnt_skipped = $cnt_skipped +1;
		next;
	    }
	}

	# print "Trying to download " . $occachecode . "...\n";
	
	# download cache:
	my $occache=$oc2go->download_gpx($occachecode);

	# write cache to file:
	open(my $fh, ">", $localfile) or
	    die "Could not open " . $localfile . " for writing\n" . $!;
	print $fh $occache;
	close $fh;

	# print "done.\n";
    
	# add result to zip file:
	# print "zipping $occachecode...";
	system ($ZIP . $ZIPARGS . $Cfg{'zipfile'} . " " . $localfile);
	# print "done.\n";

	# just be nice to the okapi server:
	sleep 1;
    }

    print "\n\n";
    print "Done.\n";
    print $cnt_skipped . " out of " . $cnt . " geocaches were skipped,\n";
    print "because their last download was less than " . $Cfg{'minage'} . " hours ago.\n";
    print $cnt - $cnt_skipped . " caches were updated in " . $Cfg{'zipfile'} . "\n\n";

}

sub oc2go_check_authorization {
    ### check of set authorization against opencaching.de... ###

    # Get the tokens from the command line, a config file or wherever 
    %tokens  = get_tokens(); 
    $oc2go     = Ocdl->new(%tokens);

    # Check to see we have a consumer key and secret
    unless ($oc2go->consumer_key && $oc2go->consumer_secret) {
	die "You must get a consumer key and secret from opencacing.de\n";
    } 

    # If the app is authorized (i.e has an access token and secret),
    # skip the authorization stuff. Otherwise, prompt the user to
    # authorize at opencaching.de before downloading caches.

    if (!$oc2go->authorized) {
	# seems that we are not yet authorized at opencaching.de...
	print "You have to register at opencaching.de to use this script.\n\n";
#	print "DBG: " . $oc2go->authorization_url. "\n";
	print "URL: " . $oc2go->get_authorization_url( callback => 'oob' )."\n\n";
	print "Please go to the above URL and authorize using your opencaching.de credentials.\n";
	print "It will give you a numeric code. \n\n";
	print "Please type it here: ";
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
	print "You are authorized at opencaching.de as user " . $oc2go->get_username() . ".\n\n";
    }
}


sub oc2go_install {
    ### set up directories and config file, if needed ###
    printf "Setting up directories and config file for oc2go.pl...\n";

    # create directory for config file etc., if needed:
    if (-e $CONFIGDIR) {
	print "Configuration directory $CONFIGDIR already exists - ok.\n";
    }
    else {
	unless (mkdir $CONFIGDIR)  {
	    die "Fatal: could not create config directory " . $CONFIGDIR;
	}
	
	print "Created configuration directory $CONFIGDIR - ok.\n";

    }
    # create working directory:
    my $WRKDIR = $CONFIGDIR . $DIRSEP . "wrk";
    if (-e $WRKDIR) {
	print "Working directory $WRKDIR already exists - ok.\n";
    }
    else {
	unless (mkdir $WRKDIR) {
	    die "Fatal: could not create working directory " . $WRKDIR;
	}
	print "Created work directory $WRKDIR - ok.\n";
    }
    


    # does the auth config file exist?
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
    chmod 0600, $AUTHCONFIG;

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
					'cache_codes'            => $cache_code,
					'langpref'               => $Cfg{'langpref'},
					'ns_ground'              => 'true',
					'trackables'             => $Cfg{'trackables'},
					'protection_areas'       => $Cfg{'protection_areas'},
					'images'                 => $Cfg{'images'},
					'recommendations'        => $Cfg{'recommendations'},
					'my_notes'               => 'gc:personal_note',
					'alt_wpts'               => 'true',
					'location_source'        => $Cfg{'location_source'},
					'location_change_prefix' => "$Cfg{'location_change_prefix'} ",
					'mark_found'             => 'true',
					'latest_logs'            => 'true');

    return $gpx->content;
}

sub get_username {
    my $self = shift;
    my $response;
    
    $response=$self->make_restricted_request("http://www.opencaching.de/okapi/services/users/user",
					     "GET",
					     'fields' => 'username');

    # This might fail if the username contains characters like ':'... :-(
    my @foo = $response->content =~ /\{ \"(.*?)\"\:\"(.*?)\" \}/xg;

    return $foo[1];
}

#sub _make_restricted_request {
#    my $self     = shift;
#    my $response = $self->make_restricted_request(@_);
#    return $response->content;
#}


1;
