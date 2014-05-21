#!/usr/bin/perl -w
package ADBGUI::TelnetServer;

use strict;
use warnings;

use POE qw(Wheel::ReadWrite Wheel::SocketFactory Filter::Stream);
use POSIX qw(errno_h setsid);
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT simplehashclone Log);

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $config = shift;
   my $self = {};
   $self->{server} = POE::Session->create(
      inline_states => {
         _start => sub {
            my ($heap, $self, $config) = @_[HEAP, ARG0, ARG1];
            $heap->{config} = $config;
            $heap->{self} = $self;
            Log("TelnetServer: Listening on ".$heap->{config}->{listenip}.":".$heap->{config}->{listenport}.":", $INFO);
            $heap->{server_wheel} = POE::Wheel::SocketFactory->new(
               BindAddress  => $heap->{config}->{listenip},
               BindPort     => $heap->{config}->{listenport},
               Reuse        => 'yes',
               SuccessEvent => 'telnetserver_accept_success',
               FailureEvent => 'telnetserver_accept_failure',
            );
         },
         _stop  => sub {
            my $heap = $_[HEAP];
            Log("TelnetServer: stopped", $INFO);
         },
         telnetserver_accept_success => sub {
            my ($heap, $socket, $clientip, $clientport) = @_[HEAP, ARG0, ARG1, ARG2];
            $heap->{self}->{connectedcount}++;
            # Wenn in der Config steht, dass wir nur ein Child haben wollen,
            # dann versuchen wir die laufenden zu beenden, bevor wir eine
            # neue Child-Session erzeugen.
            if ((!$heap->{config}->{MultipleConnections}) && defined($heap->{self}->{connections}) && scalar(@{$heap->{self}->{connections}})) {
               Log("TelnetServer: There is already one or more client Session(s) opened. Terminating them before creating a new session.", $WARNING);
               grep { $_->terminate() } @{$heap->{self}->{connections}};
            }
            my $connection = ADBGUI::TelnetServerConnection->new($socket, $heap->{self},
               { readtimeout     => $heap->{config}->{readtimeout},
                 readlinetimeout => $heap->{config}->{readlinetimeout}},
                 $clientip, $clientport);
         },
         telnetserver_accept_failure => sub {
            my ( $heap, $operation, $errnum, $errstr ) = @_[ HEAP, ARG0, ARG1, ARG2 ];
            Log("TelnetServer: accept: ".$operation." error ".$errnum.": ".$errstr, $ERROR );
            # TODO/FIXME/...: Da gibts noch mehr und bessere Abbruchbedingungen!
            delete $heap->{server_wheel} if ($errnum == ENFILE) or ($errnum == EMFILE);
         },
      },
      args => [ $self, $config ]
   );
   return ($self->{server} ? bless($self, $class) : undef);
}

sub RegisterConnection {
   my $self = shift;
   my $connection = shift;

   push(@{$self->{connections}}, $connection);
}

sub UnRegisterConnection {
   my $self = shift;
   my $connection = shift;
   my $before = scalar(@{$self->{connections}});
   @{$self->{connections}} = grep { $connection != $_ } @{$self->{connections}};
   unless ($before != (scalar(@{$self->{connections}})-1)) {
      Log("Before was :".$before.": and now it is :".scalar(@{$self->{connections}}).":", $ERROR);
   }
}

sub LineHandler {
   my $self = shift;
   $_ = shift;
   my $client = shift;
   my $onConnect = shift;
   
   Log("TelnetServer: input: No LineHandler defined! Disconnecting.", $ERROR);
   
   $client->terminate();
}

package ADBGUI::TelnetServerConnection;

