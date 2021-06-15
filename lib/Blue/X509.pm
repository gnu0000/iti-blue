#
# x509.pm
#
# -initially: utils for x.509 fns 
# -eventually openssl wrapper?
#
package Blue::X509;

require Exporter;

use strict;
use warnings;
use Blue::Config   qw(Setting);
use Blue::DebugLog qw(DebugLog GetDebugLog);
use Blue::Util;

our $VERSION   = 1.00;
our @ISA       = qw (Exporter);
our @EXPORT_OK = qw (IsPEMCertificate
                     IsDERCertificate
                     IsX509Certificate 
                     ConvertDERToPEM
                     VerifySignature);


# returns x509 hash if file is an x.509 cert, 0 if not
#
sub IsX509Certificate
   {
   my ($filespec) = @_;

   return IsPEMCertificate ($filespec) || IsDERCertificate ($filespec);
   }


# returns x509 hash if file is an x.509 cert, 0 if not
#
sub IsPEMCertificate
   {
   my ($filespec) = @_;

   my $utilspec = _openssl_spec();
   my $cmd = "\"$utilspec\" x509 -inform PEM -in \"$filespec\" -hash -noout";

   DebugLog (5, "IsPEMCertificate Command: $cmd");

   my ($result, $hash) = BacktickCommand ($cmd);
   chomp $hash;

   DebugLog (5, "IsPEMCertificate hash: '$hash' return code '$result'");

   #return $hash if !$result; --- this sometimes returns an error code of 1 (256) even though it works ---
   return $hash if !$result || length $hash == 8;

   DebugLog (3, "IsPEMCertificate: cmd returned '$?' '$hash'");
   return 0;
   }


sub IsDERCertificate
   {
   my ($filespec) = @_;

   my $utilspec = _openssl_spec();
   my $cmd = "\"$utilspec\" x509 -inform DER -in \"$filespec\" -hash -noout";

   DebugLog (5, "IsDERCertificate Command: $cmd");

   my ($result, $hash) = BacktickCommand ($cmd);
   chomp $hash;

   DebugLog (5, "IsDERCertificate hash: '$hash' return code '$result'");

   #return $hash if !$result; --- this sometimes returns an error code of 1 (256) even though it works ---
   return $hash if !$result || length $hash == 8;

   DebugLog (3, "IsDERCertificate: cmd returned '$?'");
   return 0;
   }


sub ConvertDERToPEM
   {
   my ($der_filespec, $pem_filespec) = @_;

   my $utilspec = _openssl_spec();
   my $nowhere  = NowhereFile ();
   my $cmd      = "\"$utilspec\" x509 -inform DER -in \"$der_filespec\" -outform PEM -out \"$pem_filespec\" > $nowhere";

   DebugLog (5, "ConvertDERToPEM Command: $cmd");

   my $result   = SystemCommand ($cmd);

   DebugLog (3, "ConvertDERToPEM: cmd returned '$result'");
   return $result;
   }


# returns 1 of ok, 0 if an error
#
sub VerifySignature
   {
   my ($filespec, $ca_dir) = @_;

   return _verifySignature ($filespec, $ca_dir, 1) || 
          _verifySignature ($filespec, $ca_dir, 2) ||
          _verifySignature ($filespec, $ca_dir, 0) ;
   }


# returns 1 of ok, 0 if an error
#
# $ca_dir    : path to dir containing parent certs.  if blank,
#              this fn just checks that the file is signed by anybody
#
# $format_id : 0 - compound
#              1 - der
#              2 - pem
#
sub _verifySignature
   {
   my ($filespec, $ca_dir, $format_id) = @_;
   
   my $utilspec = _openssl_spec();
   my $outspec  = $filespec . ".out";
   my $nowhere  = NowhereFile ();
   my $opt      = $ca_dir ? "-CApath \"$ca_dir\"" : "-noverify";
   my $format   = $format_id ==  1 ? "-inform DER" :
                  $format_id ==  2 ? "-inform PEM" :
                                     ""            ;
   my $cmd      = "\"$utilspec\" smime -verify $format $opt -in \"$filespec\" -out $nowhere > \"$outspec\"";

   DebugLog (5, "_verifySignature Command: $cmd");
   my $result   = SystemCommand ($cmd);
   DebugLog (3, "_verifySignature: cmd returned '$result'");
   return !$result;
   }


   
sub _openssl_spec
   {
   # if were in windows, build complete filespec, otherwise assume it's in shell path
   return "openssl" if $^O =~ m/ux|nix|bsd/i;
   
   my $app_spec = Setting('bin') . "/openssl/openssl.exe";
   $app_spec =~ tr[/][\\];
   return $app_spec;
   }


1;