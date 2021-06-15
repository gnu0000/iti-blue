#
# Authentication and Authorization fns
#
#
package Blue::Auth;

require Exporter;
use strict;
use warnings;
use Blue::Util;
use Blue::User     qw(GetUser);
use Blue::DebugLog qw(DebugLog);
use Blue::Response qw(Error);
use Blue::Resource qw(GetBucket GetObject);


our $VERSION   = 1.00;
our @ISA       = qw(Exporter);
our @EXPORT    = qw(CheckNamespacePrivilege 
                    CheckBucketPrivilege 
                    CheckObjectPrivilege
                    PolicyCheck
                   );


# $privilege is 'read' | 'write' | 'owner'
# current implementation: 
#   owners/admins have read permission
#   users classified as 'owner's have an assigned namespace that they own and may write to
#
sub CheckNamespacePrivilege
   {
   my ($namespace, $privilege, $die_on_error) = @_;

   my $user = GetUser();
   my $is_read = $privilege =~ /^read$/i;

#   return 1 if $is_read;                              # anyone can read any namespace (subject to bucket constraints) (currently)

   return 1 if $user->{role}      =~ /^admin$/i;      # admin is god
   return 1 if $user->{role}      =~ /^owner$/i   &&  
               $user->{namespace} =~ /^$namespace$/i; # user is explicitlt an owner of this namespace

   Error (403, "User '$user->{name}' does not have privilege to index/create/modify buckets") if $user->{role} =~ /^user|guest$/i;
   Error (403, "User '$user->{name}' does not have privilege to index/create/modify buckets in namespace '$namespace'");
   }


# # $privilege is 'read' | 'write' | 'owner'
# # current implementation: 
# #    read and write permission is derived from the bucket policy 
# #    (which is set via headers when creating the bucket)
# #
# #    for owner, permission,  the actual creator of the bucket is 
# #    not used.   Instead, owners of a namespace are implicitly
# #    owners of all buckets in that namespace
# #
# sub CheckBucketPrivilege
#    {
#    my ($namespace, $bucket_name, $privilege, $die_on_error, $anonymous_ok) = @_;
# 
#    my $user = GetUser($anonymous_ok || 0);
#    return 1 if $user->{role} =~ /^admin$/i;
# 
#    my $user_is_owner = $user->{namespace} =~ /^$namespace$/i ? 1 : 0;
# 
#    if ($privilege =~ /^owner$/i)
#       {
#       return $user_is_owner if !$die_on_error;
#       Error (403, "Insufficient privilege for operation") if !$user_is_owner;
#       return 1;
#       }
#    my $bucket = GetBucket ($namespace, $bucket_name);
# 
#    my $privilege_role = $user->{role};
#    
#    # owners are not considered 'owners' of other peoples workspaces.
#    $privilege_role  = "User" if  ($user->{role} =~ /^Owner$/i) && !$user_is_owner;
# 
#    my $policy = $bucket->{policychange} && $bucket->{policychange} lt NowInDBFormat() ?
#                 $bucket->{policy2} : $bucket->{policy};
# 
#    my $return_code =  PolicyCheck ($policy, $privilege_role, $privilege);
#    Error (403, "Insufficient privilege for operation") if $die_on_error && !$return_code;
#    return $return_code;
#    }
# 
   
# sub CheckBucketPrivilege
#    {
#    my ($namespace, $bucket_name, $privilege, $die_on_error) = @_;
#    
#    return _CheckBucketPrivilege ($namespace, $bucket_name, $privilege, $die_on_error);
#    }
#   
#    
# sub CheckObjectPrivilege
#    {
#    my ($namespace, $bucket_name, $privilege, $die_on_error) = @_;
# 
#    my $anonymous_ok = ($privilege =~ /^read$/i);
#    return _CheckBucketPrivilege ($namespace, $bucket_name, $privilege, $die_on_error, $anonymous_ok);
#    }
   
   
# $privilege is 'read' | 'write' | 'owner'
# current implementation: 
#    read and write permission is derived from the bucket policy 
#    (which is set via headers when creating the bucket)
#
#    for owner, permission,  the actual creator of the bucket is 
#    not used.   Instead, owners of a namespace are implicitly
#    owners of all buckets in that namespace
#
sub CheckBucketPrivilege
   {
   my ($namespace, $bucket_name, $privilege, $die_on_error) = @_;
   
   my $bucket = GetBucket ($namespace, $bucket_name);
   my $user   = GetUser(HasAnonymousAccess ($bucket, $privilege));

   return 1 if $user->{role} =~ /^admin$/i;

   my $user_is_owner = $user->{namespace} =~ /^$namespace$/i ? 1 : 0;

   if ($privilege =~ /^owner$/i)
      {
      return $user_is_owner if !$die_on_error;
      Error (403, "Insufficient privilege for operation") if !$user_is_owner;
      return 1;
      }
   my $privilege_role = $user->{role};
   
   # owners are not considered 'owners' of other peoples workspaces.
   $privilege_role  = "User" if  ($user->{role} =~ /^Owner$/i) && !$user_is_owner;

   my $policy      = BucketPolicy ($bucket);
   my $return_code = PolicyCheck ($policy, $privilege_role, $privilege);
   Error (403, "Insufficient privilege for operation") if $die_on_error && !$return_code;
   return $return_code;
   }


# CheckObjectPrivilege
# $privilege is 'read' | 'write'
#
# if the user is the owner if the object, he implicitly has read permission for the object.
# otherwise, the permission is defined by CheckBucketPrivilege() above
#   
sub CheckObjectPrivilege
   {
   my ($namespace, $bucket_name, $object_name, $privilege, $die_on_error) = @_;
   
   return 1 if IsReadingOwnedObject ($namespace, $bucket_name, $object_name, $privilege);

   return CheckBucketPrivilege ($namespace, $bucket_name, $privilege, $die_on_error);
   }

   
sub IsReadingOwnedObject
   {
   my ($namespace, $bucket_name, $object_name, $privilege) = @_;
   
   return 0 if $privilege !~ /^read$/i;
   
   my $user   = GetUser() or return 0;
   my $object = GetObject ($namespace, $bucket_name, $object_name) or return 0;
   
   return $object->{owner} eq $user->{name};
   }   

   
# PolicyCheck
# check to see if th bucket's policy string contains the requested
# privilege for the current user's type
#
sub PolicyCheck 
   {  # [RW..RW]       "User"           "write"
   my ($policy_string, $privilege_role, $privilege) = @_;

   my $offset = $privilege_role =~ /owner/i ? 1 :
                $privilege_role =~ /user/i  ? 3 :
                                              5 ;
   my $policy_substring = substr ($policy_string, $offset, 2);

   return $policy_substring =~ /R/i if $privilege =~ /^read$/i;
   return $policy_substring =~ /W/i if $privilege =~ /^write$/i;
   return 0;
   }


# does the bucket allow anonymous read access?
#   
sub HasAnonymousAccess 
   {
   my ($bucket, $privilege) = @_;
   
   my $policy = BucketPolicy ($bucket);
   return (substr ($policy, 5, 1) =~ /R/i) if $privilege =~ /read/i;
   return (substr ($policy, 6, 1) =~ /W/i) if $privilege =~ /write/i;
   }
   

# get the bucket's policy
#   
sub BucketPolicy
   {
   my ($bucket) = @_;
   
   return $bucket->{policychange} && $bucket->{policychange} lt NowInDBFormat() ? $bucket->{policy2} : $bucket->{policy};
   }

1;