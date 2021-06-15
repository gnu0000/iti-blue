#
# Resource.pm
# functions to return data to the client
#
# buckets and objects are cached at 1st load, so I liberally re-get them
# in parts of the app to simplify the parameter passing (without taking
# a performance hit)
#
#
#
package Blue::Resource;

use strict;
use warnings;
use Digest::MD5    qw(md5_base64);
use File::Temp     qw(tempfile);
use Text::CSV_XS;
use LWP::Simple qw(get);
use LWP::UserAgent;
use MIME::Base64;
use Blue::Config   qw(Setting);
use Blue::DB       qw(GetDB);
use Blue::Response qw(Error SysError GetHeaders);
use Blue::X509     qw(IsX509Certificate IsPEMCertificate);
use Blue::User;
use Blue::Util;
use Blue::DebugLog   qw(DebugLog GetDebugLog);

our $VERSION = 1.00;
our @ISA     = qw (Exporter);
our @EXPORT  = qw (GetNamespaces
                   GetBuckets
                   GetBucket
                   AddBucket
                   DeleteBucket
                   GetObjects
                   GetObject
                   GetMatchingObjects
                   AddObject
                   DeleteObject
                   CheckNamespaceName
                   ExistingNamespace
                   CheckBucketName
                   CheckObjectName
                   CheckBucketExists
                   CheckObjectExists
                   GenerateObjectName
                   GenerateBucketName
                  );
                  
                  
#constants
my %POLICY_ALIASES = 
   ( 
   "[RW....]" => "Private" ,
   "[RWRWRW]" => "Public"  ,
   "[RW.W..]" => "Lockbox" ,
   "[RWR.R.]" => "Publish" ,
   );
   
my $DEFAULT_POLICY = "[RW....]";



                  

#module globals
my $BUCKET_CACHE = {};
my $OBJECT_CACHE = {};

###############################################################################
#
# namespace fns
#
###############################################################################

sub GetNamespaces
   {
   my $db = GetDB();

   # namespaces actually used
   my @namespaces = $db->FetchRows ("select namespace, count(namespace) as bucket_count from bucket group by namespace");

   # build hash index of what we have so far
   my %namespace_map;
   map {$namespace_map{$_->{namespace}}=$_->{bucket_count}} @namespaces;

   # get list of valid namespaces
   my @user_namespaces = $db->FetchRows ("select distinct(namespace), 0 as bucket_count from user");

   # add unused-but-valid namespaces to namespace list
   foreach my $user_namespace (@user_namespaces)
      {
      push @namespaces, $user_namespace if $user_namespace->{namespace} && !defined $namespace_map{$user_namespace->{namespace}};
      }
   @namespaces = sort {$a->{namespace} cmp $b->{namespace}} @namespaces;

   
   my $user = GetUser ();
   foreach my $namespace (@namespaces)
      {
      my $quoted_namespace = quotemeta($namespace->{namespace});
   
      $namespace->{user_role} = $user->{role} =~ /^admin/i                                                  ? "admin"  :
                                $user->{role} =~ /^guest/i                                                  ? "guest"  :
                                $user->{role} =~ /^user/i                                                   ? "user"   :
                                $user->{role} =~ /^owner/i &&  ($user->{namespace} =~ /^$quoted_namespace/) ? "owner"  :
                                $user->{role} =~ /^owner/i && !($user->{namespace} =~ /^$quoted_namespace/) ? "user"   :
                                                                                                              "unknown";
      }
   return @namespaces;
   }


sub CheckNamespaceName
   {
   my ($namespace) = @_;

   $namespace =~ /^[a-zA-Z0-9_\-\.]+$/ or Error (400, "invalid namespace name: '$namespace'");
   }


sub ExistingNamespace
   {
   my ($namespace) = @_;

   my @rows = GetDB()->FetchRows ("select distinct(namespace) from user");
   foreach my $row (@rows)
      {
      return 1 if $row->{namespace} =~ /^$namespace$/;
      }
   return 0;
   }



###############################################################################
#
# bucket fns
#
###############################################################################


sub GetBuckets
   {
   my ($namespace) = @_;

   my @rows = GetDB()->FetchRows ("select * from bucket where namespace=?", $namespace);
   map {$_->{policy_alias} = Policy_To_PolicyAlias ($_->{policy})} @rows;
   return @rows;
   }


