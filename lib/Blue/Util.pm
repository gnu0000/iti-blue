#
# Util.pm
# Utility functions specifically for Blue server
#
#
package Blue::Util;

require Exporter;

use strict;
use warnings;
use Time::Local;
use File::Path;
use File::Basename;
use Text::CSV_XS;
use Blue::Config   qw(Setting);
use Blue::Untaint;
#use Blue::DebugLog;
#use Blue::Response qw(Error); # this causes a circular reference!


our $VERSION = 1.00;
our @ISA     = qw (Exporter);
our @EXPORT  = qw (CleanString
                   NowInDBFormat
                   NowInFillStringFormat
                   DumpStdin
                   LoadStdin
                   SlurpFile
                   Sum
                   SpillFile
                   SafeGetDir
                   GetHostURIPrefix
                   GetContentLocation
                   GetContentPath
                   NowhereFile
                   _get_meta
                   _set_meta
                   WinSystemCommand
                   SystemCommand
                   BacktickCommand
                   GenerateCleanSystemPath
                   );




# strip leading and trailing whitespace characters from the string
#
sub CleanString
   {
   my ($string) = @_;

   return $string if !$string;
   $string =~ s/^\s*(.*?)\s*$/$1/;
   return $string;
   }
   
   

sub NowInDBFormat
   {
   my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
   return sprintf ("%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
   }

#
sub NowInFillStringFormat
   {
   my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
   return sprintf ("%4.4d-%2.2d-%2.2d-%2.2d-%2.2d-%2.2d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
   }



# dump stdin to the named filespec
#
sub DumpStdin
   {
   my ($filespec) = @_;
   my $outfile;
   open ($outfile, ">", $filespec);
   binmode STDIN;
   binmode $outfile;
   local $/ = undef;
   print $outfile <STDIN>;
   close $outfile;
   }


# load stdin and return the contents
#
sub LoadStdin
   {
   local $/ = undef;
   binmode STDIN;
   my $data = <STDIN>;
   return $data;
   }


# load contents of file specified by filespec and return the contents
#
# $error_handler - is an optional replacement error handler
#                  die is used if not specified
#
sub SlurpFile
   {
   my ($filespec, $error_handler) = @_;

   my $handler = $error_handler || sub{die(@_)};

   my $filehandle;
   open ($filehandle, "<", $filespec) or &$handler("Could not read file '$filespec'");
   binmode $filehandle;
   local $/ = undef;
   my $contents = <$filehandle>;
   close $filehandle;
   return $contents;
   }


sub Sum
   {
   my (@params) = @_;

   return undef unless scalar @params;
   my $result = 0;
   foreach my $param (@params)
      {
      $param =~ s/[^0-9\.-]//g;
      $result += $param;
      }
   return 0 + $result;
   }


# Write the contents of a variable to a file
#
#  $filespec    - filespec to open
#  $content     - REFERENCE to the scalar (be nice to your memory)
#  $isbinary,   - 0=text 1=binary
#
# synopsis:
#  SpillFile ('a.o', \"This is a test");
#  SpillFile ('c:/a.bin', \$buffer, 1);
#
#
sub SpillFile
   {
   my ($filespec, $content, $isbinary) = @_;

   $isbinary = 0 if !defined $isbinary;
   my $filehandle;
   open ($filehandle, ">", $filespec) or return 0;
   binmode $filehandle if $isbinary;
   print $filehandle ${$content}  if ref $content eq "SCALAR";
   print $filehandle $content     if ref $content ne "SCALAR";
   close $filehandle;
   return 1;
   }


# exec a windows system call
#
# This fn assumes the program is a windows program.
# if we are running in a unix environment, wine is used.
# This fn scrubs the system path to make it available .
#
# this fn returns the executed processes exit status
#
sub WinSystemCommand
   {
   my @args = @_;

   unless ($^O =~ m/win/i)
      {
      s{\\}{\\\\}g foreach (@args);
      if (scalar @args == 1)
         {
         $args[0] = "wine $args[0]";
         }
      else
         {
         @args = ('wine', @args);
         }
      }
   return SystemCommand (@args);
   }


# exec a system call.
# This fn assumes the program is available in the native environment.
# This fn scrubs the system path to make it available.
#
# this fn returns the executed processes exit status.
#
sub SystemCommand
   {
   my @args = @_;

   #DebugLog (5, "SystemCommand: " . join (" ", map {"$_"} @args));

   my $oldpath = $ENV{PATH};
   $ENV{PATH} = GenerateCleanSystemPath();

   system (@args);
   my $exit_status  = $? >> 8;

   $ENV{PATH} = $oldpath;

   #DebugLog (5, "SystemCommand exit status: '$exit_status'");

   return $exit_status;
   }


# exec a system call.
# This fn assumes the program is available in the native environment.
# This fn scrubs the system path to make it available.
#
# in list   context, this fn returns the executed process exit stataus and stdout
# in scalar context, this fn returns the executed process stdout
#
sub BacktickCommand
   {
   my ($cmd) = @_;

   #DebugLog (5, "BacktickCommand: $cmd");

   my $oldpath  = $ENV{PATH};
   $ENV{PATH} = GenerateCleanSystemPath();

   my $content = `$cmd`;
   my $result  = $? >> 8;

   $ENV{PATH} = $oldpath;

   #DebugLog (5, "BacktickCommand exit status: '$result'");

   return ($result, $content) if wantarray;
   return $content;
   }


# this is used to generate a system path so we can shell 
# out with taint checking on
#
sub GenerateCleanSystemPath
   {
   return '/usr/local/bin:/bin:/usr/bin' unless $^O =~ m/win/i; # hard coded if not windows

   my $comspec = env_filespec ('COMSPEC') || "C:\\Windows\\system32\\cmd.exe";
   my (undef, $comspec_dir) = fileparse($comspec);
   return ".;$comspec_dir";
   }

sub NowhereFile
   {
   return $^O =~ m/win/i ? "nul" : "/dev/null";
   }


# $error_handler - is an optional replacement error handler
#                  undef is returned on error or dir
#
sub SafeGetDir
   {
   my ($dir, $error_handler) = @_;

   eval {mkpath($dir)};
   &$error_handler (500, "Can't create system directory \"$dir\": $@", 1) if $error_handler && $@;
   return $@ ? undef : $dir;
   }


sub GetHostURIPrefix
   {
   my ($prefix) = env_uri('SCRIPT_URI') =~ m/^(https?:\/\/[^\/]*)/i;
   return $prefix;
   }


sub GetContentLocation
   {
   my ($namespace, $bucket_name, $object_name) = @_;

   my $uri_prefix   = GetHostURIPrefix ();
   my $loc = "$uri_prefix" . GetContentPath($namespace, $bucket_name, $object_name);
   return $loc;

   }

sub GetContentPath
   {
   my ($namespace, $bucket_name, $object_name) = @_;

   my $uri_prefix   = GetHostURIPrefix ();
   my $service_root = Setting('blue_url_root') || "";

   my $loc   .= "$service_root/";
   $loc   .= "$namespace/"   if $namespace;
   $loc   .= "$bucket_name/" if $bucket_name;
   $loc   .= $object_name    if $object_name;
   return $loc;
   }



# $params is a string of comma-separated, name=value pairs
# returns the value of the $param_name param, or undef
# rename this and figure out something to do with this
#
sub _get_meta
   {
   my ($params, $param_name) = @_;

   my $csv = Text::CSV_XS->new();
   $csv->parse ($params);
   my @tuples = $csv->fields();
#   my @tuples = split (',', $params);

   foreach my $tuple (@tuples)
      {
      my ($name, $value) = $tuple =~ /^([^=]+)=(.*)$/;
      $name  = CleanString ($name );
      $value = CleanString ($value);
      return $value if $name =~ /^$param_name$/i;
      }
   return undef;
   }


# $params is a string of comma-separated, name=value pairs
# $name,$value is the new param to add. $params is returned
# rename this and figure out something to do with this
#
sub _set_meta
   {
   my ($params, $name, $value) = @_;
    
   $params ||= "";
   $params = $params . ($params ? "," : "");
   $params = $params . "$name=$value";
   return $params;
   }
 

1;
