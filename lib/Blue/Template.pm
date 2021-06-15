#
# Template.pm
# This module contains simple text templates and a function to interpolate
# the variables in the templates.  This is used by response.pm
#
package Blue::Template;

require Exporter;

use strict;
our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (Template TemplateList);
                     
                     
###############################################################################
#
# template processing
#

my $TEMPLATES = undef; # template cache

sub ReadTemplates
   {
   my $Key;
   map {($_ =~ /^#(\S+)/) ? ($Key = $1) : ($TEMPLATES->{$Key} .= $_);} (<DATA>);
   }


# returns the contents of a nemed template
# the variables in the template are replaced with the variables contents
#
sub Template
   {
   my ($templateName, %templateParams) = @_;
   ReadTemplates () unless defined $TEMPLATES;
   my $templateData = $TEMPLATES->{$templateName};
   $templateData =~ s{\$(\w+)}{exists $templateParams{$1} ? $templateParams{$1} : "\$$1"}gei;
   return $templateData;
   }

# call a sequence of templates on a list of data.
# Call sequence:
#  templateBaseName_start
#  templateBaseName_row (1 call per row in @{$List}
#  templateBaseName_end
#
sub TemplateList
   {
   my ($templateBaseName, $List, %ExtraParams) = @_;
   my $response = Template ($templateBaseName . '_start', %ExtraParams);
   map {$response .= Template ($templateBaseName . '_' . ($_->{_template} || 'row'), %{$_}, %ExtraParams)} @{$List};
   $response .= Template ($templateBaseName . '_end', %ExtraParams);
   return $response;
   }

1;                     
                     
__DATA__
#user_info
   <user>
      <userid>$userid</userid>
      <role>$role</role>
      <namespace>$namespace</namespace>
   </user>
#namespace_index_start
   <namespaces>
#namespace_index_row
      <namespace>
         <name>$namespace</name>
         <bucket_count>$bucket_count</bucket_count>
         <link>$location</link>
         <user_role>$user_role</user_role>
      </namespace>
#namespace_index_end
   </namespaces>
#bucket_index_start
   <buckets>
      <namespace>$namespace</namespace>
#bucket_index_row
      <bucket>
         <name>$name</name>
         <policy>$policy_alias</policy>
         <custom_metadata>$custom_metadata</custom_metadata>
         <link>$location$name</link>
         <updated>$updated</updated>
      </bucket>
#bucket_index_end
   </buckets>
#bucket_info_start
   <bucket>
      <namespace>$namespace</namespace>
      <name>$name</name>
      <creator>$owner</creator>
      <policy>$policy_alias</policy>
      <total_size>$_total_size</total_size>
      <object_count>$_object_count</object_count>
      <max_size>$max_size</max_size>
      <max_objects>$max_objects</max_objects>
      <signature_cert>$signature_cert</signature_cert>
      <encryption_cert>$encryption_cert</encryption_cert>
      <custom_metadata>$custom_metadata</custom_metadata>
      <updated>$updated</updated>
#object_index_start
      <objects type="array">
#object_index_row
         <object>
            <namespace>$namespace</namespace>
            <bucket>$bucket</bucket>
            <name>$name</name>
            <creator>$owner</creator>
            <content_type>$content_type</content_type>
            <content_length>$content_length</content_length>
            <content_md5>$content_md5</content_md5>
            <custom_metadata>$custom_metadata</custom_metadata>
            <link>$location</link>
            <path>$path</path>
            <updated>$updated</updated>
         </object>
#object_index_end
      </objects>
#full_object_index_start
      <objects type="array">
#full_object_index_row
         <object>
            <namespace>$namespace</namespace>
            <bucket>$bucket</bucket>
            <name>$name</name>
            <creator>$owner</creator>
            <content_type>$content_type</content_type>
            <content_length>$content_length</content_length>
            <content_md5>$content_md5</content_md5>
            <custom_metadata>$custom_metadata</custom_metadata>
            <link>$location</link>
            <path>$path</path>
            <updated>$updated</updated>
            <content>
               $value
            </content>
         </object>
#full_object_index_end
      </objects>
#bucket_info_end
   </bucket>
#error
  <error>
    <status>$status</status>
    <message>$message</message>
  </error>
#log_message
   <log_message>
      $log_message
   </log_message>
#admin_start
   <html>   
      <head>
         <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
         <link rel="stylesheet" href="/css/main.css" type="text/css" media="screen" />
         <title>$title</title>
      </head>
      <body>
         <h1>$title</h1>
#admin_end
      </body>
   </html>   
#admin_users_start
         <table class="block_table">
            <tr class="head">
               <td>Name     </td>
               <td>Role     </td>
               <td>Namespace</td>
               <td style="width: 4em">Delete   </td>
            </tr>
#admin_users_row
            <tr>
               <td><a href="/admin/user?command=edit&name=$name">$name</a></td>   
               <td>$role</td>   
               <td>$namespace</td>   
               <td class="c"><a class="minilinkbutton" href="/delete">x</a></td>   
            </tr>
#admin_users_end
         </table>
         <p>
         <a class="minilinkbutton" href="/admin/user?command=edit">Add User</a>
         </p>
#admin_edituser
      <form method="POST" action="/admin/user">
         <table class="input_table">
            <tr>
               <td class="l">Name:     </td>
               <td><input type="text" name="name"      value="$name"      /></td>
            </tr>
            <tr>
               <td class="l">Role:     </td>
               <td><select name="role" style="width: 11em">
                     <option value="user"  $select_user >User </option>  
                     <option value="owner" $select_owner>Owner</option>  
                     <option value="admin" $select_admin>Admin</option>  
                   </select>
               </td>
            </tr>
            <tr>
               <td class="l">Namespace:</td>
               <td><input type="text" name="namespace" value="$namespace" /></td>
            </tr>
            <tr>
               <td class="l">Password: </td>
               <td><input type="password" name="namespace" value="$password"  /></td>
            </tr>
         </table>
         <br />
         <input type="submit" name="command" value="Save" />
         <input type="submit" name="command" value="Cancel" />
      </form>
   <html>
#fini


