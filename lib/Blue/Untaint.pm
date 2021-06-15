#
#
package Blue::Untaint;

require Exporter;
use strict;
#use CGI qw(:cgi);

our $VERSION = 1.00;
our @ISA     = qw(Exporter);
our @EXPORT  = qw (
                  param_id        env_id        untaint_id
                  param_text      env_text      untaint_text
                  param_date      env_date      untaint_date
                  param_time      env_time      untaint_time
                  param_number    env_number    untaint_number
                  param_filespec  env_filespec  untaint_filespec
                  param_uri       env_uri       untaint_uri
                  param_any       env_any       untaint_any

                  is_tainted
                  );


## untainting CGI paras
##
#sub param_id         {my ($name) = @_; return untaint_id      (param($name))}
#sub param_text       {my ($name) = @_; return untaint_text    (param($name))}
#sub param_date       {my ($name) = @_; return untaint_date    (param($name))}
#sub param_time       {my ($name) = @_; return untaint_time    (param($name))}
#sub param_number     {my ($name) = @_; return untaint_number  (param($name))}
#sub param_filespec   {my ($name) = @_; return untaint_filespec(param($name))}
#sub param_uri        {my ($name) = @_; return untaint_uri     (param($name))}
#sub param_any        {my ($name) = @_; return untaint_any     (param($name))}

# untainting environment vars
#
sub env_id           {my ($name) = @_; return untaint_id      ($ENV{$name})}
sub env_text         {my ($name) = @_; return untaint_text    ($ENV{$name})}
sub env_date         {my ($name) = @_; return untaint_date    ($ENV{$name})}
sub env_time         {my ($name) = @_; return untaint_time    ($ENV{$name})}
sub env_number       {my ($name) = @_; return untaint_number  ($ENV{$name})}
sub env_filespec     {my ($name) = @_; return untaint_filespec($ENV{$name})}
sub env_uri          {my ($name) = @_; return untaint_uri     ($ENV{$name})}
sub env_any          {my ($name) = @_; return untaint_any     ($ENV{$name})}

# untainting scalars (supports multiple params)
# some of these tr's need refinement. and _uri isn't done
#
sub untaint_id       {_untaint (sub {$_ = shift; tr{[0-9][a-z][A-Z]\-\_\&\.\,\@ }           {}cd; $_}, @_)}
sub untaint_text     {_untaint (sub {$_ = shift; tr{`|}                                     {}d;  $_}, @_)}
sub untaint_date     {_untaint (sub {$_ = shift; tr{[0-9]\/}                                {}cd; $_}, @_)}
sub untaint_time     {_untaint (sub {$_ = shift; tr{[0-9]APMapm:\/ }                        {}cd; $_}, @_)}
sub untaint_number   {_untaint (sub {$_ = shift; tr{[0-9]\-\$\.\, }                         {}cd; $_}, @_)}
sub untaint_filespec {_untaint (sub {$_ = shift; tr{[0-9][a-z][A-Z]\\\/:;\-\_\.\ }          {}cd; $_}, @_)}
sub untaint_uri      {_untaint (undef                                                                , @_)}
sub untaint_any      {_untaint (undef                                                                , @_)}


sub _untaint
   {
   my ($untaintfn, @values) = @_;

   foreach my $index (0 .. $#values)
      {
      my $value = $values[$index];
      next if !defined $value;
      ($value) = $value =~ /^\s*(.*?)\s*$/;                # base untaint, remove surrounding whitespace
      $value = &$untaintfn($value) if defined $untaintfn;  # type specific untaint fn
      $values[$index] = $value;
      }
   return wantarray ? @values : $values[0];
   }


sub is_tainted
   {
   my ($arg) = @_;

   my $nada = substr ($arg, 0, 0);
   local $@;
   eval {eval "# $nada"};
   return length($@) != 0;
   }

1;
