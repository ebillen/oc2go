#!/usr/bin/perl -w


# Use "cpan -i <module_name>" to install any missing modules together with their dependencies...
# When installed locally (as desktop user, not as root), you might have to set 
# PERL5LIB to help perl locating the modules:
# export PERL5LIB=~/perl5/lib/perl5/
use strict;
use lib qw(lib);
use File::HomeDir;
use File::Path;
use File::Basename;
use Getopt::Std;
use XML::Twig;
use Archive::Zip;
use JSON;

# global variables:

my %Cfg;  # to hold settings from config file
my $VERSION="oc2go version 0.04b";
my $CONFIGDIR;
my $AUTHCONFIG;
my $CONFIGFILE;
my %tokens=();
my $oc2go;

# global variables used for parsing gpx XML-structure:
my $gpx_wpts;      # number of waypoints in current gpx file
my $gpx_persnote;  # personal cache note in current gpx file
my $gpx_recommendations; # number of recommendations for this cache
my $trackables;     # trackables in the cache
my $is_oconly;    

# Are we using Windows or a real operating system?
my $DIRSEP;

if ($^O eq "linux") {
    # running on linux...
    $DIRSEP = '/';
}
elsif ($^O eq "MSWin32") {
    # running on Windows...
    $DIRSEP = '\\';
}
else {
    die "Unsupported operating system ($^O)\n";
}

$CONFIGDIR = File::HomeDir->my_home . $DIRSEP . ".oc2go";
$AUTHCONFIG = $CONFIGDIR . $DIRSEP . "oc2go_auth.cfg";
$CONFIGFILE = $CONFIGDIR . $DIRSEP . "oc2go.cfg";

# create $CONFIGDIR, if it does not exist:
if (!-e $CONFIGDIR) {
    unless (mkdir $CONFIGDIR)  {
	die "Fatal: could not create config directory " . $CONFIGDIR;
    }
}

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
    $Cfg{'modgpx'}                 = '1';
    $Cfg{'get_recommendations'}    = '1';
    $Cfg{'get_trackables'}         = '1';
    $Cfg{'mark_oconly'}            = '1';
    $Cfg{'trace'}                  = 'nothing';

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
	print $cfgfh "# Modify the downloaded gpx file:\n";
	print $cfgfh "# modgpx = 1\n";
	
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
    
    if ($Cfg{'trace'} =~ 'config') {
	# print configuration
	foreach my $key (keys %Cfg) {
	    print $key . " = " . $Cfg{$key} . "\n";
	}
    }

}

