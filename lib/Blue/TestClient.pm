#
# TestClient.pm
#
# Subclass of client.pm that adds test assertions
#
# Note: this is not part of the server, but is used by the test suite.
# This module is mainly for making assertions about requests initiated by the Blue::client module
# This module prints to stdout!
#
package Blue::TestClient;

use strict;
use warnings;
use XML::LibXML;
use Blue::Client;
use Blue::Util qw (SlurpFile);

our $VERSION   = 1.00;
our @ISA       = qw (Blue::Client Exporter);
our @EXPORT_OK = qw (MakeSampleFile);
our @EXPORT    = qw (); #object based

##############################################################################
#
#  class def
#

sub new
   {
   my ($class, $url_prefix) = @_;

   my $self = Blue::Client->new ($url_prefix);
   $self->{m_assert_index   } = 0;
   $self->{m_assert_failures} = 0;
   $self->{m_print_successes} = 1;
   $self->{m_print_failures } = 1;
#   $self->{m_print_url      } = 1;
   $self->{m_print_url      } = 0;
   
   return bless ($self, $class);
   }

sub GetAssertCount    {my($obj) = @_; return $obj->{m_assert_index   }}
sub GetAssertFailures {my($obj) = @_; return $obj->{m_assert_failures}}


sub SetTestGroup
   {
   my ($obj, $name) = @_;
   return $obj->{m_group_name} = $name;
   }
  
sub SetTestName
   {
   my ($obj, $name) = @_;
   $obj->{m_assert_group_index} = 0;  
   return $obj->{m_test_name} = $name;
   }
   
sub SetPrintOptions
   {
   my ($obj, $print_successes, $print_failures, $print_url) = @_;
   
   $obj->{m_print_successes} = $print_successes;
   $obj->{m_print_failures } = $print_failures ;
   $obj->{m_print_url      } = $print_url      ;
   }   


##############################################################################
#
# Asserts
#

# (200, "Create testbucket");
#
sub Assert_Code
   {
   my ($obj, $expected_status, $assert_msg, $skip) = @_;

   my $response      = $obj->GetResponse();
   my $actual_status = $obj->GetStatus();
   my $ok            = ($actual_status == $expected_status);

   my $returned_message = $obj->GetStatusMessage ();
   my $display_message  = $ok                ? "Status $actual_status == $expected_status" : 
                          $returned_message  ? "$returned_message ($actual_status != $expected_status)"                          :
                                               "Status $actual_status != $expected_status" ;
   
   $obj->Report ($ok, $display_message);
   return $ok;
   }


sub Assert_Content
   {
   my ($obj, $value, $assert_msg) = @_;

   my $content = $obj->GetContent ();
   my $ok      = $content =~ m/$value/is;

   $obj->_AssertPrefix ($ok);
   print $ok ? "(content check)" : "'$content' found where '$value' expected.";
   print "\n";
   return $ok;
   }


# useless assert
sub Assert_Request_Header 
   {
   return 1; 
   }


#sub Assert_Response_Header
#   {
#   my ($obj, $header_name, $header_value, $assert_msg) = @_;
#
#   my $response     = $obj->GetResponse ();
#   my $actual_value = $response->header ($header_name);
#   my $ok           = defined $actual_value && $actual_value =~ m/$header_value/i;
#            
#   $obj->_AssertPrefix ($ok);
#   print "($header_name check)"                                         if  $ok;
#   print "$header_name : expected '$header_value' got '$actual_value'"  if !$ok &&  $actual_value;
#   print "$header_name : header not present"                            if !$ok && !$actual_value;
#   print "\n";
#   return $ok;
#   }

sub Assert_Response_Header
   {
   my ($obj, $header_name, $header_value, $assert_msg) = @_;

   my $response     = $obj->GetResponse ();
   my $actual_value = $response->header ($header_name);
   
   my $ok           = (!$header_value && !$actual_value) ||
                      (defined $actual_value &&  ($header_value eq $actual_value)) ||
                       defined $actual_value && $actual_value =~ m/$header_value/i;
   my $wordy        = 1;

   my $display_message = $ok    ? "'$header_name' has '$header_value'"                                 :
                         $wordy ? "'$header_name' doesn't have '$header_value' (it has $actual_value)" :
                                  "'$header_name' doesn't have '$header_value'"                        ;
                               
   $obj->Report ($ok, $display_message);
   return $ok;
            
#   $obj->_AssertPrefix ($ok);
#   print "($header_name check)"                                         if  $ok;
#   print "$header_name : expected '$header_value' got '$actual_value'"  if !$ok &&  $actual_value;
#   print "$header_name : header not present"                            if !$ok && !$actual_value;
#   print "\n";
#   return $ok;
   }


