oc2go
=====

opencaching 2 go - download geocaches from opencaching.de

This small script helps you to download geocaches from opencaching.de.

Put all caches you want to download in a textfile, one per line. See
"oc2go_bookmarks.txt" for an example. This script will try to download all
caches from this list and add them to a zip file. You can easily copy this zip
file to you GPSr device and import them there into your famous geocaching
software.

The script will also download personal notes and personal coordinates for your
geocaches. If you provide personal coordinates using the opencaching.de web
interface, the cache will be moved to this coordinates and the text "(solved)"
will be prepended to the cache name.

Also, information about cache attributes, recommendations and geokretys
contained in the cache will be added to the listing.

Supported platforms:  
--------------------
Linux, Windows

Requirements:  
-------------
A running perl distribution. The script is tested with perl 5.18 on Linux and
ActivePerl 5.16.3 on Windows.

The following perl modules should be installed:  
Crypt::SSLeay (install from you distribution, on Windows use ppm to install)  
Net::OAuth::Simple (use "cpan -i Net::Oauth::Simple" to install)  

Install any other missing perl modules using "cpan -i module-name".

Windows users should install 7-zip and make sure that the executable 7z.exe is
found in the PATH environment variable.

Installation:
-------------  
Run "oc2go.pl -i". This will set up some directories and create the basic
configuration file. The script will prompt for an authorization at
opencaching.de. Copy the shown URL into your browser and authenticate using
your opencaching.de user. You will get a code, enter this code at the command
prompt. You are authenticated to opencaching.de now, you have to run this
authentication only once.

Now run "oc2go.pl -f name_of_your_bookmark_list" to download some cool
caches from opencaching.de.

