#
# DB.pm
# simple database access
#
#
package Blue::DB;

require Exporter;

use strict;
use DBI;
use Blue::Config   qw(Setting);
use Blue::DebugLog qw(DebugLog);

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (GetDB);


# internal global
#
my $DB           = undef;
my $DIE_ON_ERROR = 1;

# the only exported fn
#
sub GetDB
   {
   return $DB if ($DB);
   $DB = Blue::DB->Connect ();
   return $DB;
   }


sub Connect
   {
   my ($class) = @_;

   my $dbinfo   = Setting('db'    );
   my $username = Setting('dbusername');
   my $password = Setting('dbpassword');

   my $dbh = DBI->connect ($dbinfo, $username, $password);

   DBLog (1, "Could not connect to database \"$dbinfo\" (" . $DBI::errstr . ").", 1) if !$dbh;

   my $self = {dbh      => $dbh     ,
               dbinfo   => $dbinfo  ,
               username => $username};

   return bless ($self, $class);
   }

sub Prepare
   {
   my ($db, $statement) = @_;

   return $db->{dbh}->prepare($statement);
   }


sub Quote
   {
   my ($db, $string) = @_;

   return $db->{dbh}->quote ($string);
   }


# returns an array of hashrefs
# hash keys are the db column names, for oracle databases, they are in uppercase
#
sub FetchRows
   {
   my ($db, $statement, @bind_params) = @_;

   DBLog (4, "FetchRows: $statement");
   my $sth = $db->Prepare($statement);
   $sth->execute (@bind_params);
   return DBLog (1, "could not execute query '$statement'") if $sth->errstr;

   my @results = ();
   while (my $hash = $sth->fetchrow_hashref ())
      {
      push @results, $hash;
      }
   $sth->finish();
   return @results;
   }

# return single row query result as a list is scalars
# internal, used by AUTOLOADer
# if used externally, leave $stack_level_hint undefined
#
sub FetchList
   {
   my ($db, $statement, @bind_params) = @_;

   DBLog (4, "FetchList: $statement");

   my $sth = $db->Prepare($statement);
   $sth->execute (@bind_params);
   my @row = $sth->fetchrow_array ();

   return DBLog (1, "could not execute query '$statement'") if $db->{dbh}->errstr;
   my $columns = scalar @row;

   return undef if !$columns;
   return @row;
   }

# returns a single row as a hashref
# hash keys are the db column names, for oracle databases, they are in uppercase
#
sub FetchRow
   {
   my ($db, $statement, @bind_params) = @_;

   DBLog (4, "FetchRow: $statement");

#  my $hash = $db->{dbh}->selectrow_hashref ($statement);
   my $sth = $db->Prepare($statement);
   $sth->execute (@bind_params);
   my $hash = $sth->fetchrow_hashref ();

   return DBLog  (1, "could not execute statement '$statement'")if $db->{dbh}->errstr;
   return undef if !$hash || !scalar (keys %{$hash});
   return $hash;
   }

sub FetchColumn
   {
   my ($db, $statement, @bind_params) = @_;

   DBLog (4, "FetchColumn: $statement");
   my @row = $db->FetchList ($statement, @bind_params);
   return $row[0];
   }


# executa a statement that does not result in return data
# returns 0 if there is an Error
#
sub Do
   {
   my ($db, $statement, @bind_params) = @_;

   DBLog (4, "Do: $statement");
#   $db->{dbh}->do ();
#   my $ret = $db->{dbh}->do ($statement, undef, @bind_params);
   my $sth = $db->Prepare($statement);
   $sth->execute (@bind_params);

   DBLog (1, "Do Error: " . $db->{dbh}->errstr) if $db->{dbh}->errstr;
   return ($db->{dbh}->errstr ? 0 : 1);
   }


# sql logs are killing me
#
# only errors and warnings are logged unless config entry
# dblog is set to 1
#
sub DBLog
   {
   my ($log_level) = @_;
   DebugLog (@_) if $log_level < 3 || Setting ('dblog');
   
   #die if $log_level ==1 && $DIE_ON_ERROR;
   }

######################################################################################

#fini
1;