sub oc2go_download_caches {
    my @bookmarklist;
    my $occachecode;

    my $cnt = 0;
    my $cnt_skipped = 0;

    print "Input:  " . $Cfg{'bookmarkfile'} . "\n";
    print "Output: " . $Cfg{'zipfile'} . "\n\n";

    my $trace = $Cfg{'trace'} =~ 'download';

    open (BOOKMARKLIST, $Cfg{'bookmarkfile'}) or 
	die "Fatal: could not open " . $Cfg{'bookmarkfile'} . "\n" . $!;

    @bookmarklist = <BOOKMARKLIST>;

    my $zipfile = Archive::Zip->new();

    foreach my $line (@bookmarklist) {
	next if $line =~ /^#/;    # skip comment lines
	next if $line =~ /^$/;    # skip empty lines

	print ".";
	$cnt = $cnt + 1;
	if ($cnt % 72 == 0) {
	    print "\n";
	}

	($occachecode) = split /[ \s]+/, $line, 2;

	my $localfile = $CONFIGDIR . $DIRSEP . 
	    "wrk" . $DIRSEP . $occachecode . ".gpx";

	# download only, if local cache download is older than $Cfg{'minage'} hours:
	my $now = time;
	my @stat = stat($localfile);

	if (-r $localfile) {
	    my $age_in_hours = ($now - $stat[9])/3600;
	    if ($age_in_hours < $Cfg{'minage'}) {
		print "skipped $occachecode (last download was less then " . 
		    $Cfg{'minage'} . " hours ago)\n" if ($trace);
		$cnt_skipped = $cnt_skipped +1;
		next;
	    }
	}

	print "Trying to download " . $occachecode . "...\n" if ($trace);
	
	# download cache:
	my $occache=$oc2go->download_gpx($occachecode);

	# write cache to file:
	open(my $fh, ">", $localfile) or
	    die "Could not open " . $localfile . " for writing\n" . $!;
	print $fh $occache;
	close $fh;

	print "done.\n" if ($trace);

	# do some modifications on the gpx file:
	if ($Cfg{'modgpx'}) {
	    print "\ntwigging the gpx file...\n" if ($trace);
	    parse_and_modify_gpx($occachecode);
	}

    
	# add result to zip file:
	print "adding $occachecode to zip..." if ($trace);
	#system ($ZIP . $ZIPARGS . $Cfg{'zipfile'} . " " . $localfile);
	$zipfile->addFile($localfile, basename($localfile));
	print "done.\n" if ($trace);

	# just be nice to the okapi server:
	# sleep 1;
	select(undef, undef, undef, 0.25);
    }

    $zipfile->writeToFileNamed($Cfg{'zipfile'});

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


sub parse_and_modify_gpx {
    my $cache_code = shift;

    my $trace = ($Cfg{'trace'} =~ "gpxparser");

    if ($trace) {
	print "===================================\n";
	print "gpx parser is starting on " . $cache_code . "...\n\n";
    }

    my $gpxinfile = $CONFIGDIR . $DIRSEP . "wrk" . $DIRSEP . $cache_code . ".gpx";
    my $outfile = $CONFIGDIR . $DIRSEP . "wrk" . $DIRSEP . $cache_code . ".gpx";

    $gpx_wpts = 0;       # number of waypoints in gpx file
    $gpx_persnote = "";  # personal note
    $gpx_recommendations = 0; # 
    $is_oconly = 0;

    if ($Cfg{'get_recommendations'}) {
	$gpx_recommendations = $oc2go->get_recommendations($cache_code);
    }

    if ($Cfg{'get_trackables'}) {
	$trackables = $oc2go->get_trackables($cache_code);
    }

    if ($Cfg{'mark_oconly'}) {
	$is_oconly = $oc2go->check_oconly($cache_code);
    }

    my $twig = XML::Twig->new(
	pretty_print => 'indented',
	twig_handlers => { 
	    'wpt' => \&gpx_parser_wpt,
	    'groundspeak:cache' => \&gpx_parser_gscache ,
	    'groundspeak:log' => \&gpx_parser_gslog ,
	}
	);

    # parse the gpx file:
    $twig->parsefile($gpxinfile);

    if ($trace) {
	print "=== begin personal note ===:\n";
	print $gpx_persnote . "\n";
	print "=== end personal note ===\n";
    }

    # Try to modify the gpx file:
    my $root = $twig->root;

    # Now, parse the personal note line by line and try
    # to extract a waypoint information from it.
    # Anything like 'Waypoint-Name: N/S DD° MM.MMM W/E DDD° MM.MMM'
    # will create an additional waypoint named 'Waypoint-Name'
    # in the gpx file.

    # split the personal note into lines:
    my @pnote = split /\n+/, $gpx_persnote;

    foreach (@pnote) {
	my $line = $_;

	if ($trace) {    
	    print "Analyzing: '" . $line . "'...\n";
	}

	next unless $line =~ /:/;               # ignore all lines without ':'

	my ($wpname, $wpcoordstring) = split /:/, $line;
#	$wpcoordstring =~ s/^ +//g;             # strip leading blanks
	$wpcoordstring =~ s/°/ /g;               # remove degree sign
	$wpcoordstring =~ s/\x{b0}/ /g;          # remove degree sign
	$wpcoordstring =~ s/\,/\./g;            # use '.' as decimal separator
	
	if ($trace) {    
	    print "waypoint name: $wpname\n";
	    print "(trimmed) waypoint string: '" . $wpcoordstring . "'\n";
	}

	my ($lat_ns, $lat_deg, $lat_min, $lon_we, $lon_deg, $lon_min) = 
	    ($wpcoordstring =~ /([NS])\s*(\d*)\s*([0-9]*\.?[0-9]*)\s*([EOW])\s*(\d*)\s*([0-9]*\.?[0-9]*).*/);

	if (!($lat_ns && $lat_deg && $lat_min && $lon_we && $lon_deg && $lon_min)) {
	    # we did'nt parse anything useful:
	    if ($trace) {
		print "skipped, failed to parse coordinates from $wpcoordstring\n";
	    }
	    next;
	}
	
	if ($trace) {    
	    print "lat_ns:  " . $lat_ns . "\n";
	    print "lat_deg: " . $lat_deg . "\n";
	    print "lat_min: " . $lat_min . "\n";
	    print "lon_we:  " . $lon_we . "\n";
	    print "lon_deg: " . $lon_deg . "\n";
	    print "lon_min: " . $lon_min . "\n";
	}    
	
	my $lat = $lat_deg + $lat_min/60.0;
	my $lon = $lon_deg + $lon_min/60.0;
	if ($lat_ns =~ /S/) { $lat = -$lat; };
	if ($lon_we =~ /W/) { $lon = -$lon; };
	
	# now, add a waypoint element to the gpx:
	my $wpt =  $root->insert_new_elt('last_child', 
					 'wpt', {
					     lat => $lat,
					     lon => $lon,
					 });
	
	# fill the new waypoint element with some more data.
	# it's important, that the waypoint name is '<OC-CODE>-<number>',
	# this will allow Locus Pro to import the new waypoint as a child
	# waypoint for the cache itself.
	$wpt->insert_new_elt('last_child', 'name', sprintf('%s-%d', $cache_code, $gpx_wpts));
	$wpt->insert_new_elt('last_child', 'cmt', 'added by oc2go.pl');
	$wpt->insert_new_elt('last_child', 'desc', $wpname);
	# Waypoint types:
	# * Final Location
	# * Parking Area
	# * Virtual Stage
	# * Reference Point
	# * Physical Stage
	# * Trailhead
	if ($wpname =~ /Fin/ || $wpname =~ /Final Location/) {
	    print "waypoint type detected: Final Location\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Final Location');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Final Location');
	}
	elsif ($wpname =~ /Park/ || $wpname =~ /park/ || $wpname =~ /Parking Area/) {
	    print "waypoint type detected: 'Parking Area'\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Parking Area');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Parking Area');
	}
	elsif ($wpname =~ /Virtual Stage/) {
	    print "waypoint type detected: 'Virtual Stage'\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Virtual Stage');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Virtual Stage');
	}
	elsif ($wpname =~ /Physical Stage/) {
	    print "waypoint type detected: 'Physical Stage'\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Physical Stage');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Physical Stage');
	}
	elsif ($wpname =~ /Trailhead/) {
	    print "waypoint type detected: 'Trailhead'\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Trailhead');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Trailhead');
	}
	else {
	    # default: Reference Point
	    print "using default waypoint type 'Reference Point'\n" if ($trace);
	    $wpt->insert_new_elt('last_child', 'sym', 'Reference Point');
	    $wpt->insert_new_elt('last_child', 'type', 'Waypoint|Reference Point');
	}
		
	$gpx_wpts = $gpx_wpts + 1;
    }
    
    # We're done. Now, write back the full xml structure to the gpx file:
    if ($trace) {
	print "writing back the xml structure to " . $outfile . "...\n\n";
    }
    $twig->print_to_file($outfile);
    if ($trace) {
	print "gpx parser finished.\n";
	print "===================================\n\n";
    }
} # sub parse_and_modify_gpx

###### subroutines needed by the gpx/xml parser: #######

sub gpx_parser_wpt {
    my ($twig, $wpt) = @_;

    my $trace = ($Cfg{'trace'} =~ "gpxparser");

    print "parsing element <wpt> #" . $gpx_wpts . "...\n" if $trace;


#    my $name = $wpt->first_child('name')->text;
#    my $gstyp = $wpt->first_child('desc')->text;
#    my $gsnote = $wpt->first_child('type')->text;
#    print "Name: " . $name . "\n";
#    print "Typ:  " . $gsnote . "\n";
    
    # count the number of waypoints. This is needed
    # for the correct naming of the
    # additional waypoints created
    # from the personal note.
    $gpx_wpts = $gpx_wpts+1;
}

sub gpx_parser_gscache {
    my ($twig, $wpt) = @_;

    my $trace = ($Cfg{'trace'} =~ "gpxparser");
    
    
    print "parsing element <groundspeak:cache>...\n" if $trace;
    
    if ($wpt->first_child('groundspeak:personal_note')) {
	$gpx_persnote = $wpt->first_child('groundspeak:personal_note')->text;
    }

    if ($Cfg{'mark_oconly'} && $is_oconly) {
	$wpt->set_att('memberonly' => 'true');
    }

    # write FPs to gpx:
    if ($gpx_recommendations > 0) {
	$wpt->insert_new_elt('last_child', 
			     'groundspeak:favorite_points', $gpx_recommendations);
    }

    # insert travelbugs, if wanted:
    if ($Cfg{'get_trackables'}) {
	my $gc_travelbugs =  $wpt->insert_new_elt('last_child', 
						  'groundspeak:travelbugs');
	foreach my $item( @$trackables ) { 
	    my $gc_travelbug = $gc_travelbugs->insert_new_elt('last_child',
							      'groundspeak:travelbug',
							      {
								  'ref' => $item->{code}
							      });
	    $gc_travelbug->insert_new_elt('last_child',
					  'groundspeak:name',
					  $item->{name});
	}
    }

}

sub gpx_parser_gslog {
    my ($twig, $wpt) = @_;

    # For some reasons, the log types are different when using
    # the OKAPI gpx formatter service (compared to "download gpx"
    # from the cache listing.
    # This method fixes it, so that Locus Map uses the 
    # correct icons for the log.

    my $trace = ($Cfg{'trace'} =~ "gpxparser");

    print "Parsing groundspeak:log...\n" if $trace;

    my $logtype = $wpt->first_child('groundspeak:type')->text;

    print "Logtype is: " . $logtype . "\n" if $trace;

    if ($logtype =~ /Ready to search/) {
	print "'Ready to search' corrected to 'Owner Maintenance'\n" if $trace;
	$wpt->first_child('groundspeak:type')->set_text("Owner Maintenance");
    }

    if ($logtype =~ /Comment/) {
	print "'Comment' corrected to 'Write note'\n" if $trace;
	$wpt->first_child('groundspeak:type')->set_text("Write note");
    }

    if ($logtype =~ /Temporarily unavailable/) {
	print "'Temporarily unavailable' corrected to 'Temporarily Disable Listing'\n" if $trace;
	$wpt->first_child('groundspeak:type')->set_text("Temporarily Disable Listing");
    }

    if ($logtype =~ /Archived/) {
	print "'Archived' corrected to 'Archive'\n" if $trace;
	$wpt->first_child('groundspeak:type')->set_text("Archive");
    }

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

    my $trace = ($Cfg{'trace'} =~ "gpxdownload");

    print "trying to download cache: '". $cache_code . "'\n"
	if ($trace);

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

    my $json = JSON->new->utf8();
    my $username = $json->decode( $response->content );

    return $username->{username};
}

sub get_recommendations {
    my $self = shift;
    my $occode = shift;
    my $response;

    $response=$self->make_restricted_request("http://www.opencaching.de/okapi/services/caches/geocache",
					     "GET",
					     'cache_code' => $occode,
					     'fields' => 'recommendations');

    my $json = JSON->new->utf8();
    my $recommendations = $json->decode( $response->content );

    return $recommendations->{recommendations};
}

sub get_trackables {
    my $self = shift;
    my $occode = shift;
    my $response;

    my $trace = ($Cfg{'trace'} =~ 'trackables');

    print "\ntrying to get trackables for '" . $occode . "'...\n" if ($trace);
    

    $response=$self->make_restricted_request("http://www.opencaching.de/okapi/services/caches/geocache",
     					     "GET",
     					     'cache_code' => $occode,
     					     'fields' => 'trackables');

    print "result of call: " . $response->content . "\n" if ($trace);

    my $json = JSON->new->utf8();
    my $trackables = $json->decode( $response->content );

    return $trackables->{trackables};
}

sub check_oconly {
    my $self = shift;
    my $occode = shift;
    my $response;

    my $is_oconly = 0;

    my $trace = ($Cfg{'trace'} =~ 'oconly');

    print "\ntrying to get oconly status for '" . $occode . "'...\n" if ($trace);
    

    $response=$self->make_restricted_request("http://www.opencaching.de/okapi/services/caches/geocache",
     					     "GET",
     					     'cache_code' => $occode,
     					     'fields' => 'attr_acodes');

    my $json = JSON->new->utf8();
    my $attr_acodes = $json->decode( $response->content );

    foreach (@{$attr_acodes->{attr_acodes}}) {
	if ($_ =~ /^A1$/) {
	    print $occode . " is oconly\n" if ($trace);
	    $is_oconly = 1;
	}
    }

    return $is_oconly;
}

#ub _make_restricted_request {
#    my $self     = shift;
#    my $response = $self->make_restricted_request(@_);
#    return $response->content;
#}


1;
