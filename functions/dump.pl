#!perl
##
##  printenv -- demo CGI program which just prints its environment
##

MAIN:
   my $fh;
   
   open ($fh, ">>", "c:/bidx/blue/functions/dump.dat") or die "cannot append to dump.dat";
   print $fh "-[DUMP START]--------------------------------------------\n";
   my $indata = LoadStdin();
   print $fh $indata;
   print $fh "\n-------------------------------------------------------\n";
   
   foreach $var (sort(keys(%ENV))) 
      {
      $val = $ENV{$var};
      $val =~ s|\n|\\n|g;
      $val =~ s|"|\\"|g;
      print $fh "${var}=\"${val}\"\n";
      }
   print $fh "\n-[DUMP END]--------------------------------------------\n";
   close ($fh);
     
   print "Content-type: text/plain; charset=iso-8859-1\n\n";
   exit (0);      


sub LoadStdin
   {
   local $/ = undef;
   binmode STDIN;
   my $data = <STDIN>;
   return $data;
   }

