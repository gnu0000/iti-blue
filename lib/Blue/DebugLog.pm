#
# DebugLog.pm
# simple logging
#
package Blue::DebugLog;

require Exporter;

use strict;
use warnings;
use MIME::Base64;
use Blue::Config qw(Setting);
use Blue::Util   qw(NowInDBFormat);

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (DebugLog GetDebugLog);

# internal globals
my $LOG_HANDLE = undef;
my @LOG_CONTENTS = ();



# log_level
#   0 - No logging
#   1 - Errors
#   2 - above + warnings
#   3 - above + info
#   4 - above + verbose info
#   5 - above + annoyingly verbose info
#
sub DebugLog
   {
   my ($log_level, $message) = @_;

   return if Blue::Config::Setting('debug_log_level') < $log_level;
   if (!$LOG_HANDLE)
      {
      my $filespec = Blue::Config::Setting('root') . "/logs/application.log";
      open ($LOG_HANDLE, ">>", $filespec);
      $|=1;
      }
   my $time = Blue::Util::NowInDBFormat ();
   my $quip = "$time:$log_level:$message\n";
   print $LOG_HANDLE $quip;
   push @LOG_CONTENTS, {time=>$time, log_level=>$log_level, log_message=>"$message", _template=>"log_message"};
   return undef;
   }

sub GetDebugLog
   {
   return @LOG_CONTENTS;
   }


#sub DebugLogAuthInfo
#   {         
#   my ($log_level) = @_;
#
#   my $header = $ENV{HTTP_AUTHORIZATION};
#   return if !$header;
#
#   my ($type, $data) = $header =~ /^(\w+) (.*)$/;
#   my $is_basic =  $type =~ /^Basic/i;
#
#   my $data = decode_base64($data) if $is_basic;
#   DebugLog ($log_level, "HTTP_AUTHORIZATION: $data" . ($is_basic ? " (decoded)" : ""));
#   }

1;