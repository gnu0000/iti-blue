#!perl
#
# http resource manager with REST / ROA interface
#
# This server allows users to create storage areas (buckets) and to
# store and retrieve resources.
#
#
# GET    http://whateverhost/root/             get a directory of buckets you own
# PUT    http://whateverhost/root/             -na-
# DELETE http://whateverhost/root/             -na-
# HEAD   http://whateverhost/root/             -na-
#
# GET    http://whateverhost/root/foo/         get a directory of bucket named foo
# PUT    http://whateverhost/root/foo/         create a bucket named foo
# DELETE http://whateverhost/root/foo/         delete a bucket named foo
# HEAD   http://whateverhost/root/foo/         get metadata info about foo
#
# GET    http://whateverhost/root/foo/bar.txt  get resource named bar.txt in bucket foo
# PUT    http://whateverhost/root/foo/bar.txt  upload resource bar.txt
# DELETE http://whateverhost/root/foo/bar.txt  delete resource bar.txt
# HEAD   http://whateverhost/root/foo/bar.txt  get metadata info about bar.txt
#
#
# Several Headers are used or may be used by the client and/or server
#
# Content-Length
#   the client should send thes when uploading a file (although it is optional)
#   resource GET and HEAD requests get this header back
#
# Content-MD5
#   the client should send thes when uploading a file (although it is optional)
#   resource GET and HEAD requests get this header back if it whas provided on upload
#
# Content-Type
#   the client should send thes when uploading a file (although it is optional)
#   resource GET and HEAD requests get this header back.  defaults to x/application-data
#  if not specified
#
# X-Bucket-Policy
#   the client should send this when creating a bucket.  The options are:
#     timelock - 1> Authenticated users may add resources (until the deadline)
#                2> Authenticated users may get or modily only their resources (until the deadline)
#                3> Owner may get resources only after the deadline
#     |RWRWRW| - Set Read/Write permissions for Owner,authenticated user,anon user
#     lockbox  - Synonym for [RW.W..]
#     private  - Synonym for [RW....]
#     public   - Synonym for [RWRWRW]
#
#     Note that the 'R' permission actually means 'read other peoples stuff'.  a 'W' flag
#     allows writes but also reads to your own resource.  So for instance, in the lockbox
#     above, authenticated users may post resources, and read thier own resources but
#     not view other peoples resources.
# 
# X-Custom-Metadata
#   the client may send this when creating a bucket or uploading a resource.
#   GET and HEAD requests on a bucket or resource will return this is present.
#
# X-Blue-Authorization
#   Request based authentication
#
# X-Bucket-Max-Size
#   max size of objects in bytes of the bucket
#
# X-Bucket-Max-Objects
#   max count of objects in bytes of the bucket
#
# X-Bucket-Signature-Cert
#   csv list of certs, the chain of parents to verify sig
#
# X-Bucket-Encryption-Cert
#   *not implemented*
#
# URL extra params
#
# ?method=PUT
#   You may use this param to overrid the http verb.  This is usefull for doung things like deleting
#   resources from within a web browser
#
#

use lib '../lib';
use strict;
use warnings;
use CGI::Carp        qw (fatalsToBrowser);  # remove eventually
use URI::Split       qw(uri_split);
use Time::Local;
use Digest::MD5      qw(md5);
use File::Basename;
use File::Path;
use XML::Simple;
use Blue::Resource;
use Blue::Config     qw(Setting);
use Blue::Util;
use Blue::DB         qw(GetDB);
use Blue::Auth       qw(CheckNamespacePrivilege CheckBucketPrivilege CheckObjectPrivilege);
use Blue::Response   qw(Error Response_xml Response_raw AddContentLengthHeader AddMD5Header SetBucketHeaders SetObjectHeaders SetContentLocationHeader);
use Blue::Template   qw(Template TemplateList);
use Blue::DebugLog   qw(DebugLog GetDebugLog);
use Blue::User       qw(GetUser);
use Blue::ServiceLog qw(SetLogInfo);
use Blue::Untaint;

MAIN:
#  GetUser (); # for side effect: authenticate if auth info provided
   Route ();
#   exit (0);


###############################################################################


