#!/Perl/bin/perl
#
#
#
# bClient2 [section] [url] [filespec]
#

use lib '../lib';
use strict;
use warnings;
use Blue::Util;
use Blue::Client qw(GetMD5 GetLength);

MAIN:
   Usage() if (scalar @ARGV > 3 || scalar @ARGV < 2);

   my $ini      = ReadIni ();
   my $section  = GetIniSection (lc $ARGV[0]);
   my $url      = GetURL ($ARGV[1], $section);
   my $verb     = $section->{verb};
   my $filespec = $ARGV[2];
                
   my $client   = Blue::Client->new();
   
   SetUserInfo         ($client, $section);
   InterpolateHeaders  ($section->{headers}, $filespec);
   $client->AddHeaders ($section->{headers});

   $client->Get    ($url, $filespec) if $verb =~ /^get/i   ;
   $client->Post   ($url, $filespec) if $verb =~ /^post/i  ;
   $client->Put    ($url, $filespec) if $verb =~ /^put/i   ;
   $client->Delete ($url)            if $verb =~ /^delete/i;
   $client->Head   ($url)            if $verb =~ /^head/i  ;

   $client->DumpRequest ();
   $client->DumpResponse ($section->{show_content});
   exit (0);


###############################################################################
#
#
#

my $INI = {};

#
#
sub ReadIni
   {
   my ($ini_filespec) = @_;

   $ini_filespec ||= "bclient.ini";
   
   my $filehandle;
   open ($filehandle, "<", $ini_filespec) or Error ("could not open ini file: '$ini_filespec'");
   my $current_section = $INI->{global};
   while (my $line = <$filehandle>)
      {
      next if $line =~ /^#/;        # skip comment lines
      $line =~ s/#.*$//;            # strip line ending comments 
      if ($line =~ /^\[([^\]]*)\]/) # new section?
         {
         my $section_name = lc $1;
         $current_section = $INI->{$section_name} = {};
         $current_section->{verb} = _get_verb($section_name);
         next;
         }
      my ($name, $value) = $line =~ /^([^=]*)=(.*)$/;
      next unless $name && $value;
      CleanString ($name); CleanString ($value);
      $current_section->{$name} = $value            if $name =~ /^username|password|show_content|auth_type|url_base$/i;
      $current_section->{headers}->{$name} = $value if $name !~ /^username|password|show_content|auth_type|url_base$/i;
      }
   return $INI;
   }


sub _get_verb
   {
   my ($ident) = @_;
   my ($verb) = $ident =~ /^.*(get|put|post|head|delete)$/i;
   return $verb;   
   }

# accepts:  defined section 'test_get' , returns that section info
#           direct verb     'get'      , returns default_get or blank section
#
#           otherwise, dies with an error
#
#
# return hash: verb         - http verb to use
#              username     - optional - overrides username in global section
#              password     - optional - overrides password in global section
#              show_content - optional - 1 to send response data to stdout
#              url_base     - optional - set base of user's url
#              headers      - hashref of headers to set
#
sub GetIniSection
   {
   my ($section_name) = @_;
   my $section = $INI->{$section_name};
   return $section if $section;
   Error ("Section '$section_name' not found in ini file.") unless $section_name =~ /^(get|put|post|head|delete)$/;

   # see if we have a [default_verb] defined ....
   $section = $INI->{"default_" . $section_name};
   return $section if defined $section;

   return {verb=>$section_name};
   }


# returns the user specified url
# if url starts with a '.', replace the dot with url_base entry in global section
#
sub GetURL
   {
   my ($url) = @_;

   my $base = $section->{url_base} || $INI->{global}->{url_base};
   $url =~ s/^\./$base/; # if ($url =~ /^\./);
   return $url;
   }


sub SetUserInfo
   {
   my ($client, $section) = @_;

   my $username  = $section->{username}  || $INI->{global}->{username};
   my $password  = $section->{password}  || $INI->{global}->{password};
   my $auth_type = $section->{auth_type} || $INI->{global}->{auth_type};
   $client->SetUser ($username, $password, $auth_type);
   }
   
sub Error
   {
   my ($msg) = @_;

   print "Error: $msg\n";
   exit (0);
   }

sub Usage
   {
   print while <DATA>;
   exit (0);
   }


# headers may contain a few variables that get fixed up here:
#
#   $content_length
#   $content_md5
#   $filename
#
sub InterpolateHeaders
   {
   my ($headers, $filespec) = @_;

   return unless defined $filespec && -f $filespec;
   my %data = (content_length => GetLength ($filespec),
               content_md5    => GetMD5 ($filespec)   ,
               filename       => $filespec            );

   foreach my $header_name (keys %{$headers})
      {
      $headers->{$header_name} =~ s{\$(\w+)}{exists $data{$1} ? $data{$1} : "\$$1"}gei;
      }
   }


__DATA__

BClient  -  Command line Blue client

Usage: BClient action url filespec

Where: 
   action ... Action to perform.  this field corresponds to a section 
               in the bclient.ini file.  the format is tag_verb.  tag
               is any ident you want, verb is the http verb to use.
               you may also use verbs directly.

   url ...... The url to act apon.  if the url starts with a '.', the
               dot is replaces with the url_base entry in the global 
               section of the bclient.ini file.

   filespec . For put and post commands, the file of content to upload.
               for get commands the file to store the results.

Examples: 
   perl bclient2.pl test_put http://blue/craigspace/tb2
            do a http put to http://blue/craigspace/tb2, using the
            headers and options in the [test_put] section of the ini 
            file

   perl bclient2.pl test_get ./craigspace/tb2
            do a http get to http://blue/craigspace/tb2, using the
            headers and options in the [test_get] section of the ini 
            file. (the . in the url resolves to the url_base option)

   perl bclient2.pl get http://blue/craigspace/tb2/myobject
            do a http get to http://blue/craigspace/tb2/myobject, 
            using the headers and options in the [default_get] section
            of the ini file.
