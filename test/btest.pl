#!/Perl/bin/perl
#
# Test Runner for blue
#
# use: bTest [url] [fn]
#   url - url of blue server default is http://blue
#   fn  - test to run        default is Suite
#
# pre-requisites
# --------------
#   valid users:
#
#   user         password   role    namespace
#   -----------------------------------------
#   admin        password   admin
#   testowner1   password   owner   tns1
#   testowner2   password   owner   tns2
#   user         password   user
#
#
#

use lib '../lib';
use strict;
use warnings;
use URI::Escape;
use Digest::MD5 qw(md5);
use HTTP::Request::Common;
use HTTP::Request::Common qw(POST $DYNAMIC_FILE_UPLOAD);
use LWP::Simple qw(get);
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday tv_interval);
use XML::LibXML;
use Blue::Util;
use Blue::Client qw (GetMD5 GetLength);
use Blue::TestClient qw (MakeSampleFile);

# globals for bad design
my $BASE_URL = "";

MAIN:
   $BASE_URL = $ARGV[0]; 
   $BASE_URL = "http://blue" if !$BASE_URL || $BASE_URL eq '.';
   SetUser ("testowner1", "password");

   my $test       = $ARGV[1] || "Suite";
   my $symbol     = "Test_" . $test;
   my $function   = "main::" . $symbol;
   my $time_start = [gettimeofday];
   
   die "Error: Test $symbol is not defined.\n" if (!defined $main::{$symbol});
      {
      no strict 'refs';   
      &$function ();
      }
   PrintFinalStats (tv_interval ($time_start, [gettimeofday]));
   exit (0);


   
sub PrintFinalStats
   {
   my ($delta) = @_;
   my $client = GetClient ();
   my $tests    = $client->GetAssertCount()   ;
   my $failures = $client->GetAssertFailures();
   my $duration = sprintf ("%.3f", $delta);
   my $statline = "[$failures] failures in [$tests] total tests taking [$duration] seconds.\n";

   print "\n$statline";
   
   return if !$failures;
   
   print "\n\n"                                                  .
         "---------------------------------------------------\n" .
         "Failure recap:\n"                                      .
         "---------------------------------------------------\n" ;
   $client->PrintAllFailures();
   print "$statline";
   }
   
   
   
# returns default test values (namespace bucket object filespec namespace2 bucket2 object2 filespec2)
#  the first namespace is owned by testowner1
#  the second namespace is owned by testowner2
#
sub Defaults
   {
   return qw(tns1 tbk1 tobj1 test1.txt tns2 tbk2 tobj2 test2.txt);
   }   
   
###############################################################################
#
# Tests
#

sub Test_Suite
   {
   Test_Basic            ();
   Test_Commands         ();
   Test_Names            ();
   Test_Authentication   ();
   Test_BucketAliases    ();
   Test_BucketAttributes ();
   Test_Objects          ();
   
   Test_BucketTypes      ();
   Test_Certificates     ();
   Test_Signatures       ();
   }


#   
# basic access tests  
#   
sub Test_Basic
   {   
   SetTestGroup("Basic");
   
   my ($namespace, $bucket, $object, $filespec) = Defaults ();
   
   _Get_Namespace (200, $namespace                             );
   _Put_Bucket    (200, $namespace, $bucket                    );
   _Get_Bucket    (200, $namespace, $bucket                    );
   _Put_Object    (200, $namespace, $bucket, $object, $filespec);
   _Get_Object    (200, $namespace, $bucket, $object           );
   _Delete_Object (200, $namespace, $bucket, $object           );
   _Delete_Bucket (200, $namespace, $bucket                    );
   }


#   
# basic test of all roa commands  
#   
sub Test_Commands   
   {
   Test_Commands_Ping      ();
   Test_Commands_Namespace ();
   Test_Commands_Bucket    ();
   Test_Commands_Object    ();
   }


sub Test_Commands_Ping
   {
   my ($namespace, $bucket, $object, $filespec) = Defaults ();
   
   SetTestGroup("Commands_Ping");
   _Head_Ping   (200);
   _Get_Ping    (200);
   _Put_Ping    (403); # invalid cmd
   _Post_Ping   (403); # invalid cmd
   _Delete_Ping (403); # invalid cmd
   }

   
sub Test_Commands_Namespace
   {
   my ($namespace, $bucket, $object, $filespec) = Defaults ();
   
   SetTestGroup("Commands_NS");
   _Head_Namespace   (200, $namespace);
      _Assert_Header  ("Content-Type" , 'text/xml');
   _Get_Namespace    (200, $namespace);
      _Assert_Header  ("Content-Type" , 'text/xml');
   _Put_Namespace    (404, $namespace);
      _Assert_Header  ("Content-Type" , 'text/xml');
   _Post_Namespace   (200, $namespace);
      _Assert_Header  ("Content-Type"    , 'text/xml'  );
      _Assert_Header  ("Content-Location", '.+'        );
      _Assert_Header  ("X-Bucket-Name"   , '.+'        );
      _Assert_Content ("//response"      , "$namespace/(.+) created\$");

   # cleanup from the above _Post_Namespace
   _Delete_Bucket (200, $namespace, _Header_Text ('X-Bucket-Name'));
   
   _Delete_Namespace (404, $namespace);
   }   

   