# return information about the service
#
sub GetInfoHandler ()
   {
   my $user = GetUser ();
   
   return Response_xml (200, Template ('user_info', %{$user}));

#   my @namespaces = GetNamespaces ();
#   my $location   = GetContentLocation ();
#   return Response_xml (200, TemplateList ('namespace_index', \@namespaces, location=>$location));
   }


   
# create a new bucket
#
sub PostNamespaceHandler
   {
   my ($namespace) = @_;

   my $bucket_name = GenerateBucketName ();
   return PutBucketHandler ($namespace, $bucket_name);
   }


# get index of all buckets in a namespace
# xxx 1st cut: you need to own a namespace to get an index of it's buckets:
#
sub GetNamespaceHandler
   {
   my ($namespace) = @_;

   CheckNamespacePrivilege ($namespace, "read", 1);
   my @buckets  = GetBuckets ($namespace);
   my $location = GetContentLocation ($namespace);

   return Error (403, "Namespace '$namespace' does not exist") if !scalar @buckets && !ExistingNamespace ($namespace);
   return Response_xml (200, TemplateList ('bucket_index', \@buckets, namespace=>$namespace, location=>$location));
   }



# get index of all buckets in a namespace
# xxx 1st cut: you need to own a namespace to get an index of it's buckets:
#
sub HeadNamespaceHandler
   {
   my ($namespace) = @_;

   CheckNamespacePrivilege ($namespace, "read", 1);
   my @buckets = GetBuckets ($namespace);

   return Error (403, "Namespace '$namespace' does not exist") if !scalar @buckets && !ExistingNamespace ($namespace);
   return Response_raw (200, "", "text/xml");
   }



# get index of all objects in a namespace
# if the user has read permission, all objects are returned
# if the user does not have read permission, only owned objects are returned
#
sub GetBucketHandler
   {  
   my ($namespace, $bucket_name) = @_;

   CheckBucketExists ($namespace, $bucket_name, 1);
   
   my $can_read = CheckBucketPrivilege ($namespace, $bucket_name, "read", 0);
   
   # if user cannot read or write, they cannot get a bucket index either
   $can_read || CheckBucketPrivilege ($namespace, $bucket_name, "write", 0)
      || Error (403, "Insufficient privilege for operation");
   
   my $show_content = SimpleParseQuery()->{showcontent};
   my $bucket       = GetBucket ($namespace, $bucket_name);
   my @objects      = GetObjects ($namespace, $bucket_name, $can_read, $show_content);
   my $location     = GetContentLocation ($namespace, $bucket_name);
   my $path         = GetContentPath ($namespace, $bucket_name);
   map {$_->{location}=$location . $_->{name};
        $_->{path} = $path . $_->{name}} @objects;

   $bucket->{_total_size}   = 0 + Sum(map{$_->{content_length}} @objects);
   $bucket->{_object_count} = scalar @objects;

   SetBucketHeaders ($bucket);
   my $object_template = $show_content ? 'full_object_index' : 'object_index';

   return Response_xml (200, Template     ('bucket_info_start', %{$bucket}) .
                             TemplateList ($object_template   , \@objects ) .
                             Template     ('bucket_info_end'  , %{$bucket}) );
   }


sub HeadBucketHandler
   {  
   my ($namespace, $bucket_name) = @_;

   CheckBucketExists ($namespace, $bucket_name, 1);

   my $can_read = CheckBucketPrivilege ($namespace, $bucket_name, "read", 0);
   
   # if user cannot read or write, they cannot get a bucket index either
   $can_read || CheckBucketPrivilege ($namespace, $bucket_name, "write", 0)
      || Error (403, "Insufficient privilege for operation");
   
   my $bucket   = GetBucket ($namespace, $bucket_name);
   my @objects  = GetObjects ($namespace, $bucket_name, $can_read);

   $bucket->{_total_size}   = 0 + Sum(map{$_->{content_length}} @objects);
   $bucket->{_object_count} = scalar @objects;

   SetBucketHeaders ($bucket);
   return Response_raw (200, "", "text/xml");
   }


