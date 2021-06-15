#
# Client.pm
#
# Client library for accessing BlueElephant Server
#
#
# my $client = BlueElephantClient->new();
# $client->SetUser     (username, password);
# $client->AddHeader   (name, value)
# $client->Get         ('http://a.net/blaaa', $outfile)
# $client->Post        ('http://a.net/blaaa', $infile)
# $client->Put         ('http://a.net/blaaa', $infile)
# $client->Delete      ('http://a.net/blaaa')
# $client->Head        ('http://a.net/blaaa')
# $client->GetRequest  ()
# $client->GetResponse ()
# $client->GetHeader   (name)
#
#
package Blue::Client;

use strict;
use warnings;
use XML::LibXML;
use URI::Escape;
use Digest::MD5 qw(md5 md5_base64);
use HTTP::Request::Common;
use LWP::Simple qw(get);
use LWP::UserAgent;
use MIME::Base64;

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (GetMD5 GetLength SlurpFile SpillFile);

#our @EXPORT    = qw (); # this is an object module


##############################################################################
#
# BidxClient class constructor
#
# $projectid
# projectid is needed for all instances except for when posting an agency key
#
##############################################################################


sub new
   {
   my ($class, $url_prefix) = @_;

   my $self = {m_url_prefix    => $url_prefix || ""     , #
               m_request       => undef                 , #
               m_response      => undef                 , #
               m_status        => 0                     , #
               m_statusmessage => "No Error"            , #
               m_client_name   => $ENV{SERVER_NAME}     , #
               m_agent         => LWP::UserAgent->new() , #
               m_headers       => {}                    , #
              };
   return bless ($self, $class);
   }


# note: in and out params may be either filespecs or references to data buffers or null
#
sub Get   {my ($obj, $url, $out) = @_; return $obj->_Request ('GET'   , $url, undef, $out);}
sub Post  {my ($obj, $url, $in)  = @_; return $obj->_Request ('POST'  , $url, $in        );}
sub Put   {my ($obj, $url, $in)  = @_; return $obj->_Request ('PUT'   , $url, $in        );}
sub Delete{my ($obj, $url)       = @_; return $obj->_Request ('DELETE', $url             );}
sub Head  {my ($obj, $url)       = @_; return $obj->_Request ('HEAD'  , $url             );}



#sub _Request
#   {
#   my ($obj, $verb, $url, $infile, $outfile) = @_;
#
#   $obj->{m_verb   } = $verb   ;
#   $obj->{m_url    } = $obj->{m_url_prefix} . $url;
#   $obj->{m_infile } = $infile ;
#   $obj->{m_outfile} = $outfile;
#   $obj->{m_request} = HTTP::Request->new ($verb => $obj->{m_url});
#   $obj->{m_request}->content ($infile ? SlurpFile ($infile) : "") if (defined $infile);
#
#   # we default these headers if they are not explicitly present and we have data to upload
#   $obj->AddHeader ('Content-MD5'   , GetFileMD5($infile)) if ($infile && !$obj->GetHeader ('Content-MD5'   ));
#   $obj->AddHeader ('Content-Length', (stat $infile)[7]  ) if ($infile && !$obj->GetHeader ('Content-Length'));
#   $obj->_SetHeaders ();
#
#   Log (5, "BlueElephant: - about to $verb $obj->{m_url} [$infile]");
#
#   $obj->{m_response     } = $obj->{m_agent}->request ($obj->{m_request});
#   $obj->{m_status       } = $obj->{m_response}->code;
#   $obj->{m_is_success   } = $obj->{m_response}->is_success();
#   $obj->{m_content      } = $obj->{m_response}->content();
#   $obj->{m_error_message} = $obj->_GetErrorMessage () if !$obj->{m_is_success};
#   SpillFile ($outfile, $obj->{m_content})             if $obj->{m_is_success} && $outfile;
#
#   Log (5, "BlueElephant:request error ($obj->{m_status}) [$obj->{m_content}]") if !$obj->{m_is_success};
#
#
#   return $obj->{m_is_success} ? 0 : $obj->{m_status}; # make sure this is the convention
#   }


