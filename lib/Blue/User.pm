#
# User.pm
#
# GetUser()
#  1> Get the Auth CGI header which includes the user name, password and
#      the authorization type (such as 'Basic' or 'ITILDAP')
#
#  2> Get the metdatata for the authorization type.  This metadata describes
#      how the user will be authenticated
#
#  3> Authenticate the user.  This may be done using LDAP or the local
#      user DB table, or whatever the metadata tells it to do.
#
#
#  the Auth header:
#
#  Authorization: Type userid:password
#
#  Type - This can be anything we define in the blue.conf file, in practice
#         it wil be 'Basic' for authenticating against the local database,
#         and optionally some user defined types for performing ldap based
#         authentication.
#
#  userid:password - typically this data is a base64 string.  The server
#                    allows this in the clear as well.
#
#
#
package Blue::User;

require Exporter;

use strict;
use warnings;
use Authen::Simple::LDAP;
use Digest::MD5    qw(md5 md5_base64);
#use CGI           qw(cookie);
use MIME::Base64;
use Text::CSV_XS;
use Blue::Config   qw(Setting);
use Blue::DB       qw(GetDB);
use Blue::Response qw(Error);
use Blue::DebugLog qw(DebugLog);
use Blue::Untaint;
use Blue::Util     qw(CleanString);
               
our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT    = qw (GetUser);
our @EXPORT_OK = qw (GetCurrentUserName MD5HashPassword SHA1HashPassword);


#constants
my $SALT = "Farfegnugen";

# module globals
my $USER_CACHE = {}; # cached user/auth info
my $CURRENT_USER = undef; # cached user/auth info


##############################################################################
#
# The reason for the module ...
#

sub GetUser
   {
   my ($anonymous_ok) = @_;

   $anonymous_ok = 0 if !defined $anonymous_ok;
   
   my $cache_key = (env_any('HTTP_AUTHORIZATION')            || "") .
                   (env_any('HTTP_X_ELEPHANT_AUTHORIZATION') || "") ;
   if ($cache_key)
      {
      $CURRENT_USER = $USER_CACHE->{$cache_key};
      return $CURRENT_USER if $CURRENT_USER;
      }

   my $user = GetCredentials ($anonymous_ok); # get auth header (or error)
   GetAuthenticationMetadata ($user);         # get config info (or error)
   AuthenticateCredentials   ($user);         # authenticate    (or error)
   
   return $USER_CACHE->{$cache_key} = $CURRENT_USER = $user;
   }

##############################################################################
#
# Gather Authentication Info from a header
#

sub GetCredentials
   {
   my ($anonymous_ok) = @_;
   
   return GetHTTPAuthorizationInfo     () if env_any('HTTP_AUTHORIZATION');
#  return GetCookieAuthorizationInfo   () if do-not-use-cookie('sessionid');           # not done
   return GetElephantAuthorizationInfo () if env_any('HTTP_X_ELEPHANT_AUTHORIZATION'); # depricated
   return GetNullAuthorizationInfo     () if $anonymous_ok;                            # none provided
   
   return Blue::Response::AuthRequiredResponse();
   }

sub GetHTTPAuthorizationInfo
   {
   my $auth_header = $ENV{HTTP_AUTHORIZATION};
   return if !$auth_header;

   my ($auth_type, $data) = $auth_header =~ /^(\w+) (.*)$/;
   my $decoded_data       = decode_base64($data);
   $decoded_data          = $data if (_oc($data) && !_oc($decoded_data));
   my ($userid,$password) = split (':', $decoded_data);

   DebugLog (4, "HTTP_AUTHORIZATION: $auth_header [type=$auth_type,userid=$userid,pwd=$password]");

   return {auth_header => $auth_header ,
           auth_type   => $auth_type   ,
           userid      => $userid      ,
           password    => $password    };
   }


sub _oc {return $_[0] =~ tr/:/:/ == 1}   
   

