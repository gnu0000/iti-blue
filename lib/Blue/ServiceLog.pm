#
# ServiceLog.pm
#
package Blue::ServiceLog;

require Exporter;

use strict;
use warnings;
use Blue::Config   qw(Setting);
use Blue::DB       qw(GetDB);
use Blue::User     qw(GetCurrentUserName);
use Blue::DebugLog qw(DebugLog);
use Blue::Util;
use Blue::Untaint;

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (LogAction SetLogInfo);

my %LOG_INFO  = ();

sub LogAction
   {
   my ($result_code) = @_;

   my $verb      = $LOG_INFO{verb};
   return unless LogThisVerb ($verb);

   my $headers   = Blue::Response::GetHeaders ();
   
   DebugLogAction ($result_code, $headers) if Setting ('reqlog');
   
   my $namespace = $LOG_INFO{namespace};
   my $bucket    = $LOG_INFO{bucket   };
   my $object    = $LOG_INFO{object   };
   my $user      = GetCurrentUserName ();
   my $user_agent= $headers->{"User-Agent"};
   my $url       = env_uri('SCRIPT_URL');
   my $sql       = "insert into log " .
                   "(user, url, verb, namespace, bucket, object, result_code, user_agent) " .
                   "values (?, ?, ?, ?, ?, ?, ?, ?)";

   return GetDB()->Do ($sql, $user, $url, $verb, $namespace, $bucket, $object, $result_code, $user_agent);
   }


sub SetLogInfo
   {
   my (%log_info) = @_;

   %LOG_INFO = (%LOG_INFO, %log_info);
   }


sub LogThisVerb 
   {
   my ($verb) = @_;

   my %verbhash;
   map {$verbhash{lc CleanString($_)}=1} split (',', Setting ('service_log'));
   return 1 if !scalar keys %verbhash;
   return 1 if $verbhash{all};
   return 1 if $verbhash{lc $verb};
   return 0;
   }

sub DebugLogAction
   {
   my ($result_code, $headers) = @_;

   my $verb    = $LOG_INFO{verb};
   my $uri     = env_any('SCRIPT_URI');  #$LOG_INFO{url};
   my $msg    = "--------- request start ---------\n". 
                " $verb $uri ($result_code)\n"       ;
   map {$msg .= " $_=$headers->{$_}\n" } (keys %{$headers}); #if $headers->{$_}
   $msg      .= "--------- request end ---------";
   
   DebugLog (3, $msg);
   }


1;