sub GetBucket
   {
   my ($namespace, $bucket_name) = @_;

   my $bucket = $BUCKET_CACHE->{"$namespace.$bucket_name"};
   return $bucket if defined $bucket;

   my $sql = "select * from bucket where namespace=? and name=?";
   $bucket = GetDB()->FetchRow ($sql, $namespace, $bucket_name);
   $bucket->{policy_alias} = Policy_To_PolicyAlias ($bucket->{policy}) if defined $bucket;
   return $BUCKET_CACHE->{"$namespace.$bucket_name"} = $bucket;
   }


# returns 2 element list: (object_count_in_the_bucket, total_size_of_bucket_objects)
#
sub GetBucketContentInfo
   {
   my ($namespace, $bucket_name) = @_;

   my $sql = "select count(name), sum(content_length) from object where namespace = ? and bucket = ?";
   return GetDB()->FetchList ($sql, $namespace, $bucket_name);
   }


sub AddBucket
   {
   my ($namespace, $bucket_name) = @_;

   my $user    = GetUser();
   my $headers = GetHeaders();
   my ($policy, $policy_change, $policy2) = split (",", $headers->{'X-Bucket-Policy'});
   $policy     = PolicyAlias_To_Policy ($policy) || $DEFAULT_POLICY;
   $policy2    = PolicyAlias_To_Policy ($policy2);
   
   delete $BUCKET_CACHE->{"$namespace.$bucket_name"}; # maybe changing the data

   my $sql = "replace into bucket " . 
             "(namespace, name, owner, policy, policy2, policychange, custom_metadata, max_size, max_objects, signature_cert, encryption_cert) " .
             "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

   return GetDB()->Do ($sql,
                       $namespace, 
                       $bucket_name, 
                       $user->{name}, 
                       $policy,
                       $policy2,
                       $policy_change,
                       $headers->{'X-Custom-Metadata'       } || undef,
                       $headers->{'X-Bucket-Max-Size'       } || undef,
                       $headers->{'X-Bucket-Max-Objects'    } || undef,
                       $headers->{'X-Bucket-Signature-Cert' } || undef,
                       $headers->{'X-Bucket-Encryption-Cert'} || undef);
   }


# [RW....] => Private
sub Policy_To_PolicyAlias
   {
   my ($policy) = @_;
   
   my $alias = $POLICY_ALIASES{$policy};
   return $alias || $policy;
   }
   
# Private => [RW....]
sub PolicyAlias_To_Policy
   {
   my ($policy_alias) = @_;
   
   return $policy_alias if !$policy_alias;
   map {return $_ if $POLICY_ALIASES{$_} eq $policy_alias} (keys %POLICY_ALIASES);
   return $policy_alias;
   }


# delete bucket and all objects in the bucket
#
sub DeleteBucket
   {
   my ($namespace, $bucket_name) = @_;

   delete $BUCKET_CACHE->{"$namespace.$bucket_name"}; # maybe changing the data
   
   my $db = GetDB();
   return $db->Do ("delete from object where namespace=? and bucket=?", $namespace, $bucket_name) &&
          $db->Do ("delete from bucket where namespace=? and   name=?", $namespace, $bucket_name);
   }


sub CheckBucketName
   {
   my ($bucket_name) = @_;

   $bucket_name =~ /^[a-zA-Z0-9_\-\.]+$/ or Error (400, "invalid bucket name: '$bucket_name'");
   }


sub CheckBucketExists
   {
   my ($namespace, $bucket_name, $die_on_error) = @_;

   my $bucket = GetBucket ($namespace, $bucket_name);
   my $exists = $bucket->{name};

   $exists = CreateCertBucket ($namespace) if !$exists && $bucket_name =~ /^cert$/i;

   Error (404, "bucket '$namespace/$bucket_name' does not exist") if $die_on_error && !$exists;
   return $exists ? 1 : 0;
   }


sub GenerateBucketName
   {
   return NowInFillStringFormat () . sprintf ("%5.5d", rand (32000));
   }

###############################################################################
#
# object fns
#
###############################################################################