use POE;
use Socket;   # Wird nur fuer "inet_ntoa" gebraucht
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT simplehashclone Log);

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $self = {};
   my $socket = shift;
   bless($self);
   $self->{trackingdata} = {};
   $self->{parent} = shift;
   $self->{config} = shift;
   $self->{clientip_packed} = shift;
   $self->{clientip}        = inet_ntoa($self->{clientip_packed});
   $self->{clientport}      = shift;
   $self->{client} = POE::Session->create(
      inline_states => {
         _start                  => sub {
            my ($heap, $kernel, $self, $socket, $config) = @_[HEAP, KERNEL, ARG0, ARG1, ARG2];
            $heap->{self} = $self;
            $heap->{config} = $config;
            $heap->{queue} = '';
            $heap->{self}->{parent}->RegisterConnection($heap->{self});
            $_[KERNEL]->delay( "timeout" => $heap->{config}->{readtimeout}) if ($heap->{config}->{readtimeout});
            Log("TelnetServerConnection: Accepted connection from ".$heap->{self}->{clientip}.":".$heap->{self}->{clientport}, $INFO);
            $heap->{wheel_client} = POE::Wheel::ReadWrite->new(
               Handle => $socket,
               Driver     => POE::Driver::SysRW->new,
               Filter     => POE::Filter::Stream->new,
               InputEvent => 'input',
               FlushedEvent => 'flushed',
               ErrorEvent => 'error',
            );
            $heap->{self}->{parent}->LineHandler(undef, $heap->{self}, 1);
         },
         _stop => sub {
            my ( $heap, $session ) = @_[ HEAP, SESSION ];
            Log("TelnetServerConnection: stop: Closing Session.", $INFO);
            $heap->{self}->{parent}->UnRegisterConnection($heap->{self});
         },
         flushed   => sub {
            my ( $kernel, $heap ) = @_[KERNEL, HEAP];
            if ($heap->{terminate}) {
               $kernel->yield("terminate");
            }
         },
         close     => sub {
            my ( $kernel, $heap ) = @_[KERNEL, HEAP];
            $heap->{terminate}++;
         },
         input     => sub {
            my ($kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];
            $heap->{self}->{incoming} += length($input);
            if ($heap->{terminate}) {
               $kernel->yield("terminate");
               return;
            }
            $heap->{queue} .= $input;
            while (scalar(my @lines = split(/\r?\n/, $heap->{queue}, 2))>1) {
               my $curline = $lines[0];
               $heap->{queue} = $lines[1];
               #if ($heap->{config}->{LineHandler}) {
               $heap->{self}->{parent}->LineHandler($curline, $heap->{self}, 0);
               #} else {
               #   Log("TelnetServerConnection: input: No Line-Handler defined: ".
               #        "Discarding incoming data! Socket is ".$heap->{config}->{listenip}.":".
               #        $heap->{config}->{listenport}, $WARNING);
               #}
            }
            my $timeout = 0;
            $timeout = $heap->{config}->{readlinetimeout} || 0 if (length($heap->{queue}) > 0);
            $timeout = $heap->{config}->{readtimeout} if (defined($heap->{config}->{readtimeout})
                && ($heap->{config}->{readtimeout}) && (($timeout > $heap->{config}->{readtimeout})
                || !$timeout));
            Log("TelnetServerConnection: input: Setting timeout to ".
               $heap->{config}->{readlinetimeout}.":".$heap->{config}->{readtimeout}.
               ":".$timeout, $DEBUG);
            $kernel->delay( "timeout" => $timeout) if ($timeout);
         },
         error     => sub {
            my ( $kernel, $heap, $operation, $errnum, $errstr ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
            my $config = $heap->{config};
            Log("TelnetServerConnection: ".$operation." error ".$errnum.": ".$errstr, $WARNING) if (    $errnum);
            Log("TelnetServerConnection: Client closed connection.", $INFO)                     if (not $errnum);
            $kernel->yield("terminate");
         },
         shutdown => sub {
            $_[KERNEL]->yield("terminate");
         },
         timeout   => sub {
            my ( $heap, $kernel ) = @_[HEAP, KERNEL];
            Log("TelnetServerConnection: timeout: Timeout for client.", $INFO);
            $kernel->yield("terminate");
         },
         terminate => sub {
            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            Log("TelnetServerConnection: DISCONNECTING.", $DEBUG);
            delete $heap->{wheel_client};
            $kernel->delay( "timeout" => undef );
            # Grundsaetzliches aufraeumen, damit die Session auch wirklich
            # sofort stirbt.
            #
            # clear all alarms you might have set
            #$kernel->alarm_remove_all();
         },
         send_message => sub {
            my ( $kernel, $heap, $line ) = @_[KERNEL, HEAP, ARG0];
            $kernel->yield(send => $line);
         },
         send => sub {
            my ( $heap, $line ) = @_[HEAP, ARG0];
            $heap->{self}->{outgoing} += length($line);
            # TODO/FIXME/XXX/...: Das können wir besser!
            exists( $heap->{wheel_client} ) and $heap->{wheel_client}->put($line);
         }
      },
      args => [$self, $socket, $self->{config}]
   );
   return $self;
}

sub send {
   my $self = shift;
   my $line = shift;

   #syswrite(STDOUT, "RUNNING WITH :".$SID.":".$line.":\n");
   # Das hier muss call statt post sein, da ansonsten im
   # destructor handler von SSHPlex (das ist ein _stop-Handler)
   # keine Nachrichten mehr versendet werden koennen.
   return $poe_kernel->call($self->{client}, "send", $line) ? 0 : 1;
}

sub close {
   my $self = shift;
   return $poe_kernel->call($self->{client} => "close") ? 0 : 1;
}

sub terminate {
   my $self = shift;
   return $poe_kernel->call($self->{client} => "terminate") ? 0 : 1;
}

sub getTrackingHash {
   my $self = shift;
   return $self->{trackingdata};
}

1;