#
# Reads the FNQ config file and provides access to the config setting
#
package Blue::Config;

require Exporter;
use strict;
use warnings;
use Blue::Untaint;

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (Setting);

my %CONFIG_SETTINGS = (); # cache

sub Initialize
   {
   $CONFIG_SETTINGS{root}          = env_filespec('BLUE_ROOT'     ) || "c:/Blue";
   $CONFIG_SETTINGS{configfile}    = env_filespec('BLUECONFIGFILE') || $CONFIG_SETTINGS{root} . "/config/Blue.conf";
   $CONFIG_SETTINGS{blue_url_root} = env_uri     ('BLUE_URL_ROOT' ) || "";

   my $confighandle;
   open ($confighandle, "<", "$CONFIG_SETTINGS{configfile}") or die ("Missing configuration file $CONFIG_SETTINGS{configfile}");

   while (my $line = <$confighandle>)
      {
      chomp $line;

      # discard possible line ending comment starting with a # sign
      ($line) = $line =~ /^(.*?)(#.*)?$/;

      # split name = value      
      my ($name, $value) = $line =~ /^\s*(\S+?)\s*=\s*(.+?)\s*$/;
      next unless defined $name and defined $value;

      # trim whitespace
      $name  = CleanString (lc $name);
      $value = CleanString ($value);

      # value may contain 1 or more "$var" representing a previous declaration
      $value =~ s{\$(\w+)}{exists $CONFIG_SETTINGS{lc $1} ? $CONFIG_SETTINGS{lc $1} : "\$$1"}gei;

      $CONFIG_SETTINGS{$name} = $value;
      }
   close $confighandle;

   $CONFIG_SETTINGS{queuedir} ||= "$CONFIG_SETTINGS{root}/queues";

   return 1;
   }


sub CleanString
   {
   my ($string) = @_;

   $string =~ s/^\s*(.*?)\s*$/$1/;
   return $string;
   }


sub Setting
   {
   my @names = map {lc $_} @_;

   Initialize() unless %CONFIG_SETTINGS;

   return $CONFIG_SETTINGS{$names[0]} unless wantarray;

   return map {$CONFIG_SETTINGS{$_}} @names;
   }


#fini
1;
