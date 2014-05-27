#!/bin/perl

use strict;
use POE qw(Component::Client::LDAP);

my $host = 'localhost';
my $username = 'ldapbind';
my $password = `cat password.txt`;
chomp $password;        
my $timeout = 10;
my $session = undef;
my $event = undef;
my $base = "OU=TEST-OU,DC=adtest,DC=local";
my $filter = '(&(objectClass=person)(memberof=CN=sayTRUST01,OU=TEST-OU,DC=adtest,DC=local))';

POE::Session->create(
   inline_states => {
      _start => sub {
         my ($heap, $session, $dstsession, $dstevent) = @_[HEAP, SESSION, ARG0, ARG1];
         $heap->{dstsession} = $dstsession;
         $heap->{dstevent} = $dstevent;
         $poe_kernel->delay("timeout" => $timeout);
         $heap->{ldap} = POE::Component::Client::LDAP->new(
            $host,
            callback => $session->postback('connect'),
         );
      },
      connect => sub {
         my ($heap, $session, $callback_args) = @_[HEAP, SESSION, ARG1];
         $poe_kernel->delay("timeout" => $timeout);
         if ( $callback_args->[0] ) {
            $heap->{ldap}->bind(
               $username,
               password => $password,
               callback => $session->postback('bind'),
            );
         } else {
            delete $heap->{ldap};
            $poe_kernel->delay("timeout" => undef);
            $poe_kernel->post($heap->{dstsession} || $session => $heap->{dstevent} || "done" => undef => "connection failed");
         }
      },
      bind => sub {
         my ($heap, $session, $arg1, $arg2, $arg3, $arg4) = @_[HEAP, SESSION, ARG0, ARG1, ARG2, ARG3];
         $poe_kernel->delay("timeout" => $timeout);
         $heap->{ldap}->search(
            base => $base,
            filter => $filter,
            callback => $session->postback('search'),
         );
      },
      search => sub {
         my ($heap, $session, $ldap_return) = @_[HEAP, SESSION, ARG1];
         my $ldap_search = shift @$ldap_return;
         $poe_kernel->post($heap->{dstsession} || $session => $heap->{dstevent} || "done" => [$ldap_search->entries] => ($ldap_search->code ? ($ldap_search->error || "unknown") : undef));
         #if ($ldap_search->done) {
            delete $heap->{ldap} ;
            $poe_kernel->delay("timeout" => undef);
         #}
      },
      timeout => sub {
         my ($heap, $session) = @_[HEAP, SESSION];
         delete $heap->{ldap};
         $poe_kernel->post($heap->{dstsession} || $session => $heap->{dstevent} || "done" => undef => "timeout");
      },
      done => sub {
         my ($heap, $data, $error) = @_[HEAP, ARG0, ARG1];
         print "done: ".($data ? "".(join("\n\n----------\n\n", map { my $curattr = $_; join("\n", map { $_."=".join("#", @{$curattr->get_value ( $_, asref => 1 )}); } $curattr->attributes()) }  @$data)  )." " : "")."\n\n    ".($error ? "error: ".$error : "ok")."\n\n=========\n\n";
      },
   },
   args => [$session => $event]
);

$poe_kernel->run();