# returns 0 on success, errorcode if an error
#
# $in, $out params:
#   if scalar, it is considered a filespec
#   if scalar ref, it is considered a ref to a data buffer
#   if undef, it isn't used
#
sub _Request
   {
   my ($obj, $verb, $url, $in, $out) = @_;

   $obj->{m_verb   } = $verb   ;
   $obj->{m_url    } = $obj->{m_url_prefix} . $url;
   $obj->{m_request} = HTTP::Request->new ($verb => $obj->{m_url});
   $obj->{m_infile } = $in  if (!ref $in);  # $in  is a filename if its a scalar
   $obj->{m_outfile} = $out if (!ref $out); # $out is a filename if its a scalar

   $obj->{m_request}->content (ref $in eq 'SCALAR' ? ${$in} : SlurpFile ($in)) if (defined $in);

   # we default these headers if they are not explicitly present and we have data to upload
   $obj->AddHeader ('Content-MD5'   , GetMD5   ($in)) if ($in && !$obj->_GetHeader ('Content-MD5'   ));
   $obj->AddHeader ('Content-Length', GetLength($in)) if ($in && !$obj->_GetHeader ('Content-Length'));
   $obj->_SetHeaders ();

#   DebugLog (5, "Blue::Client: - about to $verb $obj->{m_url} [$in]");

   $obj->{m_response     } = $obj->{m_agent}->request ($obj->{m_request});
   $obj->{m_status       } = $obj->{m_response}->code;
   $obj->{m_is_success   } = $obj->{m_response}->is_success();
   $obj->{m_content      } = $obj->{m_response}->content();
   $obj->{m_error_message} = $obj->_GetErrorMessage () if !$obj->{m_is_success};

   SpillFile ($out, $obj->{m_content}) if $obj->{m_is_success} && $obj->{m_outfile};
   ${$out} = $obj->{m_content}         if $obj->{m_is_success} && ref $out eq 'SCALAR';

#   DebugLog (5, "Blue::Client:request error ($obj->{m_status}) [$obj->{m_content}]") if !$obj->{m_is_success};

   return $obj->{m_is_success} ? 0 : $obj->{m_status}; # make sure this is the convention
   }


sub GetRequest      {my($obj) = @_; return $obj->{m_request      }}
sub GetResponse     {my($obj) = @_; return $obj->{m_response     }}
sub GetStatus       {my($obj) = @_; return $obj->{m_status       }}
sub IsSuccess       {my($obj) = @_; return $obj->{m_is_success   }}
sub GetStatusMessage{my($obj) = @_; return $obj->{m_error_message}}
sub GetContent      {my($obj) = @_; return $obj->{m_content      }}

sub GetResponseHeaders
   {
   my ($obj) = @_;
   my $response = $obj->GetResponse();
   return {map {$_ => $response->header($_)} $response->header_field_names};
   }



##############################################################################
#
# Util : headers management
#
##############################################################################

# set $header_value to undef to delete specific header
# set $header_name to undef to delete all headers
#
sub AddHeader
   {
   my ($obj, $header_name, $header_value) = @_;

   return $obj->{m_headers} = {} if !defined $header_name;
   return delete ($obj->{m_headers})->{$header_name} if !defined $header_value;
   ($obj->{m_headers})->{$header_name} = $header_value;
   }


sub AddHeaders
   {
   my ($obj, $headers) = @_;
   map {$obj->AddHeader($_=>$headers->{$_})} (keys %{$headers});
   }


sub _GetHeader
   {
   my ($obj, $header_name) = @_;
   return ($obj->{m_headers})->{$header_name};
   }


sub _SetHeaders #internal
   {
   my ($obj) = @_;

   my $headers = $obj->{m_headers};
   map {$obj->{m_request}->header ($_ => $headers->{$_})} (keys %{$headers});

   $obj->{m_headers} = {};
   }