# create a bucket
# user must have write permission on the namespace
# bucket name must be legal and unused
#
sub PutBucketHandler
   {  
   my ($namespace, $bucket_name) = @_;

   CheckNamespacePrivilege ($namespace, "write", 1);
   CheckBucketName ($bucket_name);
   CheckBucketExists ($namespace, $bucket_name, 0) && Error (409, "bucket '$namespace/$bucket_name' already exists");
   
   my $ok = AddBucket ($namespace, $bucket_name);

   SetContentLocationHeader ($namespace, $bucket_name)                                         if  $ok;
   return Response_xml (200, "<response> bucket '$namespace/$bucket_name' created</response>") if  $ok;
   return Error (500, "bucket '$namespace/$bucket_name' creation failure!")                    if !$ok;
   }


sub PostBucketHandler
   {  
   my ($namespace, $bucket_name) = @_;

   my $object_name = GenerateObjectName ();
   return PutObjectHandler ($namespace, $bucket_name, $object_name)
   }


# delete a bucket
# user must have write permission on the namespace
#
sub DeleteBucketHandler
   {  
   my ($namespace, $bucket_name) = @_;

   CheckNamespacePrivilege ($namespace, "write", 1);
   CheckBucketExists ($namespace, $bucket_name , 1);
   my $ok = DeleteBucket ($namespace, $bucket_name);
   return Response_xml (200, "<response>bucket '$namespace/$bucket_name' removed</response>") if $ok;
   return Error (500, "bucket '$namespace/$bucket_name' remove failure!") if !$ok;
   }

   
# This is a hack
#
sub SearchObjectHandler   
   {  
   my ($namespace, $bucket_name, $object_name) = @_;
   
   my @objects = GetMatchingObjects ($namespace, $bucket_name, $object_name);
   map {$_->{location} = GetContentLocation ($_->{namespace}, $_->{bucket}) . $_->{name};
        $_->{path}     = GetContentPath     ($_->{namespace}, $_->{bucket}) . $_->{name}} @objects;

   # count 
   return Response_xml (200, TemplateList ('object_index', \@objects));
   }

   
sub IsAnObjectSearch
   {  
   my ($namespace, $bucket_name, $object_name) = @_;
   my $blob = $namespace . $bucket_name . $object_name;
   return $blob =~ /\*|\?/;
   }


# get an object
#
sub GetObjectHandler
   {  
   my ($namespace, $bucket_name, $object_name) = @_;

   return SearchObjectHandler ($namespace, $bucket_name, $object_name) 
      if IsAnObjectSearch ($namespace, $bucket_name, $object_name);

   CheckBucketExists ($namespace, $bucket_name, 1);
   CheckObjectPrivilege ($namespace, $bucket_name, $object_name, "read", 1);
   
   my $object = GetObject ($namespace, $bucket_name, $object_name, 1) || 
                Error (404, "object '$namespace/$bucket_name/$object_name' not found");

   SetObjectHeaders ($object);
   return Response_raw (200, $object->{value}, $object->{"content_type"});
   }


sub HeadObjectHandler
   {  
   my ($namespace, $bucket_name, $object_name) = @_;

   CheckBucketExists ($namespace, $bucket_name, 1);
   CheckObjectPrivilege ($namespace, $bucket_name, "read", 1);
   
   my $object = GetObject ($namespace, $bucket_name, $object_name, 0) || 
                Error (404, "object '$namespace/$bucket_name/$object_name' not found");

   SetObjectHeaders ($object);
   return Response_raw (200, "", $object->{"content_type"});
   }


sub PutObjectHandler
   {  
   my ($namespace, $bucket_name, $object_name) = @_;

   CheckBucketExists ($namespace, $bucket_name, 1);
   CheckObjectPrivilege ($namespace, $bucket_name, "write", 1);
   CheckObjectName ($object_name);

   my $object_exists = CheckObjectExists ($namespace, $bucket_name, $object_name, 0);
   my $verb = $object_exists ? "updated" : "stored";

   my $ok = AddObject ($namespace, $bucket_name, $object_name);

   SetContentLocationHeader ($namespace, $bucket_name, $object_name)                                      if $ok;

   return Response_xml (200, "<response> object '$namespace/$bucket_name/$object_name' $verb</response>") if $ok;
   return Error (500, "put object '$namespace/$bucket_name/$object_name' failed!")                        if !$ok;
   }