sub Test_Commands_Bucket
   {
   my ($namespace, $bucket, $object, $filespec) = Defaults ();
   
   SetTestGroup("Commands_Bucket");
   _Put_Bucket    (200, $namespace, $bucket);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/"             );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                            );
      _Assert_Content ("//response"       , "bucket '$namespace/$bucket' created");
      
   _Head_Bucket   (200, $namespace, $bucket);
      _Assert_Header  ("Content-Type"     , 'text/xml'              );
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/");
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"               );
      _Assert_Header  ("X-Bucket-Policy"  , "Private"               );
      
   _Get_Bucket    (200, $namespace, $bucket);
      _Assert_Header  ("Content-Type"     , 'text/xml'              );
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/");
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"               );
      _Assert_Header  ("X-Bucket-Policy"  , "Private"               );
      _Assert_Content ("/bucket/namespace", $namespace              );
      _Assert_Content ("/bucket/name"     , $bucket                 );
      _Assert_Content ("/bucket/policy"   , "Private"               );
      
   _Put_Bucket    (403, $namespace, $bucket     ); # bucket exists
   _Head_Bucket   (404, $namespace, $bucket."x" ); # no such bucket
   _Get_Bucket    (404, $namespace, $bucket."x" ); # no such bucket
      
   _Delete_Bucket (200, $namespace, $bucket);
      _Assert_Content ("//response"       , "bucket '$namespace/$bucket' removed");
      
   _Delete_Bucket (404, $namespace, $bucket);     # no bucket already deleted
   _Delete_Bucket (404, $namespace, $bucket."x"); # no such bucket
   }   
   
   
sub Test_Commands_Object
   {
   my ($namespace, $bucket, $object, $filespec) = Defaults ();
   
   SetTestGroup("Commands_Object");
   _Put_Bucket    (200, $namespace, $bucket);
   _Put_Object    (200, $namespace, $bucket, $object, $filespec);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/$object"              );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                                    );
      _Assert_Header  ("X-Object-Name"    , "$object"                                    );
      _Assert_Content ("//response"       , "object '$namespace/$bucket/$object' stored" );
   _Put_Object    (200, $namespace, $bucket, $object, $filespec); # restore
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Content ("//response"       , "object '$namespace/$bucket/$object' updated" );
   
   _Head_Object   (200, $namespace, $bucket, $object);
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/"   );
      _Assert_Header  ("Content-Type"     , 'application/octet-stream' );
      _Assert_Header  ("Content-MD5"      , GetMD5    ($filespec)      );
      _Assert_Header  ("Content-Length"   , GetLength ($filespec)      );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                  );
      _Assert_Header  ("X-Object-Name"    , "$object"                  );
      
   _Get_Object    (200, $namespace, $bucket, $object);
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/"   );
      _Assert_Header  ("Content-Type"     , 'application/octet-stream' );
      _Assert_Header  ("Content-MD5"      , GetMD5    ($filespec)      );
      _Assert_Header  ("Content-Length"   , GetLength ($filespec)      );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                  );
      _Assert_Header  ("X-Object-Name"    , "$object"                  );


   _Delete_Object (200, $namespace, $bucket, $object);
   _Delete_Bucket (200, $namespace, $bucket         );
   }   
   

