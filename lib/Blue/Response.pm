#
# Response.pm
# functions to return data to the client
#
package Blue::Response;

require Exporter;

use strict;
use Time::Local;
use HTTP::Status;
use Blue::Template   qw(Template);
use Blue::DebugLog   qw(DebugLog GetDebugLog);
use Blue::ServiceLog qw(LogAction);
use Blue::Config     qw(Setting);
use Blue::Util;
use Blue::Untaint;

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (Error
                     SysError
                     Response_xml
                     Response_raw
                     Response_html
                     AddContentLengthHeader
                     AddMD5Header
                     GetHeaders
                     SetBucketHeaders 
                     SetObjectHeaders
                     SetContentLocationHeader
                     Reloc
                     AuthRequiredResponse
                     );


###############################################################################
#
# response generators
#

sub Response
   {
   my ($status_code, $content_type, $content) = @_;
   
   DebugLog (5, "server response: [$status_code] $content");
   LogAction ($status_code);
   AddResponseHeader ("Content-Length", length $content) if !HasResponseHeader ("Content-Length");

   binmode STDOUT;
   
#debug-start
#   print "Status: 200 OK\r\n";
#   print "Content-type: text/html\r\n\r\n Yo!"; 
#   exit(0);
#debug-end

   print "Status: $status_code " . status_message($status_code) . "\r\n";
   print "Content-type: $content_type\r\n";
   
   map {print "$_\r\n"} GetExtraHeaders();
   
   ClearExtraHeaders();
   
   print "\r\n";
   print "$content";
   }


sub Response_xml
   {
   my ($status_code, $xml) = @_;

   if (Blue::Config::Setting('debug_log_in_xml'))
      {
      my @log_contents = GetDebugLog();
      my $log_messages = "";
      map {$log_messages .= "    <msg> $_->{log_message} </msg>\n"} @log_contents;
      $xml = "<debug>\n$xml\n  <debug_log>\n$log_messages  </debug_log>\n</debug>\n";
      }
     
   return Response ($status_code, 'text/xml', $xml);
   }


sub Response_raw
   {
   my ($status_code, $message, $content_type) = @_;
   return Response ($status_code, $content_type || 'x-application/octet-stream', $message);
   }


sub Response_html
   {
   my ($status_code, $html) = @_;
   return Response ($status_code, 'text/html', $html);
   }

   
sub SysError {Error(500, @_);}


# errors are returned in xml format
#
sub Error
   {
   my ($status_code, $message, $content_status) = @_;

   # $content_status is only used if the error return in the xml is different than the http status code
   # currently, this is only used by errors.pl to show error messages
   $content_status ||= $status_code;

   DebugLog (1, "server error response: [$status_code] $message");

   Response_xml ($status_code, Template ('error', status => $content_status, message => $message));
   exit (0);
   }



###############################################################################
#
# special header creation
#

my @EXTRA_HEADERS = ();

sub GetExtraHeaders
   {
   return @EXTRA_HEADERS;
   }
   
sub ClearExtraHeaders
   {
   @EXTRA_HEADERS = ();
   }
   

sub AddContentLengthHeader
   {
   my ($ldir, $file) = @_;
   
   my $filespec  = Blue::Util::BuildFilespec ($ldir, $file);
   my $filesize  = (stat $filespec)[7];

   AddResponseHeader ("Content-Length", $filesize);
   }


sub AddMD5Header
   {
   my ($ldir, $file) = @_;

   my $filespec  = Blue::Util::BuildFilespec ($ldir, $file);
   my $filehandle;

   open ($filehandle, "<", $filespec) or return;
   binmode $filehandle;
   my $ctx = Digest::MD5->new;
   $ctx->addfile($filehandle);
   close ($filehandle);
   my $digest = $ctx->b64digest();
   $digest =~ s/\s*$//;

   AddResponseHeader ("Content-MD5", $digest);
   }

   
sub AddAuthenticationHeader
   {
   my ($realm) = @_;
   
   $realm ||= "elephant";
   AddResponseHeader ("WWW-Authenticate", "Basic realm=\"$realm\"");
   }   

   
sub AddResponseHeader
   {
   my ($name, $value) = @_;
   
   push @EXTRA_HEADERS, "$name: $value";
   }

   
sub HasResponseHeader
   {
   my ($name) = @_;

   map {return 1 if $_ =~ /$name/} @EXTRA_HEADERS;
   return 0;
   }


