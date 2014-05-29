#!/bin/perl

use strict;
use POE qw(Component::Client::LDAP);
use ADBGUI::Tools qw(queryLDAP);

my $password = `cat password.txt`;
chomp $password;        

my $ret = queryLDAP({
   ldapbase   => "OU=TEST-OU,DC=adtest,DC=local",
   ldapfilter => '(&(objectClass=person)(memberof=CN=sayTRUST01,OU=TEST-OU,DC=adtest,DC=local))',
   host       => 'localhost',
   username   => 'ldapbind',
   password   => $password,
   timeout    => 5, # Sekunden
   callback   => sub {
      my $config = shift;
      my $data   = shift;
      my $error  = shift;
      my $heap   = shift;
      return print "ERROR:".$error.":\n"
         if ($error || (!defined($data)));
      print "done: ".($data ? "".(join("\n\n----------\n\n", map {
         my $curattr = $_;
         join("\n", map {
            $_."=".join("#", @{$curattr->get_value( $_, asref => 1 )});
         } $curattr->attributes())
      } @$data))." " : "").
      "\n\n".($error ? "error: ".$error : "ok")."\n\n=========\n\n";
   },
});

print "RET:".($ret || "UNDEF").":\n";

$poe_kernel->run();