#
# test identifiers
#
sub Test_Names
   {
   my ($namespace, $bucket, $object, $filespec) = Defaults ();

   SetTestGroup("Names");
   my @good_b_names = qw(a normal verylongbucketname name0 0name 123 _name name_ na_me
                      -name name- na-me .name name. na.me .-. ._. -.- _._ _-_ );
   my @bad_b_names =  qw(na!me na@me na$me na*me na(me na)me na+me na=me 
                      !a @a $a *a (a )a +a =a a! a@ a$ a* a( a) a+ a= a');

   # strict bucket naming                       
   map {_tpbucket_ok ($_)} @good_b_names;
   map {_tpbucket_bad ($_)} @bad_b_names;
   
   # object naming                       
   _Put_Bucket    (200, $namespace, $bucket);
   map {_tpobject_ok ($bucket, $_)} @good_b_names;
   _tpobject_ok ($bucket, "with space");
   _tpobject_ok ($bucket, '@');
   _tpobject_ok ($bucket, '!');
   _Delete_Bucket (200, $namespace, $bucket);
   }
   

sub _tpbucket_ok
   {
   my ($bucket) = @_;

   my ($namespace) = Defaults ();
   SetTestGroup("BNames($bucket)");
   _Put_Bucket (200, $namespace, $bucket);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/"             );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                            );
      _Assert_Content ("//response"       , "bucket '$namespace/$bucket' created");
   _Delete_Bucket (200, $namespace, $bucket);
   }
   
sub _tpbucket_bad
   {
   my ($bucket) = @_;
   
   my ($namespace) = Defaults ();
   SetTestGroup("BNames($bucket)");
   _Put_Bucket (400, $namespace, $bucket);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Content ("/error/message"   , "invalid bucket name");
   }
   
   
sub _tpobject_ok
   {
   my ($bucket, $object) = @_;

   my ($namespace, undef, undef, $filespec) = Defaults ();
   SetTestGroup("ONames($object)");
   _Put_Object    (200, $namespace, $bucket, $object, $filespec);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Header  ("Content-Location" , ".+/$namespace/$bucket/$object"              );
      _Assert_Header  ("X-Bucket-Name"    , "$bucket"                                    );
      _Assert_Header  ("X-Object-Name"    , "$object"                                    );
      _Assert_Content ("//response"       , "object '$namespace/$bucket/$object' stored" );
   }
   
   
sub _tpobject_bad
   {
   my ($bucket, $object) = @_;
   
   my ($namespace, undef, undef, $filespec) = Defaults ();
   SetTestGroup("ONames($object)");
   _Put_Object    (400, $namespace, $bucket, $object, $filespec);
      _Assert_Header  ("Content-Type"     , 'text/xml');
      _Assert_Content ("/error/message"   , "invalid object name");
   }
   

#   
#   
#   
sub Test_Authentication   
   {
   my ($namespace1, undef, $object1, $filespec1, $namespace2) =  Defaults ();
   my ($bucket1, $bucket2, $bucket3) = qw(bk1 bk2 bk3);
   SetTestGroup("Authentication");
         
   # setup owner #1 buckets
   SetTestGroup("Authentication:Setup1");
   SetUser     ("testowner1", "password");
   _AddHeader  ("X-Bucket-Policy", "Private" );   _Put_Bucket (200, $namespace1, $bucket1);
   _AddHeader  ("X-Bucket-Policy", "[RWRW..]");   _Put_Bucket (200, $namespace1, $bucket2);
   _AddHeader  ("X-Bucket-Policy", "Public"  );   _Put_Bucket (200, $namespace1, $bucket3);
   
   # setup owner #2 buckets
   SetTestGroup("Authentication:Setup2");
   SetUser     ("testowner2", "password");
   _AddHeader  ("X-Bucket-Policy", "Private" );   _Put_Bucket (200, $namespace2, $bucket1);
   _AddHeader  ("X-Bucket-Policy", "[RWRW..]");   _Put_Bucket (200, $namespace2, $bucket2);
   _AddHeader  ("X-Bucket-Policy", "Public"  );   _Put_Bucket (200, $namespace2, $bucket3);
   
   #view namespaces
   SetTestGroup("Authentication:ViewNamespaces");
   SetUser     ("admin", "password");
   _Get_Namespace (200, $namespace1);
   _Get_Namespace (200, $namespace2);
   SetUser     ("testowner1", "password");
   _Get_Namespace (200, $namespace1);
   _Get_Namespace (403, $namespace2);
   SetUser     ("testowner2", "password");
   _Get_Namespace (403, $namespace1);
   _Get_Namespace (200, $namespace2);
   SetUser     ("user", "password");
   _Get_Namespace (403, $namespace1);
   _Get_Namespace (403, $namespace2);
   SetUser     ("", "");
   _Get_Namespace (401, $namespace1);
   _Get_Namespace (401, $namespace2);
   
   #view buckets
   SetTestGroup("Authentication:ViewBuckets");
   SetUser     ("admin", "password");
   _Get_Bucket (200, $namespace1, $bucket1);
   _Get_Bucket (200, $namespace1, $bucket2);
   _Get_Bucket (200, $namespace1, $bucket3);
   _Get_Bucket (200, $namespace2, $bucket1);
   _Get_Bucket (200, $namespace2, $bucket2);
   _Get_Bucket (200, $namespace2, $bucket3);
   SetUser     ("testowner1", "password");
   _Get_Bucket (200, $namespace1, $bucket1);
   _Get_Bucket (200, $namespace1, $bucket2);
   _Get_Bucket (200, $namespace1, $bucket3);
   _Get_Bucket (403, $namespace2, $bucket1); # cannot index private bucket
   _Get_Bucket (200, $namespace2, $bucket2);
   _Get_Bucket (200, $namespace2, $bucket3);
   SetUser     ("user", "password");
   _Get_Bucket (403, $namespace1, $bucket1);
   _Get_Bucket (200, $namespace1, $bucket2);
   _Get_Bucket (200, $namespace1, $bucket3);
   _Get_Bucket (403, $namespace2, $bucket1); # cannot index private bucket
   _Get_Bucket (200, $namespace2, $bucket2);
   _Get_Bucket (200, $namespace2, $bucket3);
   
   #put objects   
   SetTestGroup("Authentication:PutObjects");
   SetUser     ("admin", "password");
   _Put_Object (200, $namespace1, $bucket1, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket3, $object1, $filespec1);
   SetUser     ("testowner1", "password");
   _Put_Object (200, $namespace1, $bucket1, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket3, $object1, $filespec1);
   _Put_Object (403, $namespace2, $bucket1, $object1, $filespec1);
   _Put_Object (200, $namespace2, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace2, $bucket3, $object1, $filespec1);
   SetUser     ("user", "password");
   _Put_Object (403, $namespace1, $bucket1, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket3, $object1, $filespec1);
   _Put_Object (403, $namespace2, $bucket1, $object1, $filespec1);
   _Put_Object (200, $namespace2, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace2, $bucket3, $object1, $filespec1);
   SetUser     ("", "");
   _Put_Object (401, $namespace1, $bucket1, $object1, $filespec1);
   _Put_Object (401, $namespace1, $bucket2, $object1, $filespec1);
   _Put_Object (200, $namespace1, $bucket3, $object1, $filespec1);
   
   #get objects   
   SetTestGroup("Authentication:GetObjects");
   SetUser     ("admin", "password");
   _Get_Object (200, $namespace1, $bucket1, $object1);
   _Get_Object (200, $namespace1, $bucket2, $object1);
   _Get_Object (200, $namespace1, $bucket3, $object1);
   SetUser     ("testowner1", "password");
   _Get_Object (200, $namespace1, $bucket1, $object1);
   _Get_Object (200, $namespace1, $bucket2, $object1);
   _Get_Object (200, $namespace1, $bucket3, $object1);
   _Get_Object (403, $namespace2, $bucket1, $object1);
   _Get_Object (200, $namespace2, $bucket2, $object1);
   _Get_Object (200, $namespace2, $bucket3, $object1);
   SetUser     ("user", "password");
   _Get_Object (403, $namespace1, $bucket1, $object1);
   _Get_Object (200, $namespace1, $bucket2, $object1);
   _Get_Object (200, $namespace1, $bucket3, $object1);
   _Get_Object (403, $namespace2, $bucket1, $object1);
   _Get_Object (200, $namespace2, $bucket2, $object1);
   _Get_Object (200, $namespace2, $bucket3, $object1);
   SetUser     ("", "");
   _Get_Object (401, $namespace1, $bucket1, $object1);
   _Get_Object (401, $namespace1, $bucket2, $object1);
   _Get_Object (200, $namespace1, $bucket3, $object1);
   
   #delete objects
   SetUser        ("testowner1", "password");
   _Delete_Object (403, $namespace2, $bucket1, $object1);
   SetUser        ("testowner2", "password");
   _Delete_Object (403, $namespace1, $bucket1, $object1);
   SetUser        ("", "");
   _Delete_Object (401, $namespace1, $bucket1, $object1);
   _Delete_Object (401, $namespace1, $bucket2, $object1);
   _Delete_Object (200, $namespace1, $bucket3, $object1);
      
   #cleanup   
   SetTestGroup("Authentication:Cleanup");
   SetUser     ("testowner1", "password");
   _Delete_Bucket (200, $namespace1, $bucket1);
   _Delete_Bucket (200, $namespace1, $bucket2);
   _Delete_Bucket (200, $namespace1, $bucket3);
   SetUser     ("testowner2", "password");
   _Delete_Bucket (200, $namespace2, $bucket1);
   _Delete_Bucket (200, $namespace2, $bucket2);
   _Delete_Bucket (200, $namespace2, $bucket3);
   }


#
#
#
sub Test_BucketAliases
   {
   my ($namespace, $bucket) =  Defaults ();
   
   SetTestGroup("Aliases");
   SetUser ("testowner1", "password");
   
   _tba ($namespace, $bucket, "[RW....]", "Private" );
   _tba ($namespace, $bucket, "[RWRWRW]", "Public"  );
   _tba ($namespace, $bucket, "[RW.W..]", "Lockbox" );
   _tba ($namespace, $bucket, "[RWR.R.]", "Publish" );
   _tba ($namespace, $bucket, "Private" , "Private" );
   _tba ($namespace, $bucket, "Public"  , "Public"  );
   _tba ($namespace, $bucket, "Lockbox" , "Lockbox" );
   _tba ($namespace, $bucket, "Publish" , "Publish" );
   _tba ($namespace, $bucket, "[R.....]", "[R.....]");
   _tba ($namespace, $bucket, "[RWRWR.]", "[RWRWR.]");
   _tba ($namespace, $bucket, "[R.R.R.]", "[R.R.R.]");
   }

sub _tba 
   {
   my ($namespace, $bucket, $policy, $alias) = @_;
   
   SetTestGroup  ("Aliase:$alias");
   _AddHeader    ("X-Bucket-Policy", $policy);
   _Put_Bucket   (200, $namespace, $bucket);
   _Get_Bucket   (200, $namespace, $bucket);
   _Assert_Header("X-Bucket-Policy", $alias);
   _Delete_Bucket(200, $namespace, $bucket);
   }


   
sub Test_BucketAttributes
   {
   my ($namespace, $bucket) =  Defaults ();
   
   SetTestGroup("Attributes");
   
   _tbat ("admin",      "password", $namespace, $bucket);
   _tbat ("testowner1", "password", $namespace, $bucket);
   }
   
sub _tbat
   {
   my ($user, $password, $namespace, $bucket) = @_;
   
   my %header = 
      ("X-Bucket-Policy"          => 'Public'                                     ,
       "X-Bucket-Max-Size"        => '123456'                                     ,
       "X-Bucket-Max-Objects"     => '987'                                        ,
       "X-Bucket-Signature-Cert"  => 'http://www.wingnut.com/foo/bar/sig_cert.der',
       "X-Bucket-Encryption-Cert" => 'http://a.com/enc.der'                       ,
       "X-Custom-Metadata"        => 'name=fred,date=11-03-82,rank=JuniorMint'    );
   
   SetTestGroup ("Attributes:$user");
   SetUser ("testowner1", "password");
   map {_AddHeader ($_, $header{$_})} (keys %header);
   _Put_Bucket (200, $namespace, $bucket);
   _Get_Bucket (200, $namespace, $bucket);
   map {_Assert_Header ($_, $header{$_})} (keys %header);
   _Delete_Bucket (200, $namespace, $bucket);
   }
   
   
sub Test_Objects
   {
   my ($namespace, $bucket, $object)  = Defaults ();
   
   SetTestGroup("Objects");
   
   _Put_Bucket (200, $namespace, $bucket);

   _to ("text/plain", "foo=bar"    , 16             );
   _to ("text/html" , "name=fred"  , 4096           );
   _to ("text/plain", "yoko=ono"   , 32767          );
   _to ("text/plain", ""           , 100000         );
   _to ("text/zip"  , "size=123456", 1024 * 1024 * 1);
#  _to ("text/zip"  , "size=123456", 1024 * 1024 * 2);  ok, but slow
#  _to ("text/zip"  , "size=123456", 1024 * 1024 * 4);  ok, but slow
   
   _Delete_Bucket (200, $namespace, $bucket);
   }
   
   
sub _to
   {
   my ($content_type, $custom_metadata, $object_size) = @_;
   
   SetTestGroup("Objects:$object_size");
   
   my ($namespace, $bucket, $object) = Defaults ();
   my $filespec = "tempfile.dat";
   
   MakeSampleFile ($filespec, $object_size);
   
   my %header = 
      ("Content-Type"      => $content_type         ,
       "X-Custom-Metadata" => $custom_metadata      ,
       "Content-Length"    => $object_size          ,
       "Content-MD5"       => GetMD5 ($filespec));
   
   map {_AddHeader ($_, $header{$_})} (keys %header);
   _Put_Object (200, $namespace, $bucket, $object, $filespec);
   _Get_Object (200, $namespace, $bucket, $object);
   map {_Assert_Header ($_, $header{$_})} (keys %header);
   
   _Assert_CompareContent ($filespec) if $object_size;
   
   _Delete_Object (200, $namespace, $bucket, $object);
   unlink $filespec;
   }   
   
   
sub Test_BucketTypes 
   {
   print "Test_BucketTypes : todo!\n";
   }
   
sub Test_Certificates
   {
   print "Test_Certificates : todo!\n";
   }

sub Test_Signatures  
   {
   print "Test_Signatures : todo!\n";
   }
   
###############################################################################   
#   
# passthrough wrapers for our test client
#   

sub _Req
   {
   my ($verb, $test_name, $expected_status, $namespace, $bucket, $object, $filespec) = @_;
   
   my $client = GetClient();
   my $url    = url ($namespace, $bucket, $object);
   $client->SetTestName("$verb $test_name");
   $client->SetUser ();
   
   $client->Head   ($url, $filespec) if $verb =~ /^HEAD/i;
   $client->Get    ($url, $filespec) if $verb =~ /^GET/i;
   $client->Put    ($url, $filespec) if $verb =~ /^PUT/i;
   $client->Post   ($url, $filespec) if $verb =~ /^POST/i;
   $client->Delete ($url, $filespec) if $verb =~ /^DELETE/i;
   
   $client->Assert_Code ($expected_status);
   }

sub _Head_Ping        {_Req("HEAD"  , "Ping"     , @_)}
sub _Head_Namespace   {_Req("HEAD"  , "Namespace", @_)}
sub _Head_Bucket      {_Req("HEAD"  , "Bucket"   , @_)}
sub _Head_Object      {_Req("HEAD"  , "Object"   , @_)}
   
sub _Get_Ping         {_Req("GET"   , "Ping"     , @_)}
sub _Get_Namespace    {_Req("GET"   , "Namespace", @_)}
sub _Get_Bucket       {_Req("GET"   , "Bucket"   , @_)}
sub _Get_Object       {_Req("GET"   , "Object"   , @_)}

sub _Put_Ping         {_Req("PUT"   , "Ping"     , @_)}
sub _Put_Namespace    {_Req("PUT"   , "Namespace", @_)}
sub _Put_Bucket       {_Req("PUT"   , "Bucket"   , @_)}
sub _Put_Object       {_Req("PUT"   , "Object"   , @_)}

sub _Post_Ping        {_Req("POST"   , "Ping"     , @_)}
sub _Post_Namespace   {_Req("POST"   , "Namespace", @_)}
sub _Post_Bucket      {_Req("POST"   , "Bucket"   , @_)}
sub _Post_Object      {_Req("POST"   , "Object"   , @_)}

sub _Delete_Ping      {_Req("DELETE", "Ping"     , @_)}
sub _Delete_Namespace {_Req("DELETE", "Namespace", @_)}
sub _Delete_Bucket    {_Req("DELETE", "Bucket"   , @_)}
sub _Delete_Object    {_Req("DELETE", "Object"   , @_)}


sub _AddHeader            {GetClient()->AddHeader              (@_) }; # (name, value0
sub _Assert_Header        {GetClient()->Assert_Response_Header (@_) }; #(header_name, value)
sub _Assert_Content       {GetClient()->Assert_XML_Content     (@_) }; #(xpath_expr , value)
sub _Assert_CompareContent{GetClient()->Assert_CompareContent  (@_) }; #(filespec)
sub _Header_Text          {GetClient()->GetResponse()->header  (@_) }; #(header_name) 
sub DumpResponse          {GetClient()->DumpResponse           (@_) }; #(header_name) 


###############################################################################   
#   
# helpers  
#

my $CURRENT_CLIENT = undef;

sub GetClient
   {
   $CURRENT_CLIENT = Blue::TestClient->new($BASE_URL) if !$CURRENT_CLIENT;
   return $CURRENT_CLIENT;
   }
   
sub SetClient
   {
   my ($client) = @_;
   return $CURRENT_CLIENT = $client;
   }

sub SetUser
   {
   my ($userid, $password) = @_;
   GetClient()->SetUser ($userid, $password);
   }

sub SetTestGroup
   {
   my ($name) = @_;
   GetClient()->SetTestGroup ($name);
   }
   
sub SetTestName
   {
   my ($name) = @_;
   GetClient()->SetTestName ($name);
   }

sub url
   {
   my ($namespace, $bucket, $object) = @_;

   return "/" . 
          ($namespace ? "$namespace/" : "") . 
          ($bucket    ? "$bucket/"    : "") . 
          ($object    ? "$object"     : "") ;
   }







   
#  #   DumpRequest ();
#  #   DumpResponse (1);
#  #
#  sub Test_Workflow
#     {
#     my ($url) = @_;
#  
#     my $client = Blue::TestClient->new();
#  
#     $client->SetUser ("craig", "password");
#  
#     #setup
#     $client->SetUser(); $client->Delete ("$url/craigspace/testbucket/"); 
#     $client->SetUser(); $client->Delete ("$url/craigspace/testbucket2/"); 
#  
#     #make buckets
#     _Create_Bucket_Y ($client, $url, "craigspace", "testbucket",  "private", "a=b,c=d,e=g,g=h"         );
#     _Create_Bucket_Y ($client, $url, "craigspace", "testbucket2", "public" , "bingo=bango,bongo=irving");
#  
#     #make/upload samples
#     MakeSampleFile ("a.in", 1024 * 1 );
#     MakeSampleFile ('b.in', 1024 * 16 );
#     _Upload_Object_Y ($client, $url, "craigspace", "testbucket", "a.dat", "a.in", "x-application/octet-stream", "foo=bar");
#     _Upload_Object_Y ($client, $url, "craigspace", "testbucket", "b.gz" , "b.in", "x-application/gzip"        , "fred=barney,wilma=betty");
#  
#     # get an index of my buckets
#     $client->Get ("$url/craigspace/"); 
#  #$client->DumpRequest (1);   
#  #$client->DumpResponse (1);   
#  
#     $client->Assert_Code      (200, "GET $url/craigspace/");
#     $client->Assert_XML_Count ("//buckets/bucket", 2);
#     _Check_Namespace ($client, 1, "testbucket" , "craig", "[RW....]", "a=b,c=d,e=g,g=h"         );
#     _Check_Namespace ($client, 2, "testbucket2", "craig", "[RWRWRW]", "bingo=bango,bongo=irving");
#  
#     # get an index of 1st bucket
#     $client->SetUser ();
#     $client->Get ("$url/craigspace/testbucket/"); 
#  
#  #$client->DumpResponse (1);   
#  
#     _Check_Bucket_Y      ($client, $url, "craigspace", "testbucket", "17408", "2", "");
#     _Check_Bucket_Object ($client, 1, "testbucket", "a.dat", "x-application/octet-stream", "1024",  "foo=bar"                );
#     _Check_Bucket_Object ($client, 2, "testbucket", "b.gz" , "x-application/gzip"        , "16384", "fred=barney,wilma=betty");
#  
#  
#     # success-get test object a.dat
#     $client->SetUser ();
#     $client->Get     ("$url/craigspace/testbucket/a.dat"); 
#     _Check_Get_Object ($client, $url, "craigspace", "testbucket", "a.dat", "a.in", "1024", "x-application/octet-stream", "foo=bar");
#  
#     # success-get test object
#     $client->SetUser ();
#     $client->Get     ("$url/craigspace/testbucket/b.gz"); 
#     _Check_Get_Object ($client, $url, "craigspace", "testbucket", "b.gz",  "b.in", 1024*16, "x-application/gzip", "fred=barney,wilma=betty");
#  
#     # success-get test object a.dat
#     $client->SetUser                ();
#     $client->Get                    ("$url/craigspace/testbucket/b.gz"                ); 
#     $client->Assert_Code            (200, "GET $url"                                ,1);
#     $client->Assert_Response_Header ("Content-Length"   , "16384"                     );
#     $client->Assert_Response_Header ("Content-Type"     , "x-application/gzip"        );
#     $client->Assert_Response_Header ("X-Custom-Metadata", "fred=barney,wilma=betty"   );
#  
#  
#  #   # fail get non existing object
#  #   $client->SetUser   ();
#  #   $client->Get                    ("$url/craigspace/testbucket/nothete.txt"         ); 
#  #   $client->Assert_Code            (403, "GET $url"                                  );
#  #   $client->Assert_XML_Content     ("//error/message", "object 'craigspace/testbucket/nothete.txt' not found");
#     
#     _Delete_Bucket_Y ($client, $url, "craigspace", "testbucket");
#     _Delete_Bucket_Y ($client, $url, "craigspace", "testbucket2");
#  
#     $TOTAL_TESTS    += $client->GetAssertCount()   ;
#     $TOTAL_FAILURES += $client->GetAssertFailures();
#     }
#  
#  
#  
#  # Test buckets with an x509 signature requirement
#  # in this test, the actual parent certs are uploaded and the objects are verified
#  #
#  sub Test_Signatures
#     {
#     my ($url) = @_;
#  
#     my $client = Blue::TestClient->new();
#     
#     $client->SetUser ("admin", "password");
#  
#     my $namespace     = "tspace"                ;
#     my $bucket        = "test-a"                ;
#     my $parent_cert_1 = "thawte_root_1.pem"     ;
#     my $parent_cert_2 = "thawte_root_2.pem"     ;
#  #  my $signed_file_1 = "SignedObject.der"      ; # DER format
#  #  my $signed_file_2 = "SignedObject.pem"      ; # PEM format
#  #  my $signed_file_3 = "SignedObject.compound" ; # smime format
#     my $signed_file_1 = "SignedObject.dat"      ;
#  
#     $client->Get ("$url/$namespace/"); 
#     
#     #upload the cert
#     _Upload_Object_Y ($client, $url, $namespace, "cert", $parent_cert_1, $parent_cert_1, "x-application/octet-stream");
#     
#  #$client->DumpRequest (1);   
#  #$client->DumpResponse (1);   
#     
#     _Upload_Object_Y ($client, $url, $namespace, "cert", $parent_cert_2, $parent_cert_2, "x-application/octet-stream");
#     $client->Get ("$url/$namespace/cert/");
#  
#     # make sig-required bucket
#     $client->AddHeader ("X-Bucket-Signature-Cert", "$parent_cert_1,$parent_cert_2");
#     _Create_Bucket_Y ($client, $url, $namespace, $bucket,  "Lockbox", "comment=For testing Signatures");
#  
#     #upload a signed der object
#     _Upload_Object_Y ($client, $url, $namespace, $bucket,  $signed_file_1, $signed_file_1);
#  
#  #  #upload a signed pem object
#  #  _Upload_Object_Y ($client, $url, $namespace, $bucket,  $signed_file_2, $signed_file_2);
#  #
#  #  #upload a signed pem object
#  #  _Upload_Object_Y ($client, $url, $namespace, $bucket,  $signed_file_3, $signed_file_3);
#  #   #upload a signed der object
#  
#     $client->Get ("$url/$namespace/$bucket"); 
#     
#     _Delete_Bucket_Y ($client, $url, $namespace, $bucket);
#     _Delete_Bucket_Y ($client, $url, $namespace, 'cert');
#     
#     $TOTAL_TESTS    += $client->GetAssertCount()   ;
#     $TOTAL_FAILURES += $client->GetAssertFailures();
#     }
#  
#     
#     
#     
#  # Test buckets with an x509 signature requirement
#  # in this test, the actual parent certs are uploaded and the objects are verified
#  #
#  sub Test_Z
#     {
#     my ($url) = @_;
#  
#     my $client = Blue::TestClient->new();
#     
#     $client->SetUser   ("admin", "password");
#  
#     my $namespace     = "zspace"                ;
#     my $bucket        = "test-a"                ;
#     my $parent_cert_1 = "thawte_root_1.pem"     ;
#     my $parent_cert_2 = "thawte_root_2.pem"     ;
#     my $signed_file_1 = "SignedObject.dat"      ;
#  
#     $client->Get ("$url/$namespace/"); 
#  
#     #upload the cert
#     _Upload_Object_Y ($client, $url, $namespace, "cert", $parent_cert_1, $parent_cert_1, "x-application/octet-stream");
#     _Upload_Object_Y ($client, $url, $namespace, "cert", $parent_cert_2, $parent_cert_2, "x-application/octet-stream");
#     $client->Get ("$url/$namespace/cert/");
#  
#     # make sig-required bucket
#     $client->AddHeader ("X-Bucket-Signature-Cert", "$parent_cert_1,$parent_cert_2");
#     _Create_Bucket_Y ($client, $url, $namespace, $bucket,  "Lockbox", "comment=For testing Signatures");
#  
#  #   _Upload_Object_Y ($client, $url, $namespace, $bucket,  $signed_file_1, $signed_file_1);
#  #
#  #   $client->Get ("$url/$namespace/$bucket"); 
#  #   
#  #   _Delete_Bucket_Y ($client, $url, $namespace, $bucket);
#  #   _Delete_Bucket_Y ($client, $url, $namespace, 'cert');
#     }
#  
#  
#  sub Test_Z2
#     {
#     my ($url) = @_;
#  
#     my $client = Blue::TestClient->new();
#     
#     $client->SetUser   ("admin", "password");
#  
#     my $namespace     = "zspace"          ;
#     my $bucket        = "test-a"          ;
#     my $signed_file_1 = "SignedObject.dat";
#  
#     $client->AddHeader ("Content-MD5"                      , GetMD5 ($signed_file_1)   );
#     $client->AddHeader ("Content-Length"                   , GetLength ($signed_file_1));
#     $client->Put ("$url/$namespace/$bucket/$signed_file_1" , $signed_file_1            );
#     $client->DumpResponse (1);
#  
#     $client->Assert_Code            (200, "PUT $url/$namespace/$bucket/$signed_file_1");
#     $client->Assert_XML_Content     ("//response", "object '$namespace/$bucket/$signed_file_1' stored");
#     }
#     
#     
#     
#     
#  
#  #   # Test buckets with an x509 signature requirement
#  #   # in this test, the bucket simply requires the object to be signed by anybody
#  #   #
#  #   sub Test_Signatures2
#  #      {
#  #      my ($url) = @_;
#  #   
#  #      SetUser   ("admin", "password");
#  #   
#  #      my $namespace     = "tspace"                ;
#  #      my $bucket        = "test-b"                ;
#  #      my $signed_file_1 = "SignedObject.der"      ; # DER format
#  #      my $signed_file_2 = "SignedObject.pem"      ; # PEM format
#  #      my $signed_file_3 = "SignedObject.compound" ; # smime format
#  #   
#  #      Get ("$url/$namespace/"); 
#  #   
#  #      # make sig-required bucket
#  #      SetHeader ("X-Bucket-Signature-Cert", "*");
#  #      _Create_Bucket_Y ($url, $namespace, $bucket,  "Lockbox", "comment=For testing Signatures");
#  #   
#  #      #upload a signed der object
#  #      _Upload_Object_Y ($url, $namespace, $bucket,  $signed_file_1, $signed_file_1);
#  #   
#  #      #upload a signed pem object
#  #      _Upload_Object_Y ($url, $namespace, $bucket,  $signed_file_2, $signed_file_2);
#  #   
#  #      #upload a signed pem object
#  #      _Upload_Object_Y ($url, $namespace, $bucket,  $signed_file_3, $signed_file_3);
#  #   
#  #      Get ("$url/$namespace/$bucket"); 
#  #      
#  #      _Delete_Bucket_Y ($url, $namespace, $bucket);
#  #      _Delete_Bucket_Y ($url, $namespace, 'cert');
#  #      }
#     
#     
#  sub Test_9
#     {
#     my ($url) = @_;
#  
#     my $client = Blue::TestClient->new();
#     $client->SetUser("admin", "password");
#     $client->Delete ("$url/craigspace/tb1/"); 
#  
#     $client->SetUser   ();
#     $client->AddHeader ("X-Bucket-Policy", '[RW.W..]');
#     $client->AddHeader ("X-Custom-Metadata", "foo=bar");
#     $client->Put       ("$url/craigspace/tb1/"); 
#  
#     $client->DumpRequest ();
#     $client->DumpResponse ();
#  
#     $TOTAL_TESTS    += $client->GetAssertCount()   ;
#     $TOTAL_FAILURES += $client->GetAssertFailures();
#     }
#  
#  
#  
#  ###############################################################################
#  #
#  # test helpers
#  #
#  
#  sub _Create_Bucket_Y
#     {
#     my ($client, $url, $namespace, $bucket, $type, $metadata) = @_;
#     _im_here(@_);
#  
#     # create a bucket
#     $client->SetUser   ();
#     $client->AddHeader ("X-Bucket-Policy", $type);
#     $client->AddHeader ("X-Custom-Metadata", $metadata);
#     $client->Put       ("$url/$namespace/$bucket/"); 
#  
#     $client->Assert_Code            (200, "PUT $url/$namespace/$bucket");
#     $client->Assert_Response_Header ("Content-Type" , "text/xml"  ,                        );
#     $client->Assert_XML_Content     ("//response"   , "bucket '$namespace/$bucket' created",  $WORDY);
#     }
#  
#  
#  sub _Delete_Bucket_Y
#     {
#     my ($client, $url, $namespace, $bucket) = @_;
#     _im_here(@_);
#  
#     # remove the bucket
#     $client->SetUser ();
#     $client->Delete  ("$url/$namespace/$bucket/"); 
#     $client->Assert_Code            (200, "DELETE $url/$namespace/$bucket");
#     $client->Assert_Response_Header ("Content-Type" , "text/xml");
#     $client->Assert_XML_Content     ("//response", "bucket '$namespace/$bucket' removed",  $WORDY);
#     }
#  
#  
#  sub _Upload_Object_Y
#     {
#     my ($client, $url, $namespace, $bucket, $object, $filespec, $content_type, $metadata) = @_;
#     _im_here(@_);
#  
#     # upload a sample file
#     $client->SetUser   ();
#     $client->AddHeader ("Content-Type"              , $content_type        ) if $content_type;
#     $client->AddHeader ("X-Custom-Metadata"         , $metadata            ) if $metadata    ;
#     $client->AddHeader ("Content-MD5"               , GetMD5 ($filespec)   );
#     $client->AddHeader ("Content-Length"            , GetLength ($filespec));
#     $client->Put ("$url/$namespace/$bucket/$object" , $filespec            );
#  
#     $client->Assert_Code            (200, "PUT $url/$namespace/$bucket/$object");
#     $client->Assert_XML_Content     ("//response", "object '$namespace/$bucket/$object' stored");
#     }
#  
#  
#  sub _Check_Namespace
#     {
#     my ($client, $index, $bucket, $owner, $policy, $metadata) = @_;
#     _im_here(@_);
#  
#     $client->Assert_XML_Content ("//buckets/bucket[$index]/name"           , $bucket,$WORDY) if defined $bucket  ;
#     $client->Assert_XML_Content ("//buckets/bucket[$index]/policy"         , $policy  )      if defined $policy  ;
#     $client->Assert_XML_Content ("//buckets/bucket[$index]/custom_metadata", $metadata)      if defined $metadata;
#     }  
#  
#  
#  sub _Check_Bucket_Y
#     {
#     my ($client, $url, $namespace, $bucket, $total_size, $object_count, $max_size)  = @_;
#  
#     _im_here(@_);
#     # get an index of 1st bucket
#     $client->Assert_Code        (200, "GET $url/$namespace/$bucket") or return;
#     $client->Assert_XML_Content ("//bucket/total_size"  , $total_size,$WORDY) if defined $total_size  ;
#     $client->Assert_XML_Content ("//bucket/object_count", $object_count)      if defined $object_count;
#     $client->Assert_XML_Content ("//bucket/max_size"    , $max_size    )      if defined $max_size    ;
#     }
#  
#  
#  sub _Check_Bucket_Object
#     {
#     my ($client, $object_index, $bucket, $object, $content_type, $content_length, $custom_metadata) = @_;
#  
#     _im_here(@_);
#     $client->Assert_XML_Content ("//bucket/objects/object[$object_index]/name"           , $object, $WORDY ) if defined $object         ;
#     $client->Assert_XML_Content ("//bucket/objects/object[$object_index]/bucket"         , $bucket         ) if defined $bucket         ;
#     $client->Assert_XML_Content ("//bucket/objects/object[$object_index]/content_type"   , $content_type   ) if defined $content_type   ;
#     $client->Assert_XML_Content ("//bucket/objects/object[$object_index]/content_length" , $content_length ) if defined $content_length ;
#     $client->Assert_XML_Content ("//bucket/objects/object[$object_index]/custom_metadata", $custom_metadata) if defined $custom_metadata;
#     }
#  
#  sub _Check_Get_Object
#     {
#     my ($client, $url, $namespace, $bucket, $object, $filespec, $object_size, $content_type, $metadata)  = @_;
#  
#     _im_here(@_);
#     $client->Assert_Code            (200, "GET $url/$namespace/$bucket/$object", 1) || return;
#     $client->Assert_Response_Header ("Content-Length"   , $object_size            ) if defined $object_size ;
#     $client->Assert_Response_Header ("Content-Type"     , $content_type           ) if defined $content_type;
#     $client->Assert_Response_Header ("X-Custom-Metadata", $metadata               ) if defined $metadata    ;
#     $client->Assert_CompareContent  ($filespec) if $object_size;
#     }
#  
#  
#  ##########################################################################
#  
#  
#  
#  
#  
#  
#  sub _im_here
#     {
#     shift;
#     my ($package, $filename, $line, $subr, $has_args, $wantarray) = caller (1);
#     ($subr) = $subr =~ m{^.*::([^:]+)$};
#     my $params = "(" . join (",", @_) . ")";
#     print "$subr";
#     print "$params" if $WORDY;
#     print "\n";
#     }


sub Usage
   {
   print while <DATA>;
   exit (0);
   }


__DATA__
 
OCLIENT - Command line Queue utility
 
Usage: BTEST url
 
WHERE: url    - the blue elephant server URL
