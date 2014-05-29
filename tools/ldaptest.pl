#!/bin/perl

use strict;
use POE qw(Component::Client::LDAP);

my $password = `cat password.txt`;
chomp $password;        

my $ret = queryLDAP({
   ldapbase   => "OU=TEST-OU,DC=adtest,DC=local",
   ldapfilter => '(&(objectClass=person)(memberof=CN=sayTRUST01,OU=TEST-OU,DC=adtest,DC=local))',
   host       => '1.2.3.4', # 'localhost',
   username   => 'ldapbind',
   password   => $password,
   timeout    => 5, # Sekunden
   callback   => sub {
      my $config = shift;
      my $data = shift;
      my $error = shift;
      my $heap = shift;
      if ($error || (!defined($data))) {
         print "ERROR:".$error.":\n";
         return;
      }
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

sub queryLDAP {
   my $config = shift;
   return undef
      unless (
         $config->{host} &&
         $config->{callback} &&
         $config->{ldapbase} && 
 defined($config->{ldapfilter}) &&
         $config->{username} &&
         $config->{password});
   POE::Session->create(
      inline_states => {
         _start => sub {
            my ($heap, $session, $config) = @_[HEAP, SESSION, ARG0, ARG1, ARG2];
            $heap->{config} = $config;
            $heap->{config}->{timeout} ||= 10;
            $poe_kernel->delay("timeout" => $heap->{config}->{timeout});
            $heap->{ldap} = POE::Component::Client::LDAP->new(
               $heap->{config}->{host},
               callback => $session->postback('connect'),
            );
         },
         connect => sub {
            my ($heap, $session, $callback_args) = @_[HEAP, SESSION, ARG1];
            $poe_kernel->delay("timeout" => $heap->{config}->{timeout});
            if ( $callback_args->[0] ) {
               $heap->{ldap}->bind(
                  $heap->{config}->{username},
                  password => $heap->{config}->{password},
                  callback => $session->postback('bind'),
               );
            } else {
               delete $heap->{ldap};
               $poe_kernel->delay("timeout" => undef);
               $poe_kernel->post($heap->{config}->{dstsession} || $session => $heap->{config}->{dstevent} || "done" => undef => "connection failed");
            }
         },
         bind => sub {
            my ($heap, $session, $arg1, $arg2, $arg3, $arg4) = @_[HEAP, SESSION, ARG0, ARG1, ARG2, ARG3];
            $poe_kernel->delay("timeout" => $heap->{config}->{timeout});
            $heap->{ldap}->search(
               base => $heap->{config}->{ldapbase},
               filter => $heap->{config}->{ldapfilter},
               callback => $session->postback('search'),
            );
         },
         search => sub {
            my ($heap, $session, $ldap_return) = @_[HEAP, SESSION, ARG1];
            my $ldap_search = shift @$ldap_return;
            $poe_kernel->post($heap->{config}->{dstsession} || $session => $heap->{config}->{dstevent} || "done" => [$ldap_search->entries] => ($ldap_search->code ? ($ldap_search->error || "unknown") : undef));
            #if ($ldap_search->done) {
               delete $heap->{ldap} ;
               $poe_kernel->delay("timeout" => undef);
            #}
         },
         timeout => sub {
            my ($heap, $session) = @_[HEAP, SESSION];
            delete $heap->{ldap};
            $poe_kernel->post($heap->{config}->{dstsession} || $session => $heap->{config}->{dstevent} || "done" => undef => "timeout");
         },
         done => sub {
            my ($heap, $data, $error) = @_[HEAP, ARG0, ARG1];
            #print "done: ".($data ? "".(join("\n\n----------\n\n", map { my $curattr = $_; join("\n", map { $_."=".join("#", @{$curattr->get_value ( $_, asref => 1 )}); } $curattr->attributes()) }  @$data)  )." " : "")."\n\n    ".($error ? "error: ".$error : "ok")."\n\n=========\n\n";
            $config->{callback}($heap->{config}, $data, $error, $heap);
         },
      },
      args => [$config],
   );
}

$poe_kernel->run();