# return a hashref of the interesting cgi headers
# any bucket or object headers present will be scooped up
#
# cgi headers -> hash
#
sub GetHeaders
   {
   return {"User-Agent"               => env_text  ('HTTP_USER_AGENT'              ) || "",
           "Content-Type"             => env_any   ('CONTENT_TYPE'                 ) || "",
           "Content-Length"           => env_number('CONTENT_LENGTH'               ) || "",
           "Content-MD5"              => env_any   ('HTTP_CONTENT_MD5'             ) || "",
           "Authorization"            => env_any   ('HTTP_AUTHORIZATION'           ) || "", 
           "X-Elephant-Authorization" => env_any   ('HTTP_X_ELEPHANT_AUTHORIZATION') || "", 
           "X-Elephant-Version"       => env_any   ('HTTP_X_ELEPHANT_VERSION'      ) || "", 
           "X-Bucket-Policy"          => env_any   ('HTTP_X_BUCKET_POLICY'         ) || "",
           "X-Custom-Metadata"        => env_text  ('HTTP_X_CUSTOM_METADATA'       ) || "", 
           "X-Bucket-Max-Size"        => env_number('HTTP_X_BUCKET_MAX_SIZE'       ) || "",
           "X-Bucket-Max-Objects"     => env_number('HTTP_X_BUCKET_MAX_OBJECTS'    ) || "",
           "X-Bucket-Signature-Cert"  => env_text  ('HTTP_X_BUCKET_SIGNATURE_CERT' ) || "",
           "X-Bucket-Encryption-Cert" => env_text  ('HTTP_X_BUCKET_ENCRYPTION_CERT') || "",
          };
   }


# set headers associated with a bucket
#
# bucket record -> response header
#
sub SetBucketHeaders 
   {
   my ($bucket) = @_;

   AddResponseHeader ("X-Bucket-Policy"         , $bucket->{"policy_alias"   }) ;
   AddResponseHeader ("X-Custom-Metadata"       , $bucket->{"custom_metadata"}) if $bucket->{"custom_metadata"}; # db form
   AddResponseHeader ("X-Bucket-Max-Size"       , $bucket->{"max_size"       }) if $bucket->{"max_size"       };
   AddResponseHeader ("X-Bucket-Max-Objects"    , $bucket->{"max_objects"    }) if $bucket->{"max_objects"    };
   AddResponseHeader ("X-Bucket-Signature-Cert" , $bucket->{"signature_cert" }) if $bucket->{"signature_cert" };
   AddResponseHeader ("X-Bucket-Encryption-Cert", $bucket->{"encryption_cert"}) if $bucket->{"encryption_cert"};

   SetContentLocationHeader ($bucket->{namespace}, $bucket->{name});
   }


# set headers associated with an object
#
sub SetObjectHeaders
   {
   my ($object) = @_;

   AddResponseHeader ("Content-Type"     , $object->{"content_type"   }) if $object->{"content_type"   };
   AddResponseHeader ("Content-Length"   , $object->{"content_length" }) if $object->{"content_length" };
   AddResponseHeader ("Content-MD5"      , $object->{"content_md5"    }) if $object->{"content_md5"    };
   AddResponseHeader ("X-Custom-Metadata", $object->{"custom_metadata"}) if $object->{"custom_metadata"};

   SetContentLocationHeader ($object->{namespace}, $object->{bucket}, $object->{name});
   }

   
sub SetContentLocationHeader
   {
   my ($namespace, $bucket_name, $object_name) = @_;

   my $location = GetContentLocation ($namespace, $bucket_name, $object_name);
   AddResponseHeader ("Content-location", $location);
   AddResponseHeader ("X-Object-Name"   , $object_name) if $object_name;
   AddResponseHeader ("X-Bucket-Name"   , $bucket_name) if $bucket_name;
   }


sub Reloc
   {
   my ($link) = @_;

   if (not $link =~ /^http/i)   # local relocations suffer from browser bugs; check and fix
      {
      $link =~ s|^/+||;  # get rid of leading /'s, we'll add back
      $link = "http://" . env_text('SERVER_NAME'). "/$link";
      }
   print "Status: 302 Moved\r\n";
   print "Location: $link\r\n\n";
   exit (0);
   }
   
sub AuthRequiredResponse
   {
   AddAuthenticationHeader ();
   Error (401, "Authentication Required");
   }


#fini
1;