sub Assert_XML_Content
   {
   my ($obj, $xpath_expr, $value, $wordy) = @_;

   my ($text, $ok) = $obj->_XML_Text ($xpath_expr);
   
   if (!$ok) # don't have xml or the xpath node
      {
      my $display_message = "no matching node: '$xpath_expr'";
      $display_message .= "content: " . $obj->GetContent () . "\n" if $wordy;
      $obj->Report ($ok, $display_message);
      return $ok;
      }
   $ok = $text =~ /$value/i;
   
   my $display_message = $ok ? "'$xpath_expr' has '$value'"          :
                               "'$xpath_expr' doesn't have '$value'" ;
   $obj->Report ($ok, $display_message);
   return $ok;
   }


#internal only
sub _XML_Text
   {
   my ($obj, $xpath_expr) = @_;

   my $xml = $obj->_ResponseXML ();
   my @nodes = $xml ? $xml->findnodes ($xpath_expr) : ();
   my $node_count = scalar @nodes;
   return (undef, 0) if (!$node_count); 
   my $node = $nodes[0];
   my $text = $node->textContent();
   return ($text, $node_count);
   }



# external wrapper.
# todo: flesh out exception handling
sub XML_Content_Text
   {
   my ($obj, $xpath_expr) = @_;
   return $obj->_XML_Text ($xpath_expr);
   }
   

sub Assert_XML_Count
   {
   my ($obj, $xpath_expr, $count) = @_;

   my $xml          = $obj->_ResponseXML ();
   my @nodes        = $xml->findnodes ($xpath_expr);
   my $actual_count = scalar @nodes;
   my $ok           = $count == $actual_count;

   $obj->_AssertPrefix ($ok);
   print  $ok ? "(XML_Count: '$xpath_expr' found $count matches)\n" : "'$xpath_expr'  $actual_count matches found where $count expected.\n";
   return $ok;
   }


sub _ResponseXML
   {
   my ($obj) = @_;

   my $response = $obj->GetResponse ();
   my $content  = $obj->GetContent ();

   if (!$response->{_parsed} && $content)
      {
      my $parser = XML::LibXML->new();
      $response->{_xml}         = eval {$parser->parse_string ($content)};
      $response->{_parse_error} = $@;
      $response->{_parsed     } = 1;

      print "XML parse error: " . $response->{_parse_error} . "\n" if $response->{_parse_error};
      }
   return $response->{_xml};
   }

sub Assert_CompareContent
   {
   my ($obj, $filespec) = @_;

   die ("cannot find $filespec") unless -f $filespec;
   my $file_content = SlurpFile ($filespec);
   my $actual_content = $obj->GetContent ();

   my $ok = $file_content eq $actual_content;

   $obj->Report ($ok, $ok ? "Content matches" : "content doesn't match");
   return $ok;   
   }

sub _AssertPrefix
   {
   my ($obj, $ok) = @_;
   print sprintf ("  %2.2d : %s ", ++($obj->{m_assert_index}), $ok ? "PASS" : "FAIL");
   $obj->{m_assert_failures} += !$ok;
   }


##############################################################################
#
# Misc util fns
#

sub MakeSampleFile
   {
   my ($filespec, $size) = @_;

   my ($fh, $pos);
   open ($fh, ">", $filespec) or die ("cannot open $filespec");
   binmode $fh;
   my $string = join ('', map {chr(rand(255))} (1..1024));
   for ($pos=0; $size-$pos >= 1024; $pos+=1024) {print $fh $string};
   print $fh substr ($string, 0, $size-$pos);
   close $fh;
   }

   
sub Report
   {
   my ($obj, $ok, $msg) = @_;
   
   $obj->{m_assert_index}++;
   $obj->{m_assert_group_index}++;
   $obj->{m_assert_failures} += !$ok;
   
   my $result    =  $ok ? "PASS" : "FAIL";
   my $test_name = "$obj->{m_group_name}:$obj->{m_test_name}:$obj->{m_assert_group_index}";
   
   my $string = sprintf (" %3.3d: %s  ", $obj->{m_assert_index}, $result);
   if ($obj->{m_print_url})
      {
      $string .= "$obj->{m_url}\n        ";
      }
   $string .= sprintf ("%-30s %s\n", $test_name, $msg);
   
   print $string if ($ok && $obj->{m_print_successes}) || (!$ok && $obj->{m_print_failures});
   push @{$obj->{m_failures}}, $string if !$ok;
   }   
   
   
sub PrintAllFailures
   {
   my ($obj) = @_;
   
   map {print $_} @{$obj->{m_failures}};
   }   
   
1;