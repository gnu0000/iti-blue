#!/Perl/bin/perl
#

use lib '../lib';
use strict;
use warnings;
use CGI             qw(param cookie);
use CGI::Carp       qw(fatalsToBrowser);
use Digest::MD5     qw(md5 md5_base64);
use Blue::DB        qw(GetDB);
use Blue::Response  qw(Error Response_html Reloc);
use Blue::Template  qw(Template TemplateList);
use Blue::User      qw(MD5HashPassword);

#constants
my $SALT = "Farfegnugen";

##############################################################################

MAIN:
   my $command   = param ('command');
   my $sessionid = cookie('sessionid');

   ValidateSession ();

   SaveUser ()           if $command =~ /Save/i;
   Reloc ('/admin/user') if $command =~ /Cancel/i;
   DeleteUser ()         if $command =~ /Delete/i;
   EditForm ()           if $command =~ /Edit/i;
   Index ();
   

##############################################################################
#
#

sub Index
   {
   my @users = GetDB()->FetchRows ("select * from user");

   Response_html  (200,
                   Template ('admin_start', title=>'Users') .
                   TemplateList ('admin_users', \@users   ) .
                   Template ('admin_end'                  ) );
   exit (0);
   }

sub EditForm  
   {          
   my $name  = param ('name');
   my $user  = GetDB()->FetchRow ("select * from user where name='$name'");
   my $title = $user ? "Edit User" : "Add User";
   
   $user  ||= {name=>$name, role=>'', namespace=>'', password=>''}; # in case it's an add
   map {$user->{"select_".$_} = $user->{role} =~ /^$_/i ? "selected" : ""} qw(user owner admin);

   $user->{select_0} = $user->{role} =~ /^user$/i;
   $user->{select_1} = $user->{role} =~ /^owner$/i;
   $user->{select_2} = $user->{role} =~ /^admin$/i;

   Response_html  (200, Template ('admin_start', title=>$title) .
                        Template ('admin_edituser', %{$user}  ) .
                        Template ('admin_end'                 ) );
   exit (0);
   }


sub SaveUser  
   {
   my ($name, $role, $namespace, $password) = (param('name'), param('role'),  param('namespace'), param('password'));

   my $user = GetDB()->FetchRow ("select * from user where name='$name'");

   my $password_changed = !$user || ($user->{password} ne $password);

   # if password is new or has changed, get user entry and encode it   
   $password = MD5HashPassword ($name, $password) if (!$user || ($user->{password} ne $password));

   my $sql = "replace into user (name, role, namespace, password) values (?, ?, ?, ?)";
   GetDB()->Do ($sql, $name, $role, $namespace, $password);
   Reloc ('/admin/user');
   }


sub DeleteUser
   {
   GetDB()->Do ("delete from user where name=?", param('name'));
   Reloc ('/admin/user');
   }


sub ValidateSession
   {
# todo   
   }