sub GetObjects
   {
   my ($namespace, $bucket_name, $can_read_all, $include_content) = @_;

   my $db = GetDB();
   my $user_name = GetUser()->{name};
   my $columns = $include_content ? "*" : "namespace,name,bucket,owner,content_type,content_length,content_md5,custom_metadata";
   my $sql = "select $columns from object where namespace=? and bucket=?";
   $sql .=  " and owner=" . $db->Quote($user_name) unless $can_read_all;

   return $db->FetchRows ($sql, $namespace, $bucket_name);
   }


sub GetObject
   {
   my ($namespace, $bucket_name, $object_name, $include_content) = @_;

   my $object = $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.$include_content"};
   return $object if defined $object;

   my $columns = $include_content ? "*" : "namespace,name,bucket,owner,content_type,content_length,content_md5,custom_metadata";
   my $sql     = "select $columns from object where namespace=? and bucket=? and name=?";

   $object = GetDB()->FetchRow ($sql, $namespace, $bucket_name, $object_name);
   return $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.$include_content"} = $object;
   }
   
# a hack for now
sub GetMatchingObjects
   {
   my ($namespace_spec, $bucket_spec, $object_spec) = @_;
   
   $namespace_spec =~ tr/*/%/;
   $bucket_spec    =~ tr/*/%/;
   $object_spec    =~ tr/*/%/;

   my $db = GetDB();
   
   my $sql = "select "                                            .
             "bucket.namespace, "                                 .
             "bucket.policy, "                                    .
             "bucket.policy2, "                                   .
             "bucket.policychange, "                              .
             "bucket.custom_metadata as bucket_custom_metadata, " .
             "bucket.name as bucket, "                            .
             "object.owner, "                                     .
             "object.content_type, "                              .
             "object.content_length, "                            .
             "object.content_md5, "                               .
             "object.updated, "                                   .
             "object.name, "                                      .
             "object.custom_metadata "                            .
             "from bucket, object "                               .
             "where bucket.name=object.bucket "                   .
             "and bucket.namespace=object.namespace "             .
             "and object.namespace like ? "                       .
             "and object.bucket    like ? "                       .
             "and object.name      like ? "                       ;
   
   my @objects = $db->FetchRows ($sql, $namespace_spec, $bucket_spec, $object_spec);
   
   Error (400, "*** " . $db->{dbh}->errstr . " ***") if $db->{dbh}->errstr;
   
   DebugLog (4,"---SearchScript---\n$sql\nrows:" . scalar @objects);
   
   
   my $user = GetUser();
   
   my @matches;
   foreach my $row (@objects)
      {
      my $policy = $row->{policychange} && $row->{policychange} lt NowInDBFormat() ? $row->{policy2} : $row->{policy};

      push @matches, $row if 
         $user->{name} =~ /^admin$/i             ||
         $row->{owner}     eq $user->{name}      ||
         $row->{namespace} eq $user->{namespace} ||
         Blue::Auth::PolicyCheck ($policy, $user->{role}, 'read');
      }
   return @matches;
   }   


sub AddObject
   {
   my ($namespace, $bucket_name, $object_name) = @_;

   my $user          = GetUser(1);
   my $headers       = GetHeaders();
   my $data          = LoadStdin();
   my $content_type  = $headers->{'Content-Type'  } || "application/octet-stream";
   my $data_length   = $headers->{'Content-Length'};
   my $data_md5      = $headers->{'Content-MD5'   };
   my $actual_length = length $data;
   my $actual_md5    = md5_base64($data);

   Error (400, "Content-length header does not match actual content ($data_length vs $actual_length)") 
      if $data_length && ($data_length != $actual_length);

   my $quoted_md5 = quotemeta($actual_md5);
   Error (400, "Content-MD5 header does not match actual content MD5 ($data_md5 vs $actual_md5)") 
      if $data_md5 && !($data_md5 =~ /^$quoted_md5/); # $data_md5 may have trailing '=='

   CheckBucketRestrictions ($namespace, $bucket_name, $object_name, $actual_length, $headers, \$data);
   my $metadata      = $headers->{'X-Custom-Metadata'}; # must come after CheckBucketRestrictions due to side effects

   my $sql = "replace into object"                                                                                  .
             " (namespace, name, bucket, owner, value, content_type, content_length, content_md5, custom_metadata)" .
             " values (?,?,?,?,?,?,?,?,?)"                                                                          ;

   delete $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.0"}; # maybe changed the data
   delete $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.1"};
             
             
   return GetDB()->Do ($sql          ,  # 
                       $namespace    ,  # namespace, 
                       $object_name  ,  # name, 
                       $bucket_name  ,  # bucket, 
                       $user->{name} ,  # owner, 
                       $data         ,  # value, 
                       $content_type ,  # content_type, 
                       $actual_length,  # content_length, 
                       $actual_md5   ,  # content_md5, 
                       $metadata     ); # custom_metadata
   }


sub DeleteObject
   {
   my ($namespace, $bucket_name, $object_name) = @_;

   delete $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.0"};
   delete $OBJECT_CACHE->{"$namespace.$bucket_name.$object_name.1"};
   
   my $sql = "delete from object where namespace=? and bucket=? and name =?";
   return GetDB()->Do ($sql, $namespace, $bucket_name, $object_name);
   }


sub CheckObjectName
   {
   my ($object_name) = @_;

   # revamp this
   #
   # $object_name =~ /^[a-zA-Z0-9_\-\.\/\\ ]+$/ or Error (400, "invalid object name: '$object_name'");
   }


sub CheckObjectExists
   {
   my ($namespace, $bucket_name, $object_name, $die_on_error) = @_;

   my $object = GetObject ($namespace, $bucket_name, $object_name, 0);
   my $exists = $object->{name};
   Error (400, "object '$namespace/$bucket_name/$object_name' does not exist") if $die_on_error && !$exists;
   return $exists ? 1 : 0;
   }


# when uploadinn an object to a bucket, the object has to pass the bucket criteria including:
#  max object count
#  max size of bucket contents
#  object may require an x.509 signature
#  object may require an x.509 encryption
#  object may be required to be an x.509 certificate
#
sub CheckBucketRestrictions
   {
   my ($namespace, $bucket_name, $object_name, $content_length, $headers, $data_ref) = @_;

   my $bucket      = GetBucket ($namespace, $bucket_name);
   my $data_needed = $bucket->{signature_cert} || $bucket->{encryption_cert};

   if ($bucket->{max_size} || $bucket->{max_objects})
      {
      my ($count, $total_size) = GetBucketContentInfo ($namespace, $bucket_name);

      my $existing_object = GetObject ($namespace, $bucket_name, $object_name, $data_needed);

      $count--                                           if ($existing_object); # if were replacing the object ...
      $total_size -= $existing_object->{content_length}  if ($existing_object); # if were replacing the object ...

      Error (403, "Bucket already contains max number of objects ($bucket->{max_objects})") 
         if $bucket->{max_objects} && $count >= $bucket->{max_objects};
      Error (403, "Bucket would exceed max size of ($bucket->{max_size})") 
         if $bucket->{max_size} && $total_size + $content_length > $bucket->{max_size};
      }
 
   $headers->{'X-Custom-Metadata'} = _set_meta ("", 'x509_hash', VerifyIsCert ($data_ref)) if ($bucket_name =~ /^cert$/i);
   VerifySignature  ($bucket, $data_ref) if ($bucket->{signature_cert} );
   VerifyEncryption ($bucket, $data_ref) if ($bucket->{encryption_cert});
   }


sub GenerateObjectName
   {
   return NowInFillStringFormat () . sprintf ("%5.5d", rand (32000)) . ".obj";
   }


###############################################################################
#
# cert fns
#
###############################################################################

sub VerifyIsCert 
   {
   my ($data_ref) = @_;

   my $tmp_dir             = SafeGetDir (Setting('tmp') . "/x509/", \&SysError);
   my ($tmp_fh, $tmp_spec) = tempfile('certXXXX', DIR => $tmp_dir, SUFFIX => '.cer', UNLINK => 0);
   binmode $tmp_fh;
   print $tmp_fh ${$data_ref};
   close $tmp_fh;

   my $hash = IsPEMCertificate ($tmp_spec); 
   unlink ($tmp_spec) unless Setting('keep_temp_files');;
   Error (403, "x.509 certificates must be in PEM format") unless $hash;
   return $hash;
   }


sub CreateCertBucket
   {
   my ($namespace) = @_;
   
   return GetDB()->Do ("replace into bucket (namespace, name, policy) values (?, 'cert', '[RWR.R.]')", $namespace);
   return;
   }


sub VerifySignature
   {
   my ($bucket, $data_ref) = @_;

   # dump the object
   my $tmp_dir             = SafeGetDir (Setting('tmp') . "/x509/", \&SysError);
   my ($tmp_fh, $tmp_spec) = tempfile('objectXXXX', DIR => $tmp_dir, SUFFIX => '.dat', UNLINK => 0);
   binmode $tmp_fh;
   print $tmp_fh ${$data_ref};
   close $tmp_fh;

   my $ca_dir = WriteCAFiles ($bucket);                       # make sure we have the CA files
   my $ok = Blue::X509::VerifySignature ($tmp_spec, $ca_dir); # check it

   unlink ($tmp_spec) unless Setting('keep_temp_files');
   Error (403, "Bucket $bucket->{namespace}/$bucket->{name} only accepts signed objects in PEM format") unless $ok;
   return $ok;
   }


# # for now we always re-write the certs. todo: optimize this
# # the $ca dir for this bucket is returned 
# #
# sub WriteCAFiles
#    {
#    my ($bucket) = @_;
# 
#    return "" if !$bucket->{signature_cert};
#    my @cert_names = split (',', $bucket->{signature_cert});
#    @cert_names = map {CleanString ($_)} @cert_names;
#    map {return "" if $_ eq '*'} @cert_names; # just ensure is signed, dont verify against parents
# 
#    my $ca_dir = SafeGetDir (Setting('cache') . "/" . $bucket->{namespace} . "/" . $bucket->{name}, \&SysError);
# 
#    my $sql = "select * from object where namespace=? and bucket='cert' and name=?";
#    foreach my $cert_name (@cert_names)
#       {
#       my $cert = GetDB()->FetchRow ($sql, $bucket->{namespace}, $cert_name);
#       my $cert_hash = _get_meta($cert->{custom_metadata}, 'x509_hash');
#       SpillFile ("$ca_dir/$cert_hash.0", $cert->{value}, 1);
#       }
#    return $ca_dir;
#    }

# for now we always re-write the certs. todo: optimize this
# the $ca dir for this bucket is returned 
#
sub WriteCAFiles
   {
   my ($bucket) = @_;

   return "" if !$bucket->{signature_cert};

   my $csv = Text::CSV_XS->new();
   $csv->parse ($bucket->{signature_cert});
   my @cert_names = $csv->fields();

   map {return "" if $_ eq '*'} @cert_names; # just ensure is signed, dont verify against parents

   my $ca_dir = SafeGetDir (Setting('cache') . "/" . $bucket->{namespace} . "/" . $bucket->{name}, \&SysError);

   my $sql = "select * from object where namespace=? and bucket='cert' and name=?";
   my $db  = GetDB();
   foreach my $cert_name (@cert_names)
      {
      my ($cert, $cert_hash);
      if (IsURL ($cert_name))
         {
         $cert = DownloadCert ($cert_name) or Error (403, "Could not get CERT '$cert_name'");
         $cert_hash = VerifyIsCert (\$cert);
         }
      else
         {
         my $cert_row  = $db->FetchRow ($sql, $bucket->{namespace}, $cert_name) or Error (403, "Could not find CERT '$cert_name'");
         $cert = $cert_row->{value};
         $cert_hash = _get_meta($cert_row->{custom_metadata}, 'x509_hash');
         }  
      SpillFile ("$ca_dir/$cert_hash.0", $cert, 1);
      }
   return $ca_dir;
   }


sub IsURL
   {
   my ($string) = @_;
   
   return ($string =~ /^http/i); # cheating :)
   }


   
sub DownloadCert
   {
   my ($url) = @_;

   my $agent    = LWP::UserAgent->new();
   my $request  = HTTP::Request->new (GET => $url);
   my $user     = GetUser ();
   $request->header ("Authorization" => "Basic " . encode_base64("$user->{name}:$user->{password}"));
   my $response = $agent->request($request);
   
   $response->is_success() ? $response->content() : undef;
   }



sub VerifyEncryption
   {
   my ($bucket, $data_ref) = @_;

   return 1;
   }

