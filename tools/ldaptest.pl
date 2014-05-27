#!/bin/perl

use POE qw(Component::Client::LDAP);

POE::Session->create(
   inline_states => {
      _start => sub {
         my ($heap, $session) = @_[HEAP, SESSION];
         $heap->{ldap} = POE::Component::Client::LDAP->new(
            'localhost',
            callback => $session->postback( 'connect' ),
         );
         print "connecting\n";
      },
      connect => sub {
         my ($heap, $session, $callback_args) = @_[HEAP, SESSION, ARG1];
         if ( $callback_args->[0] ) {
            print "connected\n";
            $heap->{ldap}->bind(
               'ldapbind',
               password => 'sayFUSE05',
               callback => $session->postback( 'bind' ),
            );
         } else {
            delete $heap->{ldap};
            print "Connection Failed\n";
         }
      },
      bind => sub {
         my ($heap, $session, $arg1, $arg2, $arg3, $arg4) = @_[HEAP, SESSION, ARG0, ARG1, ARG2, ARG3];
         print "searching:".$heap->{ldap}.":".$arg1.":".$arg2.":".$arg3.":".$arg4.";\n";
         $heap->{ldap}->search(
            base => "OU=TEST-OU,DC=adtest,DC=local",
            filter => "(objectClass=person)",
            callback => $session->postback( 'search' ),
         );
      },
      search => sub {
         my ($heap, $ldap_return) = @_[HEAP, ARG1];
         my $ldap_search = shift @$ldap_return;
         print "results:".$ldap_search.":".$ldap_search->code.":\n";
         $ldap_search->code && die $ldap_search->error;
         foreach (@$ldap_return) {
            print $_->dump;
         }
         delete $heap->{ldap} if $ldap_search->done;
      },
   },
);

$poe_kernel->run();