# $type - undef = std Basic Authorization
#
sub SetUser
   {
   my ($obj, $userid, $password, $auth_type) = @_;

   $obj->{userid  }  = $userid    if defined $userid; 
   $obj->{password}  = $password  if defined $password;
   $obj->{auth_type} = $auth_type if defined $auth_type;
   return if !$obj->{userid} && !$obj->{password};
   
   $auth_type = $obj->{auth_type} || "Basic";
   
   return $obj->AddHeader ("X-Elephant-Authorization", "Blue userid=\"$obj->{userid}\",password=\"$obj->{password}\"")
      if ($auth_type =~ /^Elephant/i); # old.  depricated
      
   my $encoded_data = encode_base64("$obj->{userid}:$obj->{password}");
   chomp $encoded_data;
   return $obj->AddHeader ("Authorization", "$auth_type $encoded_data");
   }


###############################################################################
#
# error handling
#
##############################################################################

# see if we got back an xml block
#
sub _GetErrorMessage
   {
   my ($obj) = @_;

   my $parser = XML::LibXML->new();
   my $dom    = eval {$parser->parse_string ($obj->{m_content})};
   
   return "Server Error code '$obj->{m_status}'" if $@; 
   return _XML_Text ($dom, "//error/message") || "Server Error code '$obj->{m_status}'";
   }


sub _XML_Text
   {
   my ($dom, $xpath_expr) = @_;

   my $results = $dom->findnodes ($xpath_expr);
   return "" if scalar $results->get_nodelist() < 1;
   my $node = $results->get_node(1);
   my $text = $node->textContent();
   return $text;
   }


###############################################################################
#
# Util
#
##############################################################################

# Get the length of a file or data buffer
# $in : if a scalar, its a filespec
# $in : if a scalar ref, its a ref to a data buffer
#
sub GetLength
   {
   my ($in) = @_;

   return length ${$in} if ref $in eq 'SCALAR';
   return (stat $in)[7];
   }  


# Calc the MD5 of a file or data buffer
# $in : if a scalar, its a filespec
# $in : if a scalar ref, its a ref to a data buffer
#
sub GetMD5
   {
   my ($in) = @_;

   return md5_base64 (${$in}) if ref $in eq 'SCALAR';

   my $filehandle;
   open ($filehandle, "<", $in) or return;
   binmode $filehandle;
   my $ctx = Digest::MD5->new;
   $ctx->addfile($filehandle);
   close ($filehandle);
   return $ctx->b64digest . "==";
   }


sub SlurpFile
   {
   my ($filespec) = @_;

   my $filehandle;
   my $ok = open ($filehandle, "<", $filespec) or return undef;
   binmode $filehandle;
   my $contents;
   local $/ = undef;
   $contents = <$filehandle>;
   close $filehandle;
   return $contents;
   }


sub SpillFile
   {
   my ($filespec, $content) = @_;

   my $filehandle;
   open ($filehandle, ">", $filespec) or return 0;
   binmode $filehandle;
   print $filehandle ${$content}  if ref $content eq "SCALAR";
   print $filehandle $content     if ref $content ne "SCALAR";
   close $filehandle;
   return 1;
   }

##############################################################################
#
# Util: debug dumps
#
##############################################################################

sub DumpRequest
   {
   my ($obj) = @_;

   print "--------------------Request----------------------------\n";
   print "  Verb    : " . $obj->{m_verb} . "\n";
   print "  Url     : " . $obj->{m_url } . "\n";
   print "  Headers : \n"; 
   DumpHeaders (($obj->{m_request}));
   }


sub DumpResponse
   {
   my ($obj, $include_content) = @_;

   my $response = $obj->{m_response};
   print "--------------------Response----------------------------\n";
   print "  Code    : " . $obj->{m_status} . "\n";
   print "  Headers : \n"; 
   DumpHeaders ($response);
   (print "  Content : \n" . ($obj->{m_content} || "") . "\n") if $include_content;
   print "--------------------------------------------------------\n";
   }


sub DumpHeaders
   {
   my ($rr_obj) = @_; # request or responce object

   map {print "            $_: " . $rr_obj->header($_) . "\n"} $rr_obj->header_field_names;
   }


 1;