#deprecated
sub GetElephantAuthorizationInfo
   {
   my $auth_header = env_text('HTTP_X_ELEPHANT_AUTHORIZATION');
   return undef if !$auth_header;

   chomp $auth_header;
   $auth_header =~ s/^(.*[^\r])\r?$/$1/; # carriage return removal... who knows why its here
      
   my ($auth_type, $realm_str) = $auth_header =~ m/^(\w+) (.*)$/i;
   return undef if !$auth_type;

   my $params = {auth_header => $auth_header,
                 auth_type   => $auth_type  };

   foreach my $param (split (',', $realm_str))
      {
      my ($name, $value) = split('=', $param);  
      $value =~ s/[\"\'](.*)[\"\']/$1/i;
      $params->{$name} = $value;   
      }
   return $params;
   }

   
sub GetNullAuthorizationInfo
   {
   return {userid => 'guest'};
   }

   
##############################################################################
#
# Get config info describing how we authenticate with the given header
# 

sub GetAuthenticationMetadata
   {
   my ($user) = @_;

   my $auth_type = $user->{auth_type} or return $user;
   my $cfg_data  = Setting ('Authentication_' . $auth_type);
   
   if (!$cfg_data)
      {
      # Error (401, "Unknown Authentication Type: '$auth_type'");
      DebugLog (2, "Authentication attempted with invalid type: '$auth_type'");
      Blue::Response::AuthRequiredResponse();
      }

   my $csv = Text::CSV_XS->new();
   $csv->parse ($cfg_data);
   my ($auth_class, $auth_host, $auth_dn) = $csv->fields();
   $auth_class = CleanString ($auth_class);
   $auth_host  = CleanString ($auth_host ) || "";
   $auth_dn    = CleanString ($auth_dn   ) || "";

   DebugLog (5, "GetAuthenticationMetadata:  auth_type=$auth_type, auth_class=$auth_class, auth_host=$auth_host, auth_dn=$auth_dn");

   $user->{auth_class} = $auth_class;
   $user->{auth_host } = $auth_host ;
   $user->{auth_dn   } = $auth_dn   ;
   return $user;
   }


##############################################################################
#
# Authenticate
#

sub AuthenticateCredentials
   {
   my ($user) = @_;

   my $auth_class = $user->{auth_class} || 0;

   return DoNullAuthentication  ($user) if $auth_class == 0;
   return DoLocalAuthentication ($user) if $auth_class == 1; 
   return DoLDAPAuthentication  ($user) if $auth_class == 2; 

   # Error (500, "Unknown Authentication Class: '$auth_class'");
   DebugLog (2, "Authentication attempted with invalid class: '$auth_class'");
   Blue::Response::AuthRequiredResponse();
   }

   
# authenticate user against local DB
sub DoLocalAuthentication
   {
   my ($user) = @_;

   my $password = $user->{password};
   my $userid   = $user->{userid};
   my $db_user  = GetDB()->FetchRow ("select * from user where name=?", $userid);
   my $md5_hash_pwd  = MD5HashPassword  ($userid, $password);
   my $sha1_hash_pwd = SHA1HashPassword ($userid, $password);

   # for now, accept unhashed password as an alternate --- for migration support

   my $db_pwd = $db_user ? $db_user->{password} : "";
   my $pwd_ok = $db_pwd eq $md5_hash_pwd  || 
                $db_pwd eq $sha1_hash_pwd || 
                $db_pwd eq $password;
                
   $db_user   = undef if !$pwd_ok;

   if (!$db_user)
      {
      # Error (401, "Bad username and/or password '$userid'")
      DebugLog (2, "Bad username and/or password '$userid'");
      Blue::Response::AuthRequiredResponse();
      }
   ($user->{$_} = $db_user->{$_}) foreach (keys %{$db_user});
   }

   
# authenticate user against ldap service
sub DoLDAPAuthentication 
   {
   my ($user) = @_;

   my $ldap = Authen::Simple::LDAP->new (host => $user->{auth_host}, basedn => $user->{auth_dn});
   my $userid   = $user->{userid};
   
   Error (500, "Unable to Initiate LDAP '$user->{auth_host}' '$user->{auth_dn}'") if !$ldap;
   
   my $success = $ldap->authenticate($userid, $user->{password}); 

   if (!$success)
      {
      # Error (401, "Bad username and/or password '$userid'")
      DebugLog (2, "Bad username and/or password '$userid'");
      Blue::Response::AuthRequiredResponse();
      }
   $user->{role}      = 'user';
   $user->{namespace} = '';
   }


# this is used if no auth header was given  
#
sub DoNullAuthentication 
   {
   my ($user) = @_;
   
   $user->{role}      = $user->{auth_host} && $user->{auth_host} =~ /^(admin)|(owner)|(user)/i ? $user->{auth_host} : "guest";
   $user->{namespace} = '';
   }

##############################################################################
#
# Util
#

sub MD5HashPassword
   {
   my ($name, $password) = @_;

   return md5_base64 ("$name.$SALT.$password");
   }
   
sub SHA1HashPassword
   {
   my ($name, $password) = @_;

   return "Im here";
   }
   

   
# special!
# this is used by error message and logging generators
# it gets the username if available w/o kicking off 'derive user' logic
#
sub GetCurrentUserName
   {
   defined $CURRENT_USER ? $CURRENT_USER->{name} : "unknown";
   }
   
sub Error {Blue::Response::Error(@_)};

1;