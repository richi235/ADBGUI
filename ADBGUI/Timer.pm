package Timer;

use strict;
use warnings;

use POE;
use Tools qw(simplehashclone);

sub new {
   my $self = {};
   return bless($self);
}

sub stop_timer {
   my $self = shift;
   my $SID = shift;

   Log("TimerLib: stop_timer: TimerTerminate.", $DEBUG);
   return $poe_kernel->call( $SID => "timer_terminate" ) ? 0 : 1;
}

sub time {
   my $self = shift;
   my $SID = shift;
   my $timer = shift;

   return $poe_kernel->call( $SID => "timer_time", $timer ) ? 0 : 1;
}

sub open_timer {
   my $self = shift;
   my $config = shift;
   my $myconfig = simplehashclone($config);
   $myconfig->{self} = $self;
   $myconfig->{parentconfig} = $config;
   Log("TimerLib: open_timer: Your config for SSHPlex::Timer is not complete. ".
       "Starting no timer.", $ERROR) && return undef
   unless ($myconfig && (ref($myconfig) eq "HASH") && ($myconfig->{interval} =~ /^\d+$/) &&
      (ref($myconfig->{onTimer}) eq "CODE"));
   my $session = POE::Session->create(
      inline_states => {
         _start => sub {
            my ( $kernel, $heap, $session, $config ) = @_[ KERNEL, HEAP, SESSION, ARG0 ];
            $heap->{config} = $config;
            $config->{SID} = $session->ID;
            $kernel->yield( "timer_time" );
         },
         _stop => sub {
            Log("TimerLib: _stop: Timer stopped for session ".$config->{SID}, $DEBUG);
         },
         timer_wheel => sub {
            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
            my $config = $heap->{config};
            if (ref($config->{onTimer}) eq "CODE") {
               $config->{onTimer}($config);
            } else {
               Log("TimerLib: timer_wheel: No onTimer-Handler defined: Discarding Timer Event!", $WARNING);
            }
         },
         timer_terminate => sub {
            my $kernel = $_[ KERNEL ];
            Log("TimerLib: timer_terminate: TimerTerminate", $DEBUG);
            $kernel->delay( "timer_wheel" => undef );
         },
         timer_time => sub {
            my ( $kernel, $heap, $interval ) = @_[ KERNEL, HEAP, ARG0 ];
            $config = $heap->{config};
            $config->{interval} = $interval if $interval;
            Log("TimerLib: timer_time: Timing Timer to ".$config->{interval}." Seconds.", $DEBUG);
            $kernel->delay( "timer_wheel" => $config->{interval} );
         }
      },
      args => [ $myconfig ]
   );
   return $session->ID if $session;
   return undef;
}

1;