sub PostObjectHandler
   {  
   my ($namespace, $bucket_name) = @_;

   my $object_name = GenerateObjectName ();
   return PutObjectHandler ($namespace, $bucket_name, $object_name);
   }


sub DeleteObjectHandler
   {  
   my ($namespace, $bucket_name, $object_name) = @_;

   CheckBucketExists    ($namespace, $bucket_name,               1);
   CheckObjectPrivilege ($namespace, $bucket_name, "write",      1);
   CheckObjectExists    ($namespace, $bucket_name, $object_name, 1);

   my $ok = DeleteObject ($namespace, $bucket_name, $object_name);
   return Response_xml (200, "<response>object '$namespace/$bucket_name/$object_name' removed</response>") if $ok;
   return Error (500, "object '$namespace/$bucket_name/$object_name' remove failure!") if !$ok;
   }


###############################################################################


# looks at the URL and calls handlers of the form: 
#
# httpverb [bucket | object] 'Handler'
#
# handler params are the namespace, the bucket, and possibly the object.
#
# examples:
#   GET    http://whateverhost/gadot/foo/        -> GetBucketHandler    ('gadot', 'foo'           )
#   GET    http://whateverhost/gadot/foo/bar.txt -> GetObjectHandler    ('gadot', 'foo', 'bar.txt')
#   PUT    http://whateverhost/gadot/foo/        -> PutBucketHandler    ('gadot', 'foo'           )
#   PUT    http://whateverhost/gadot/foo/bar.txt -> PutObjectHandler    ('gadot', 'foo', 'bar.txt')
#   DELETE http://whateverhost/gadot/foo/bar.txt -> DeleteObjectHandler ('gadot', 'foo', 'bar.txt')
#
#
sub Route
   {
   my $script_url   = env_uri('SCRIPT_URL')    || "";
   my $service_root = Setting('blue_url_root') || "";

   my ($path) = $script_url =~ /^$service_root\/(.*)$/i;
   my ($namespace, $bucket_name, $object_name, @remainder) = split ("/", $path);
   $object_name .= "/" . join ("/", @remainder) if scalar @remainder;

   DebugLog (4,"Route::script_url: '$script_url'") ;

   my $verb = lc ((SimpleParseQuery())->{method} || env_id('REQUEST_METHOD'));
   substr ($verb, 0, 1) = uc substr ($verb, 0, 1); # camelcase the verb

   SetLogInfo (url=>$script_url, namespace=>$namespace, bucket=>$bucket_name, object=>$object_name, verb=>$verb);
   
   return GetInfoHandler () if !$namespace && $verb =~ /^(get|head)/i;  # !!may be overridden by rewrite rules!!
   return Error (403, "bad request") if !$namespace;             # !!may be overridden by rewrite rules!!
   
   my $object_type = ($object_name  ? "Object" : ($bucket_name ? "Bucket" : "Namespace"));
   my $symname     = $verb . $object_type . "Handler";

   DebugLog (2, "$symname - ".($namespace||"").":".($bucket_name||"").":".($object_name||""));
   
      {
      no strict 'refs';   
      eval {&$symname($namespace, $bucket_name, $object_name);};
      DebugLog (2, "eval $symname returned error string '$@'") if $@;
      UnknownRoute ($symname, $@) if $@;
      }
   
   }


# were not using the CGI module, so this is a simple parse to get 
# and optional query strings that may be attached to the URL
#
sub SimpleParseQuery
   {
   my @query_set=split ('&', env_text('QUERY_STRING'));
   my $params = {};
   foreach my $paramspec (@query_set)
      {
      my ($name,$value);
      ($name, $value) = split('=', $paramspec) if ($paramspec=~/=/);
      ($name, $value) = ($paramspec, 1) if !($paramspec=~/=/);
      $params->{lc $name} = lc $value;
      }
   return $params;
   }
   

sub UnknownRoute
   {
   my ($symname, $err_str) = @_;
   
   DebugLog (2, "no route to : $symname ($err_str)");
   my $msg = "unknown url" . (Setting('debug_log_level') > 2 ? " ($err_str)" : "");
   
   return Error (404, $msg);
   }
