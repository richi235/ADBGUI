package ADBGUI::Qooxdoo;

=pod

=head1 NAME

  ADBGUI::Qooxdoo  -- The Frontend Component of the ADBGUI Framework.

  Talks to javascript components of the Qooxdoo Web Framework running in the Browser of the Client.

=head1 SYNOPSIS

  Not needed, since it gets only called by other Framework Components

=head1 DESCRIPTION

  Subroutines in here get called on Events coming from the client and call subroutines from DBManager.pm
  The events for example include:

=over

=over

=item * I<onAuthenticate> The User opens the website or is pressing the login button.

=item * I<onAuthenticated> The user logged in succesfully. Used for default window etc.

=item * I<onShow> Draw the window for a table.

=item * I<And much more...>


=back

=back

  
=head1 METHODS

=cut



use warnings;
use strict;
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(Log getAffectedColumns hashKeysRightOrder htmlUnEscape $loglevel hidebegin hideend);
use POE qw(Component::Server::TCP Filter::HTTPD Wheel::Run);
use ADBGUI::DBDesign qw($AJAXDISCONNECTED $AJAXFLUSHED $AJAXSTART);
use HTTP::Response;
use HTTP::Status;
use CGI;
use Storable qw(freeze);
use JSON;
#use Data::Dumper;
use Clone qw(clone);
use Encode;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw/$qxwidth $qxheight $qxinterval/;
}

our $qxinterval = 100; # Sekunden

our $qxwidth = 700;  # Defaultwidth
our $qxheight = 500; # Defaultheight

our $qxsearchwidth = 250;
our $qxsearchheight = 300;

$SIG{CHLD} = 'IGNORE';

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $self = {};

   bless ($self, $class);

   $self->{gui} = shift;
   $self->{dbm} = shift;
   $self->{text} = $self->{gui}->{text}; # get the ref. to the text Object from the gui module

   $self->{clients} = {};

   $self->{dbm}->{config}->{qooxdooprepath} = $self->{dbm}->{cwd} . $self->{text}->{qx}->{paths}->{qx_building_subdir}
      unless $self->{dbm}->{config}->{qooxdooprepath};

   $self->{telnetserver} = POE::Component::Server::TCP->new(
      Port => $self->{dbm}->{config}->{qooxdootelnetlistenport},
      Address => $self->{dbm}->{config}->{qooxdootelnetlistenip},
      ClientInput => sub {
         my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];
         $input =~ s/(\r|\n)$//g;
         foreach my $sessionid (keys %{$self->{dbm}->{sessions}}) {
            my $curSession = $self->{dbm}->getSession($sessionid);
            #print "XXX:".$curSession.":\n";
            if ($curSession->{client}) {
               $kernel->post($curSession->{client} => sendToQX => $input);
               print "sending to ".$sessionid." over ".$curSession->{client}.".\n";
            } else {
               print $sessionid." is not connected.\n";
            }
         }
      }
   ) if ($self->{dbm}->{config}->{qooxdootelnetlistenport} &&
         $self->{dbm}->{config}->{qooxdootelnetlistenip});

   $self->{webserver} = POE::Component::Server::TCP->new(
      Address => $self->{dbm}->{config}->{qooxdoolistenip},
      Port => $self->{dbm}->{config}->{qooxdoolistenport},
      ClientFilter => "POE::Filter::HTTPD",
      Error => sub {
         my ($syscall, $error_number, $error_message) = @_[ARG0 .. ARG2];
         die("Couldn't start consumer server: ".$syscall." error ".$error_number.": ".$error_message);
      },
      ClientConnected => sub {
         my ($session, $heap) = @_[SESSION, HEAP];
         my $client_id = $session->ID();
         $self->{clients}->{$client_id} = {};
      },
      ClientDisconnected => sub {
         my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
         my $client_id = $session->ID();
         my $connection = $self->{clients}->{$client_id};
         my $curSession = $self->{dbm}->getSession($connection->{sessionid});
         if ($self->can("handleAjax") && $heap->{ajaxhandler}) {
            return if ($heap->{ajaxhandler} = $self->handleAjax($AJAXDISCONNECTED, $kernel, $session, $heap));
         }
         if ($heap->{openfile}) {
            close($heap->{openfile});
            delete $heap->{openfile};
         }
         delete $curSession->{client}
            if (exists($curSession->{client}) &&
               defined($curSession->{client}) &&
                      ($curSession->{client} eq $client_id));
         delete $self->{clients}->{$client_id};
      },
      ClientFlushed => sub {
         my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
         if ($self->can("handleAjax") && $heap->{ajaxhandler}) {
            return if ($heap->{ajaxhandler} = $self->handleAjax($AJAXFLUSHED, $kernel, $session, $heap));
         }
         if ($heap->{openfile}) {
            if (my $read_count = sysread($heap->{openfile}, my $buffer = "", 65536)) {
               $heap->{client}->put($buffer);
            } else {
               close($heap->{openfile});
               delete($heap->{openfile});
               $kernel->yield("shutdown");
            }            
         } else {
            $kernel->yield("shutdown") unless $heap->{stayalive};
         }
      },
      ClientInput => sub {
         my ($kernel, $session, $heap, $request) = @_[KERNEL, SESSION, HEAP, ARG0];
         my $url = $request->uri();
         my $q = CGI->new($url);
         if (($request->method() =~ /^post$/i) && (!$q->param("job"))) {
            $q = CGI->new($request->content());
         #} else {
         #   $q = CGI->new($url);
         }
         #print "A:\n".$request->content().":B:\n".$url."\n";
         my $response = HTTP::Response->new();
         my $content = '';
         if ($request->uri =~ '^/(index.html?)?(\?[^\/]*)?$') {
            $response->code(RC_OK);
            $response->content_type("text/html; charset=utf-8");
            $content .= '<!DOCTYPE html>'."\n";
            $content .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">'."\n";
            $content .= '<head>'."\n";
            $content .= '  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />'."\n";
            $content .= '  <title>'.($self->{dbm}->{config}->{qooxdooname} || "Automatisches Datenbank GUI").'</title>'."\n";
            $content .= '  <script type="text/javascript" src="script/myproject.js';
            #$content .= '?nocache='.rand(999999999999).'&job='.$q->param("job").'&sessionid='.$q->param("sessionid").'
            $content .= '"></script>'."\n";
            $content .= '</head>'."\n";
            $content .= '<body></body>'."\n";
            $content .= '</html>'."\n";
            $response->content($content);
            $heap->{client}->put($response);
            $kernel->yield("shutdown");
         } elsif ($request->uri =~ '^/ajax') {
            $heap->{client_id} = $session->ID();
            $heap->{connection} = $self->{clients}->{$heap->{client_id}};
            # TODO:XXX:FIXME: Wird im DBManager ueber GUI.pm nicht uebermittelt... ist im DBManager dann also auch nicht
            #                 verfuegbar. Sollte auch dort uebermittelt werden... vieleicht bei AUTH/SESSION?
            $heap->{connection}->{ip} = $request->header('X-Forwarded-For') || $heap->{remote_ip};
            $heap->{connection}->{port} = $heap->{remote_port};
            $heap->{connection}->{sessionid} = $q->param("sessionid");
            $heap->{connection}->{q} = $q;
            $heap->{connection}->{request} = $request;
            Log("Ajax: sessionid=".$heap->{connection}->{sessionid}.":".$request->method().":".$request->uri().":".length($request->content())." Bytes:", $DEBUG);
            my $job = $q->param("job") || "";
            if ($heap->{connection}->{sessionid}) {
               my $cursession = undef;
               $response->code(RC_OK);
               $response->content_type("text/plain; charset=utf-8");
               if ($job eq "poll") {
                  delete $cursession->{cached};
                  delete $cursession->{cachedcontenttype};
                  if (defined($cursession = $self->{dbm}->getSession($heap->{connection}->{sessionid}))) {
                     Log("Replacing already exiting long-polling connection", $INFO) if (defined($cursession->{client}));
                  } else {
                     $self->{dbm}->registerSession(($cursession = {client => $heap->{client_id}}), $heap->{connection}->{sessionid});
                     $cursession->{model} = "qooxdoo";
                     $cursession->{openObjects} = {};
                     return $kernel->yield("on_client_new");
                  }
                  $cursession->{lastaccess} = time();
                  if (ref($cursession->{que}) eq "ARRAY") {
                     foreach my $text (@{$cursession->{que}}) {
                        next unless defined($text);
                        $content .= $text."\n";
                     }
                     delete $cursession->{que};
                  } else {
                     $cursession->{client} = $heap->{client_id};
                     return $kernel->delay(update_client => $qxinterval);
                  }
               } elsif ($job eq "getcached") {
                  $response->content_type("text/html; charset=UTF-8");
                  if (defined($cursession = $self->{dbm}->getSession($heap->{connection}->{sessionid})) && $cursession->{cached}) {
                     $response->content_type($cursession->{cachedcontenttype}) if $cursession->{cachedcontenttype};
                     $response->header("Content-Disposition" => "inline; filename=".$cursession->{cachedfilename}) if $cursession->{cachedfilename};
                     $content = $cursession->{cached};
                  } else {
                     $content = "Internal error.";
                  }
               } elsif ($job eq "getfile") {
                  $response->content_type("text/html; charset=UTF-8");
                  if (defined($cursession = $self->{dbm}->getSession($heap->{connection}->{sessionid})) && $cursession->{cached}) {
                     if(open($heap->{openfile}, "<", $cursession->{cached})) {
                        $response->content_type($cursession->{cachedcontenttype}) if $cursession->{cachedcontenttype};
                        $response->header("Content-Disposition" => "inline; filename=".$cursession->{cachedfilename}) if $cursession->{cachedfilename};
                     } else {
                        delete $heap->{openfile};
                        $content = "Internal error opening file: ".$!;
                     }
                     delete $cursession->{cachedcontenttype};
                  } else {
                     $content = "Internal error.";
                  }
               } else {
                  return if ($self->can("handleAjax") && ($heap->{ajaxhandler} = $self->handleAjax($AJAXSTART, $kernel, $session, $heap, $request, $response, $self->{dbm}->getSession($heap->{connection}->{sessionid}))));
                  $kernel->call($session => on_client_data => $response => \$content);
               }
               if (ref($content) eq "HASH") {
                  if ($content->{content}) {
                     $response->content_type("text/html; charset=UTF-8");
                     $response->content($content->{content});
                     $heap->{client}->put($response);
                  }
                  if ($content->{function}) {
                     $heap->{client}->set_output_filter(POE::Filter::Stream->new());
                     $heap->{stayalive}++;
                     if ($content->{fork}) {
                        $self->{dbm}->outputForked($_[SESSION]->ID(), $content->{function}, $content->{params}, $content->{forktimeout}, 0, $content->{presend}, $content->{postsend});
                     } else {
                        $kernel->yield(send_message => &{$content->{function}}($content->{params}));
                     }
                  }
               } else {
                  $response->content($content);
                  $heap->{client}->put($response);
                  if ($heap->{openfile}) {
                     $heap->{client}->set_output_filter(POE::Filter::Stream->new());
                  } else {
                     $kernel->yield("shutdown");
                  }
               }
            } else {
               Log("No sessionid!", $WARNING);
               $content = "Internal error.";
               $response->content($content);
               $heap->{client}->put($response);
               $kernel->yield("shutdown");
            }
         } else {
            $response->code(404);
            $response->content("404 Not found.\n");
            if ($url =~ m,^(http://[^/]+)?/([^\?]*)\??.*$,) {
               my $file = $self->{dbm}->{config}->{qooxdooprepath}.$2;
               my $defaultfile = "index.html";
               if ((($file =~ m,/$,) || (!$file) || (-d $file)) && (-f $file."/".$defaultfile)) {
                  $file .= $defaultfile;
               }
               if (open(FILE, "<", $file)) {
                  # TODO:XXX:FIXME: Das sollte asynchron gehen! Da haben wir was schonmal gemacht, im Dokumentenmanagementsystem zum Ausliefern der Dateien!
                  #print "Sending ".$file."\n";
                  my $tmp = '';
                  my $data = '';
                  while(sysread(FILE, $tmp, 65535)) { 
                     $data .= $tmp;
                  }
                  close(FILE);
                  $response->code(RC_OK);
                  if($file =~ m,\.png$,) {
                     $response->content_type("image/png");
                  }
                  $response->content($data);
               } else {
                  Log("HTTP: Not found: ".$file, $INFO);
               }
            }
            $heap->{client}->put($response);
            $kernel->yield("shutdown");
         }
      },
      InlineStates => {
         send_message => sub {
            my ($heap, $message) = @_[HEAP, ARG0];
            $heap->{client} && $heap->{client}->put($message);
         }, update_client => sub {
            my ($kernel, $heap, $message) = @_[KERNEL, HEAP, ARG0];
            my $response = HTTP::Response->new();
            $response->code(RC_OK);
            $response->content("");
            $response->content_type("text/plain; charset=UTF-8");
            $heap->{client} && $heap->{client}->put($response);
            $kernel->yield("shutdown");
         }, on_client_new => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            my $curSession = $self->{dbm}->getSession($heap->{connection}->{sessionid});           
            $curSession->{ip}   = $heap->{connection}->{ip};
            $curSession->{port} = $heap->{connection}->{port};
            Log("New Client: ".$heap->{connection}->{sessionid}, $INFO);
            $self->resetQX({
               curSession => $curSession,
               connection => $heap->{connection},
            });
            $self->onAuthenticate({
               connection => $heap->{connection},
               heap => $heap,
               curSession => $curSession
            });
         }, on_client_data => sub {
            my ($kernel, $heap, $session, $response, $content) = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];
            my $client_id = $session->ID();
            $heap->{connection} = $self->{clients}->{$client_id};
            my $curSession = undef;
            if (defined($curSession = $self->{dbm}->getSession($heap->{connection}->{sessionid}) || undef)) {
               $curSession->{ip}   = $heap->{connection}->{ip};
               $curSession->{port} = $heap->{connection}->{port};
            }
            $curSession->{deleteAfterDisconnect} = {};
            $curSession->{lastQXAccessTime} = time();
            $self->onClientData({
               curSession => $curSession,
               # TODO:XXX:FIXME: Das is alles unueberprueft vom User!!!
               crosslink =>  $heap->{connection}->{"q"}->param("crosslink") || '',
               crossid =>    $heap->{connection}->{"q"}->param("crossid") || '',
               crosstable => $heap->{connection}->{"q"}->param("crosstable") || '',
               table =>      $heap->{connection}->{"q"}->param("table") || '',
               $UNIQIDCOLUMNNAME => $heap->{connection}->{"q"}->param($UNIQIDCOLUMNNAME) || '',
               ids => [split(";", $heap->{connection}->{"q"}->param("ids") || "")],
               oid =>        $heap->{connection}->{"q"}->param("oid"  ) || '',
               job =>        $heap->{connection}->{"q"}->param("job"  ) || '',
               heap =>       $heap,
               response =>   $response,
               connection => $heap->{connection},
               request  =>   $heap->{connection}->{request},
               content =>    $content,
            });
            delete $curSession->{deleteAfterDisconnect};
         }, sendToQX => sub {
            my ($kernel, $heap, $text, $sessionid) = @_[KERNEL, HEAP, ARG0, ARG1];
            $sessionid ||= $heap->{connection}->{sessionid} || 0;
            return $self->sendToQXForSession($heap->{connection}->{sessionid} || 0, $text);
         }
      },
   );
   return $self;
}

sub sendToQXForSession {
   my $self = shift;
   my $sessionid = shift;
   my $text = shift;
   my $ids = undef;
   my $noque = shift || 0;
   my $response = HTTP::Response->new();
   $response->code(RC_OK);
   $response->content($text."\n") if defined($text);
   $response->content_type("text/plain; charset=UTF-8");
   if ($sessionid) {
      if (defined($self->{dbm}->getSession($sessionid))) {
         $ids = [$sessionid];
      } else {
         Log("Qooxdoo.pm: sendToQX: Unknown session: ".$sessionid."!", $WARNING);
         return; #die("Unknown session!");
      }
   } else {
      $ids = [keys %{$self->{dbm}->{sessions}}];
   }
   foreach my $sessionid (@$ids) {
      if (defined(my $curSession = $self->{dbm}->getSession($sessionid))) {
         if (exists($curSession->{client}) &&
            defined($curSession->{client})) {
            Log("Sending for session ".$sessionid." to poesession ".$curSession->{client}, $DEBUG);
            $poe_kernel->call($curSession->{client} => send_message => $response);
            $poe_kernel->call($curSession->{client} => "shutdown");
            delete $curSession->{client};
         } else {
            #Log("Writing for session ".$sessionid." to buffer.", $DEBUG);
            unless ($noque) {
               push(@{$curSession->{que}}, $text);
               Log("Qued ".scalar(@{$curSession->{que}})." packets for ".$sessionid."!", $DEBUG);
            }
         }
      } else {
         Log("Session ".$sessionid." not found.", $WARNING);
      }
   }
}

=pod

=head2 showActivate( $options, $suffix, $moreparams )

Execute a shell command and display the output in a new window.
(This is called an I<Activate> in ADBGUI Terminology).
Using Ajax therefore nearly "live" output.
Calls sendToQx() with createiframe as Parameter, this call contains
a /ajax url, therefore handleAjax() will be called which does the
actual invokation of the Activate.

The concrete Activate is stored in I<$options-E<gt>{activate}>
The mapping from activate to command is stored in dbm.cfg.   
  For example:
  I<activatecmd>B<Addkey> ./command.sh

defines the activate B<Addkey>

I<Returns:> Nothing of meaning.

=cut


sub showActivate
{
    my $self       = shift;
    my $options    = shift;
    my $suffix     = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams ) && $options->{curSession} ) {
        Log(
            "onClientData: Missing parameters: connection session="
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }

    my $window = (
        $options->{window}
          || (
            "activate"
            . (
                  $options->{table}    ? "_" . $options->{table}
                : $options->{activate} ? "_" . $options->{activate}
                : ''
            )
          )
    );

    $poe_kernel->yield(sendToQX => "destroy " . CGI::escape( $window . "_iframe" ) );

    $options->{curSession}->{activateparams}->{ $options->{activate} } =
      ( $options->{params} && ( ref( $options->{params} ) eq "ARRAY" ) )
      ? $options->{params}
      : $options->{params} ? [ $options->{params} ]
      :                      [];

    $poe_kernel->yield(
            sendToQX => "createiframe "
          . CGI::escape( $window . "_iframe" ) . " "
          . CGI::escape(
                "/ajax?nocache="
              . rand(999999999999)
              . "&job=preactivate&activate="
              . $options->{activate}
              . "&table="
              . $options->{table}
              . "&sessionid="
              . $options->{curSession}->{sessionid}
          )
    );

#$poe_kernel->yield(sendToQX => "addobject ".CGI::escape($window)." ".CGI::escape($window."_".$suffix."_acticate_iframe));
    my $curdef = {};
    
    if ( $options->{table} )
    {
        my $curtabledef = $self->{dbm}->getTableDefiniton( $options->{table} );
        $curdef->{width} =
             $curtabledef->{qxactivatewidth}
          || $curtabledef->{qxwidth}
          || $qxwidth;
        $curdef->{height} =
             $curtabledef->{qxactivateheight}
          || $curtabledef->{qxheight}
          || $qxheight;
        $curdef->{label} = $curtabledef->{label} || $options->{table};
        $curdef->{icon} = $curtabledef->{icon};
    }

    $curdef->{label} ||=
         $options->{label}
      || $options->{activate}
      || $self->{text}->{qx}->{unnamed};

    $curdef->{height} ||= $options->{height} || $qxheight;
    $curdef->{width}  ||= $options->{width}  || $qxwidth;
    $curdef->{icon}   ||= $options->{icon}   || '';

    $poe_kernel->yield( sendToQX => "createwin "
          . CGI::escape($window) . " "
          . CGI::escape( $curdef->{width} ) . " "
          . CGI::escape( $curdef->{height} ) . " "
          . CGI::escape( $self->{text}->{qx}->{enable} . $curdef->{label} )
          . " "
          . CGI::escape( $curdef->{icon} ) );

    $poe_kernel->yield( sendToQX => "addobject "
          . CGI::escape($window) . " "
          . CGI::escape( $window . "_iframe" ) );
    
    $poe_kernel->yield( sendToQX => "open " . CGI::escape($window) . " 1" );

    $poe_kernel->yield( sendToQX => "modal " . CGI::escape($window) . " 1" )
      if ( $options->{modal} );
}

sub handleAjax {
    my $self       = shift;
    my $action     = shift;
    my $kernel     = shift;
    my $session    = shift;
    my $heap       = shift;
    my $request    = shift;
    my $response   = shift;
    my $curSession = shift;

#$self->SUPER::handleAjax($action, $kernel, $session, $heap) if $self->SUPER::can("handleAjax");
    if ( $heap->{connection}->{"q"}->param("job") eq "preactivate" ) {
        if ( $action == $AJAXSTART ) {
            my $activate = $heap->{connection}->{"q"}->param("activate") || '';
            $response->code(RC_OK);
            $response->content_type("text/html; charset=UTF-8");
            if ( my $activatecmd =
                $self->{dbm}->{config}->{ "activatecmd" . $activate } )
            {
                my $activateparams = [];
                if ( $activate && $curSession ) {
                    $activateparams = $curSession->{activateparams}->{$activate}
                      || [];
                    delete $curSession->{activateparams}->{$activate};
                }
                $response->content("<pre>");
                $heap->{client}->put($response);
                $heap->{client}
                  ->set_output_filter( POE::Filter::Stream->new() );
                $heap->{connection}->{activate} = POE::Session->create(
                    inline_states => {
                        _start => sub {
                            my (
                                $kernel,        $heap,
                                $parentsession, $client,
                                $activatecmd,   $activateparams,
                                $timeout,       $activate,
                                $qooxdoo,       $curSession
                              )
                              = @_[
                              KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3,
                              ARG4,   ARG5, ARG6, ARG7
                              ];
                            $heap->{parentsession}  = $parentsession;
                            $heap->{parentclient}   = $client;
                            $heap->{timeout}        = $timeout;
                            $heap->{qooxdoo}        = $qooxdoo;
                            $heap->{activate}       = $activate;
                            $heap->{activatecmd}    = $activatecmd;
                            $heap->{activateparams} = $activateparams;
                            $heap->{curSession}     = $curSession;
                            my $cmd = undef;
                            eval {
                                $cmd = POE::Wheel::Run->new(
                                    Program     => $activatecmd,
                                    ProgramArgs => $activateparams || [],

                                    #CloseOnCall => 1,
                                    StdoutEvent => 'output',
                                    StderrEvent => 'output',
                                    ErrorEvent  => 'error',
                                    CloseEvent  => 'close',
                                    StdioFilter => POE::Filter::Stream->new()
                                );
                            };
                            if ($@) {
                                $heap->{parentclient}
                                  ->put( "ERROR STARTING:" . $@ )
                                  if ( defined( $heap->{parentclient} ) );
                            }
                            $heap->{cmd} = $cmd;
                            my $pid = "Unknown";
                            if ( defined( $heap->{cmd} ) ) {
                                $pid = $heap->{cmd}->PID;
                            }
                            $heap->{parentclient}
                              ->put( "Program started (PID:" . $pid . ")\n" )
                              if ( defined( $heap->{parentclient} ) );
                            $poe_kernel->delay( "timeout" => $heap->{timeout} )
                              if $heap->{timeout};
                        },
                        _stop => sub {

                           #delete $heap->{parentclient};
                           #$kernel->call($heap->{parentsession} => "shutdown");
                           #print "DONE\n";
                        },
                        output => sub {

                            #print "OUTPUT\n";
                            my ( $kernel, $heap, $output, $wheel_id ) =
                              @_[ KERNEL, HEAP, ARG0, ARG1 ];

                            #$output =~ s,\n,<br>\n,g;
                            #$output = $output.(join(",", split(//, $output)));
                            $heap->{parentclient}
                              ->put( $heap->{qooxdoo}->can("onCmdRead")
                                ? $heap->{qooxdoo}->onCmdRead( $heap, $output )
                                : $output )
                              if ( defined( $heap->{parentclient} ) );

                            #syswrite(STDOUT, "PUT".length($output)."\n");
                        },
                        error => sub {
                            my ( $kernel, $heap, $operation, $errnum, $errstr,
                                $wheel_id )
                              = @_[ KERNEL, HEAP, ARG0 .. ARG3 ];
                            return
                              if ( $operation eq "read" ) && ( $errnum == 0 );
                            $heap->{parentclient}->put( "ERROR:"
                                  . $operation
                                  . " error "
                                  . $errnum . ": "
                                  . $errstr )
                              if ( defined( $heap->{parentclient} ) );
                            delete $heap->{parentclient};
                            $kernel->call(
                                $heap->{parentsession} => "shutdown" );

                            #print "ERROR:".$errnum."\n";
                        },
                        close => sub {
                            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                            my $pid    = "Unknown";
                            my $return = "Unknown";

                            #print "CLOSE\n";
                            if ( defined( $heap->{cmd} ) ) {
                                $pid = $heap->{cmd}->PID;
                                $return = waitpid( $pid, 0 );
                            }
                            delete $heap->{cmd};
                            $heap->{parentclient}
                              ->put( $heap->{qooxdoo}->onCmdClose($heap) )
                              if $heap->{qooxdoo}->can("onCmdClose");
                            $heap->{parentclient}
                              ->put("Program terminated (PID:"
                                  . $pid
                                  . ", RET:"
                                  . $return
                                  . ")" )
                              if ( defined( $heap->{parentclient} ) );
                            delete $heap->{parentclient};
                            $kernel->call(
                                $heap->{parentsession} => "shutdown" );
                            $poe_kernel->delay( "timeout" => undef );

                            #print "CLOSEEND\n";
                        },
                        timeout => sub {
                            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                            my $pid = "unknown";
                            if ( defined( $heap->{cmd} ) ) {
                                $pid = $heap->{cmd}->PID;
                            }
                            $heap->{parentclient}
                              ->put("TIMEOUT: Killing process(PID:"
                                  . $pid
                                  . ") after "
                                  . $heap->{timeout}
                                  . " seconds." )
                              if ( defined( $heap->{parentclient} ) );
                            $poe_kernel->yield("terminate");
                        },
                        terminate => sub {
                            my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
                            $heap->{cmd}->kill()
                              if ( defined( $heap->{cmd} ) );
                          }
                    },
                    args => [
                        $session,
                        $heap->{client},
                        $activatecmd,
                        $activateparams,
                        $self->{dbm}->{config}->{"cmdtimeout"} || 3600,
                        $activate,
                        $self,
                        $curSession
                    ]
                );
            }
            else {
                $response->content(
                        $self->{text}->{qx}->{activate_not_configured}
                      . $activate );
                $heap->{client}->put($response);
                $kernel->yield("shutdown");
                return 1;
            }
        }
        elsif ( $action == $AJAXDISCONNECTED ) {

            #print "TERM\n";
            $poe_kernel->call( $heap->{connection}->{activate}, "terminate" );

            #$heap->{client}->put(" " x 20)
            #   if (exists($heap->{client}) && defined($heap->{client}));
            #delete $heap->{client};
            $kernel->yield("shutdown");
        }
        return 1;
    }
    return 0;
}

sub resetQX {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift || 0;
   unless ((!$moreparams) && $options->{curSession} && $options->{connection}) {
      Log(
          "onClientData: Missing parameters: connection session="
            . $options->{curSession}
            . " connection="
            . $options->{connection} . ": !",
          $ERROR
      );
      return undef;
   }
   $options->{curSession}->{openObjects} = {};
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "reset");
}

sub doQxContext {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{connection}) {
      Log("onClientData: Missing parameters: session:".$options->{curSession}." connection:".$options->{connection}."!", $ERROR);
      return undef;
   }
   
   my $contextSession = undef;
   my $contextid = $options->{contextid};

   if (ref($contextSession = $self->doContext($contextid, $options)) ne "HASH")
   {

      if ($options->{dologin} && defined($contextSession) && ($contextSession == 0))
      {
         my $window = "context";
         my $db = $self->{dbm}->getDBBackend($USERSTABLENAME);
         my $line = $db->getUsersSessionData("", 0, $contextid);
         my $username = $line->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME};

         $poe_kernel->yield(sendToQX => "destroy ".$window);
         $poe_kernel->yield( sendToQX => "createwin "
               . $window
               . " 500 160 "
               . CGI::escape( $self->{text}->{qx}->{accessing} . $username )
               . " "
               . CGI::escape('') );
         $poe_kernel->yield(sendToQX => "open ".$window." 1");

         $poe_kernel->yield(sendToQX => "createedit contextedit " . $options->{loginjob} . " " . 
            CGI::escape( $self->{text}->{qx}->{username} ) . "," . CGI::escape( $self->{text}->{qx}->{password} ) . "," . CGI::escape( $self->{text}->{qx}->{context} ) . " " . 
            CGI::escape("text")     . "," . CGI::escape("password") . "," . CGI::escape("text") . " " . 
            CGI::escape("username") . "," . CGI::escape("password") . "," . CGI::escape("contextid") . " " . 
            CGI::escape("hidden")   . "," . CGI::escape("")         . "," . CGI::escape("hidden") . " " . 
            CGI::escape($username)  . "," . CGI::escape("")         . "," . CGI::escape($contextid) . " " . 
            CGI::escape("")         . "," . CGI::escape("")         . "," . CGI::escape(""));

         $poe_kernel->yield(sendToQX => "addobject " . CGI::escape($window) . " " . CGI::escape("contextedit")); 
         #$poe_kernel->yield(sendToQX => "createbutton ".CGI::escape($window."_button")." ".
         #                                               CGI::escape("Schliessen")." ".
         #                                               CGI::escape("resource/qx/icon/Tango/32/actions/dialog-close.png")." ".
         #                                               CGI::escape("job=closeobject,oid=".$window));
         $poe_kernel->yield(sendToQX => "addobject " . CGI::escape($window) . " " . CGI::escape($window . "_button")); 

         return undef;
      }
      else
      {
         $poe_kernel->yield( sendToQX => "showmessage "
            . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 50 "
            . CGI::escape( $self->{text}->{qx}->{qx_context_error} . $contextid ) );
      }
   }

   return $contextSession;
}

# TODO:XXX:FIXME: doContext gehort eigentlich in den DBManager... man sollte nicht den Error hier
# per QX rausgeben sondern zurückgeben und im Aufrufer dann ausgeben.
sub doContext {
   my $self = shift;
   my $contextid = shift;
   my $options = shift;

   my $return = $options->{curSession};
   my $db = $options->{db} || $self->{dbm}->getDBBackend($USERSTABLENAME);

   if ( $contextid
        && ( $contextid ne $options->{curSession}->{
                   $USERSTABLENAME
                 . $TSEP
                 . $self->{dbm}->getIdColumnName($USERSTABLENAME)
           }))
   {
      my $err = $self->{dbm}->contextAllowed($contextid, $options);

      if (defined($err))
      {
         #$poe_kernel->yield(sendToQX => "showmessage ".
         #   CGI::escape("Internal error")." 300 50 ".
         #   CGI::escape($err." (CreateContext: ACCESS DENIED to ".$contextid.")"));
         Log("doContext: contextAllowed: ACCESS DENIED: ".$err, $INFO);
         return 0;
      } else {
         $self->{dbm}->setContext($options->{curSession}, $contextid, $options->{contextkey});
         $return = $db->getContext($options->{curSession}, $options->{contextkey});
      }
   }
   else
   {
      $db->destroyContext($options->{curSession}, $options->{contextkey});
   }

   if (ref($return) ne "HASH")
   {
      $poe_kernel->yield(sendToQX => "showmessage " . 
         CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 300 50 " . 
         CGI::escape( $self->{text}->{qx}->{context_error} . ($contextid||"UNDEF") . ")"));
      return undef;
   }
   return $return;
}

sub onClientData {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   unless ((!$moreparams) && $options->{heap} && $options->{curSession} && $options->{connection}) {
      Log("onClientData: Missing parameters: connection heap=".$options->{heap}.":session=".$options->{curSession}.": !", $ERROR);
      return undef;
   }

   if ($options->{job} eq "dblclick") {
      my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
      if ($curtabledef->{dblclick} && ($curtabledef->{dblclick} ne "dblclick")) {
         $options->{job} = $curtabledef->{dblclick};
         $self->onClientData($options);
      } else {
         if (!$curtabledef->{readonly}) {
            $options->{job} = "neweditentry";
            $self->onClientData($options);
         } else {
            Log("ADBGUI::Qooxdoo::onClientData: No double click action", $WARNING);
         }
      }
      return;
   }
   #print "INPUT: ".$options->{connection}->{sessionid}."\n";
   if ($options->{job} eq "delrow") {
      $self->onDelRow({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         "q" => $options->{connection}->{"q"},
         curSession => $options->{curSession},
         oid => $options->{oid},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         table => $options->{table}
      });
   } elsif ($options->{job} eq "treechange") {
      $self->onTreeChange({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         curSession => $options->{curSession},
         oid => $options->{oid},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         table => $options->{table},
         "q" => $options->{connection}->{"q"},
      });
  # } elsif($options->{job} eq "prefilter") {
  #    $options->{response}->code(RC_OK);
  #    $options->{response}->content_type("text/html; charset=UTF-8");
  #    ${$options->{content}} .= "<html>\n<head>\n";
  #    ${$options->{content}} .= "\n</head><body>";
  #    ${$options->{content}} .= "<form action='/ajax'>";
  #    ${$options->{content}} .= "<input type=hidden name=nocache value='".rand(999999999999)."'>\n";
  #    ${$options->{content}} .= "<input type=hidden name=table value='".$options->{table}."'>\n";
  #    ${$options->{content}} .= "<input type=hidden name=sessionid value='".$options->{curSession}->{sessionid}."'>\n";
  #    ${$options->{content}} .= "<input type=hidden name=job value='postfilter'>\n";
  #    #$options->{curSession}->{filter}->{general}->{$options->{table}}->{"gruppeLaufbahn.gruppe_id"} = 1;
  #    my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
  #    my $db = $self->{dbm}->getDBBackend($options->{table});
  #    my $tableconnections = {};
  #    if (($tableconnections = $db->searchTableConnections($options->{table}, $curtabledef->{defaulttablebackrefs} ? 1 : 0, undef, { $options->{table} => 1 })) &&
  #    (ref($tableconnections) eq "HASH") &&
  #  exists($tableconnections->{history}) &&
  # defined($tableconnections->{history}) &&
  #    (ref($tableconnections->{history}) eq "ARRAY") &&
  #scalar(@{$tableconnections->{history}})) {
  #       my $curtree = {};
  #       my $curelement = {
  #          $options->{table} => $curtree,
  #       };
  #       foreach my $curlink (@{$tableconnections->{history}}) {
  #          unless ($curelement->{$curlink->{table}}) {
  #             Log("Error: Unresolvable link: ".$curlink->{ctable}."(".$curlink->{asname}.") ".($curlink->{type} eq $FORWARD ? "->" : "<-")." ".$curlink->{table});
  #             next;
  #          }
  #          if (exists($curelement->{$curlink->{table}}->{$curlink->{ctable}})) {
  #             Log("Error: link already exiting: ".$curlink->{ctable}."(".$curlink->{asname}.") ".($curlink->{type} eq $FORWARD ? "->" : "<-")." ".$curlink->{table});
  #          } else {
  #             $curelement->{$curlink->{table}}->{$curlink->{ctable}} = {}; # type => $curlink->{type} };
  #             $curelement->{$curlink->{ctable}} = $curelement->{$curlink->{table}}->{$curlink->{ctable}};
  #          }
  #       }
  #       ${$options->{content}} .= "<pre>".Dumper($curtree);
  #       #${$options->{content}} .= join("<br>\n", map { ($_->{type} eq $FORWARD ? "->" : "<-")." ".$_->{ctable}."(".$_->{asname}.") to ".$_->{table} } @{$tableconnections->{history}});
  #    } else {
  #       ${$options->{content}} .= "Unable to build table reference tree!";
  #    }
   }
   elsif($options->{job} eq "auth")
   {
      $self->onAuthenticate({
         connection => $options->{connection},
         curSession => $options->{curSession}
      });
   }
   elsif($options->{job} eq "neweditentry")
   {
      $self->onNewEditEntry({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         table => $options->{table},
         connection => $options->{connection},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         oid => $options->{oid},
         ids => $options->{ids},
         curSession => $options->{curSession},
         "q" => $options->{connection}->{"q"},
      });
   }
   elsif($options->{job} eq "filterselecttable")
   {
      if (my $popupid = $options->{connection}->{"q"}->param("popupid")) {
         #$poe_kernel->yield(sendToQX => "show ".$popupid." 1");
         $self->onTableSelect({
            table => $options->{table},
            oid => $options->{oid},
            curSession => $options->{curSession},
            "q" => $options->{connection}->{"q"},
            urlappend => ",popupid=" . $popupid . ",table=" . $options->{table},
         });
         $poe_kernel->yield(sendToQX => "addobject " . CGI::escape($popupid) . " " . CGI::escape($options->{oid} . "_tableselect_tree"));
      } else {
         $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 200 " . CGI::escape( $self->{text}->{qx}->{popupid_missing} . $options->{job} ));
      }
   }
   elsif( ($options->{job} eq "filteropen")
          || ($options->{job} eq "filtersave") )
   {
        if ( my $popupid = $options->{connection}->{"q"}->param("popupid") )
        {
            my $urlappend = ",popupid=" . $popupid . ",table=" . $options->{table};

            $poe_kernel->yield(
                  sendToQX => "createtree "
                  . CGI::escape( $popupid . "_" . $options->{job} )     . " "
                  . CGI::escape( $self->{text}->{qx}->{saved_filters} ) . " "
                  . CGI::escape( ",treeaction=select" . $options->{job} . ",table=" . $options->{table}
                                 . ",loid=" . $options->{oid} . $urlappend )
            );

            $poe_kernel->yield(
                    sendToQX => "addtreeentry "
                  . CGI::escape( $popupid . "_" . $options->{job} ) . " "
                  . CGI::escape("") . " "
                  . CGI::escape("1") . " "
                  . CGI::escape( $self->{text}->{qx}->{first_entry} ) . " "
                  . CGI::escape( $self->{text}->{qx}->{paths}->{system_search_png} )
            );

            $poe_kernel->yield( sendToQX => "addtreeentry "
                  . CGI::escape( $popupid . "_" . $options->{job} ) . " "
                  . CGI::escape("") . " "
                  . CGI::escape("newentry") . " "
                  . CGI::escape( $self->{text}->{qx}->{new_entry} ) . " "
                  . CGI::escape( $self->{text}->{qx}->{paths}->{list_add} ) )
              unless ( $options->{job} eq "filteropen" );

            $poe_kernel->yield( sendToQX => "addobject "
                  . CGI::escape($popupid) . " "
                  . CGI::escape( $popupid . "_" . $options->{job} ) );
        }
        else   
        {
            $poe_kernel->yield( sendToQX => "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{internal_error} )
                  . " 400 200 "
                  . CGI::escape( $self->{text}->{qx}->{popupid_missing} . $options->{job} )
            );
        }
   }
   elsif($options->{job} eq "filter")
   {
      $self->onFilter({
         table => $options->{table},
         oid => $options->{oid},
         curSession => $options->{curSession},
         "q" => $options->{connection}->{"q"},
      });
   }
   elsif($options->{job} eq "filterhtml")
   {
      $self->onFilterHTML({
         table => $options->{table},
         oid => $options->{oid},
         curSession => $options->{curSession},
         response => $options->{response},
         content => $options->{content},
         "q" => $options->{connection}->{"q"},
      });
   }
   elsif($options->{job} eq "listcreateentry")
   {
      my $column = $options->{connection}->{"q"}->param("column") || '';
      my $id = $options->{connection}->{"q"}->param($UNIQIDCOLUMNNAME) || undef;
      my $table = undef,
      my $basetabledef = $self->{dbm}->getTableDefiniton($options->{table});      

      if ($basetabledef->{columns}->{$column} && $basetabledef->{columns}->{$column}->{linkto})
      {
         $table = $basetabledef->{columns}->{$column}->{linkto};
      } elsif ($self->{dbm}->{config}->{oldlinklogic} && ($column =~ m,^(.+)_$UNIQIDCOLUMNNAME$,))
      {
         $table = $1;
      }

      if ($table)
      {
         if (my $curtabledef = $self->{dbm}->getTableDefiniton($table)) {
            $self->onNewEditEntry({
               table => $table,
               oid => $options->{oid},
               connection => $options->{connection},
               curSession => $options->{curSession},
               $UNIQIDCOLUMNNAME => $id,
               # TODO:XXX:FIXME: Das wird ueber overridecolumns gemacht... Gute idee?
               override => {
                  AddAndSelectOID => $options->{connection}->{"q"}->param("oid") || '',
                  AddAndSelectColumn => $column,
                  AddAndSelectTable => $options->{table},
               }
            });
        } else 
        {
            my $msg           = "Error loading column: '"             . $table . "' -> '" . $column . "'";
            my $localised_msg = $self->{text}->{qx}->{col_load_error} . $table . "' -> '" . $column . "'"; 

            Log("Qooxdoo: listnewentry: ".$msg, $WARNING);
            $poe_kernel->yield(  sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 200 " . CGI::escape( $localised_msg ) );
         }
      } else {
         my $msg           = "Bad column information: '" . $column . "'";
         my $localised_msg = $self->{text}->{qx}->{col_info_error}  . $column . "'";
         
         Log("Qooxdoo: listnewentry: ".$msg, $WARNING);
         $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 200 " . CGI::escape( $localised_msg ) );
      }
   }
   elsif($options->{job} eq "show") {
      $self->onShow({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         connection => $options->{connection},
         crosstable => $options->{crosstable},
         oid => $options->{oid},
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         curSession => $options->{curSession},
         "q" => $options->{connection}->{"q"}
      });
   } elsif($options->{job} eq "showlist") {
      $self->onShowList({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         oid => $options->{oid},
         connection => $options->{connection},
         crosstable => $options->{crosstable},
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         curSession => $options->{curSession}
      });
   } elsif($options->{job} eq "updatelist") {
      $self->onUpdateList({
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         connection => $options->{connection},
         table => $options->{table},
         oid => $options->{oid},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         name => $options->{connection}->{"q"}->param("oid") || undef,
         curSession => $options->{curSession}
      });
   } elsif($options->{job} eq "getrowcount") {
      $self->onGetRowCount({
         "q" => $options->{connection}->{q},
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         table => $options->{table},
         curSession => $options->{curSession},
         connection => $options->{connection},
         oid => $options->{oid},
      });
   } elsif($options->{job} eq "closeobject") {
      $self->onCloseObject({
         curSession => $options->{curSession},
         oid => $options->{oid},
      });
   } elsif($options->{job} eq "getrow") {
      my $orderby = $options->{connection}->{"q"}->param("orderby");
      # TODO:FIXME:XXX: Das backend sollte orderby bei virutal Spalten ummappen können, im DBDesign sollte eine Spalte dafuer angegeben werden koennen
      my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
      foreach my $suffix ("", "_") {
         foreach my $curcolumn (keys(%{$curtabledef->{columns}})) {
            if ($orderby eq $options->{table}.$TSEP.$curcolumn.$suffix) {
               if (($curtabledef->{columns}->{$curcolumn}->{type} eq "virtual") && !($curtabledef->{columns}->{$curcolumn}->{usevirtualoderby})) {
                  $orderby = $options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table}).$suffix;
               }
               last;
            }
         }
      }
      $self->onGetLines({
         "q" => $options->{connection}->{"q"},
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         curSession => $options->{curSession},
         oid => $options->{oid},
         rowsadded => 0,
         sortby => $orderby,
         start => $options->{connection}->{"q"}->param("start"),
         end =>   $options->{connection}->{"q"}->param("end"),
         ionum => $options->{connection}->{"q"}->param("ionum"),
         connection => $options->{connection},
      });
   }
   elsif(($options->{job} eq "saveedit") ||
           ($options->{job} eq "newedit"))
   {
      my $id = $options->{$UNIQIDCOLUMNNAME} || $options->{connection}->{"q"}->param($self->{dbm}->getIdColumnName($options->{table}));
      my $params = {
         crosslink => $options->{crosslink},
         crossid => $options->{crossid},
         crosstable => $options->{crosstable},
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $id,
         oid => $options->{oid},
         connection => $options->{connection},
         curSession => $options->{curSession},
         "q" => $options->{connection}->{"q"},
         job => $options->{job},
      };
      $params->{columns} = $self->parseFormularData($params);
      $params->{columns}->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})} = $id;
      $self->onSaveEditEntry($params);
   }
   elsif($options->{job} eq "htmlpreview")
   {
      $self->onHTMLPreview({
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
         oid => $options->{oid},
         curSession => $options->{curSession},
         value => $options->{connection}->{"q"}->param("value") || "",
         column => $options->{connection}->{"q"}->param("column")
      });
   }
   elsif($options->{job} eq "statswin")
   {
      my $winname = "statswin";
      my $url = "/ajax?nocache=".rand(999999999999)."&job=statsval&sessionid=".$options->{curSession}->{sessionid};

      $poe_kernel->yield(sendToQX => "destroy ".CGI::escape($winname));
      $poe_kernel->yield(sendToQX => "createwin " . CGI::escape($winname) . " " . ($qxwidth) . " " . ($qxheight) . " " . CGI::escape( $self->{text}->{qx}->{live_stats} ) . " " . CGI::escape("icon"));
      $poe_kernel->yield(sendToQX => "createiframe ".CGI::escape($winname."_iframe")." ".CGI::escape($url));
      $poe_kernel->yield(sendToQX => "addobject ".CGI::escape($winname)." ".CGI::escape($winname."_iframe"));
      $poe_kernel->yield(sendToQX => "open ".CGI::escape($winname));
   }
   elsif($options->{job} eq "statsval")
   {
      if (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $ADMIN)))
      {
         $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 50 " . CGI::escape( $self->{text}->{qx}->{permission_denied} )  );
         return Log("DBManager: onNewLineServer: ".$options->{job}.": ACCESS DENIED: ".$err->[0], $err->[1]);
      }

      my $translations = $self->{text}->{qx}->{stats_window};

      my $value = "";
      my $url = "/ajax?nocache=".rand(999999999999)."&job=statsval&sessionid=".$options->{curSession}->{sessionid};
      
      $value .= $translations->{sessions} . scalar( keys %{ $self->{dbm}->{sessions} } ) . "<br>\n";    #<hr>\n";
      $value .= $translations->{cur_time} . scalar( time() ) . "<br>\n";
      $value .= "<input type=button onClick='window.location = " . '"' . $url . '"' . "' value='$translations->{refresh}'><br>";

      my $last = -1;

      #draw the stats for each session into the window (in sorted order):
      foreach my $session (
          sort {
              lc( $self->{dbm}->{sessions}->{$a}
                    ->{ $USERSTABLENAME . $TSEP . "username" } || "" ) cmp
                lc( $self->{dbm}->{sessions}->{$b}
                    ->{ $USERSTABLENAME . $TSEP . "username" } || "" )
                || (
                  (
                      $self->{dbm}->{sessions}->{$b}->{lastSessionAccessTime} || 0
                  ) <=> (
                      $self->{dbm}->{sessions}->{$a}->{lastSessionAccessTime} || 0
                  )
                )
               } keys %{ $self->{dbm}->{sessions} }
        )
      {
          my $cursession = $self->{dbm}->{sessions}->{$session};
          $value .= "<hr>"
            if ($last ne ($cursession->{$USERSTABLENAME . $TSEP
                        . $self->{dbm}->getIdColumnName($USERSTABLENAME)}
                    || 0)
            );
          $value .= $session
            . " ($self->{text}->{qx}->{username}: "
            . ( $cursession->{ $USERSTABLENAME . $TSEP . "username" } || "-" )
            . " / ID:"
            . ($cursession->{
                      $USERSTABLENAME
                    . $TSEP
                    . $self->{dbm}->getIdColumnName($USERSTABLENAME)
                } || "-");
  
          $value .= " IP: " . ( $cursession->{ip} || "-" ) . ")";
          
          $value .=
            " <br>Timeout: "
            . ( $cursession->{lastSessionAccessTime}
              ? ( time() - $cursession->{lastSessionAccessTime} )
              : "-" )
            . " / QX: "
            . ( $cursession->{lastQXAccessTime}
              ? ( time() - $cursession->{lastQXAccessTime} )
              : "-" )
            . " seconds ";
  
          $value .= " Size: " . length( freeze($cursession) ) . " Bytes";
  
          $value .= "<br>\n";
  
          $last =
            $cursession->{ $USERSTABLENAME
                . $TSEP
                . $self->{dbm}->getIdColumnName($USERSTABLENAME) }
            || 0;
      }
      $value  .= "<hr><input type=button onClick='window.location = " . '"' . $url . '"' . "' value='$translations->{refresh}'>";
      $options->{response}->code(RC_OK);
      $options->{response}->content_type("text/html; charset=UTF-8");
      ${$options->{content}} = $value;
   } else {
      $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape($self->{text}->{qx}->{internal_error}) . " 400 200 " . CGI::escape( $self->{text}->{qx}->{unknown_command} . $options->{job}) );
   }
}

sub parseFormularData {
   my $self = shift;
   my $options = shift;
   my $q = shift;
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $columns = {};
   #if ($options->{"q"}->param("ignoreEmptyValues")) {
      foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
         #next if $curtabledef->{columns}->{$column}->{hidden};
         $columns->{$options->{table}.$TSEP.$column} = htmlUnEscape(CGI::unescape($options->{"q"}->param($column)))
            if (defined($options->{"q"}->param($column)) || ($column eq $self->{dbm}->getIdColumnName($options->{table})));
         delete $columns->{$options->{table}.$TSEP.$column}
            if ((exists($columns->{$options->{table}.$TSEP.$column}) &&
                defined($columns->{$options->{table}.$TSEP.$column}) &&
                ($columns->{$options->{table}.$TSEP.$column} eq "")) && $curtabledef->{columns}->{$column}->{hidden});
      }
   #} else {
   #   foreach my $column (grep { (exists($curtabledef->{columns}->{$_}) &&
   #                              defined($curtabledef->{columns}->{$_}) &&
   #                               exists($curtabledef->{columns}->{$_}->{type}) &&
   #                              defined($curtabledef->{columns}->{$_}->{type}) &&
   #                                      $curtabledef->{columns}->{$_}->{type} &&
   #                                     ($curtabledef->{columns}->{$_}->{type} ne "htmltext") &&
   #                                     ($curtabledef->{columns}->{$_}->{type} ne "longtext")) } hashKeysRightOrder($curtabledef->{columns})) {
   #      $columns->{$options->{table}.$TSEP.$column} = htmlUnEscape(CGI::unescape($options->{"q"}->param($column)));
   #   }
   #}
   return $columns;
}

sub onTreeChange {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{table} && $options->{curSession}) {
      Log("onDelRow: Missing parameters: connection:".$options->{table}.": !", $ERROR);
      return undef;
   }
   my $treeaction = $options->{q}->param("treeaction");
   if ($treeaction eq "filter") {
      if (my $popupid = $options->{q}->param("popupid")) {
         my $loid = $options->{q}->param("loid");
         if ($options->{$UNIQIDCOLUMNNAME}) {
            #if ($options->{q}->param("entry")) {
               if ($self->addFilterEntry($options->{q}->param("entry"), $options->{curSession}, $options->{table}, $options->{$UNIQIDCOLUMNNAME})) {
                  $poe_kernel->yield(sendToQX => "destroy ".$popupid);
                  $poe_kernel->yield(sendToQX => "destroy ".CGI::escape($loid."_filter_iframe"));
                  $poe_kernel->yield(sendToQX => "createiframe ".CGI::escape($loid."_filter_iframe")." ".CGI::escape("/ajax?nocache=".rand(999999999999)."&job=filterhtml&table=".$options->{table}."&sessionid=".$options->{curSession}->{sessionid}."&oid=".$loid));
                  $poe_kernel->yield(sendToQX => "addobject ".CGI::escape($loid."_filter")." ".CGI::escape($loid."_filter_iframe"));
               }
            #} elsif(($options->{$UNIQIDCOLUMNNAME} =~ m,^[^\.]+$,) && ($options->{$UNIQIDCOLUMNNAME} ne "undefined")) {
            #   $self->addFilterEntry($loid, $options->{oid}, $popupid, $options->{curSession}, $options->{table}, $options->{$UNIQIDCOLUMNNAME}.$TSEP.$self->{dbm}->getIdColumnName($options->{$UNIQIDCOLUMNNAME}));
            #} else {
            #   $poe_kernel->yield(sendToQX => "showmessage ".CGI::escape("Info")." 400 200 ".CGI::escape("You selected ".$options->{$UNIQIDCOLUMNNAME}." for table ".$options->{table}));
            #}
         }
      }
   } else {
      Log("Unknown treeaction: ".$treeaction, $WARNING);
   }
}

sub addFilterEntry {
   my $self = shift;
   my $entry = shift;
   my $curSession = shift;
   my $table = shift;
   my $column = shift;
   my $accepted = 0;
   my $filter = $self->{dbm}->getFilter({
      curSession => $curSession,
      table => $table,
   });
   if ($entry) {   
      my $linktable = undef;
      my $basetabledef = $self->{dbm}->getTableDefiniton($table);      
      if ($basetabledef->{columns}->{$column} && $basetabledef->{columns}->{$column}->{linkto}) {
         $linktable = $basetabledef->{columns}->{$column}->{linkto};
      } elsif ($self->{dbm}->{config}->{oldlinklogic}) {
         my ($linktable) = (grep {
            $column eq $table.$TSEP.$_."_".$self->{dbm}->getIdColumnName($table)
         } keys %{$self->{dbm}->getDBBackend($table)->getTableList()});
      }   
      if ($linktable) {
         my $curtabledef = $self->{dbm}->getTableDefiniton($linktable);
         if ($curtabledef->{useAsFilterTable}) {
            $filter->{$linktable.$TSEP.$self->{dbm}->getIdColumnName($linktable)} ||= [];
            $accepted++;
         }
      } else {
         $filter->{$column} ||= "";
         $accepted++;
      }
   } elsif(($column =~ m,^[^\.]+$,) && ($column ne "undefined")) {
      my $curtabledef = $self->{dbm}->getTableDefiniton($column);
      if ($curtabledef->{useAsFilterTable}) {
         $filter->{$column.$TSEP.$self->{dbm}->getIdColumnName($column)} ||= [];
         $accepted++;
      }
   }
   $self->{dbm}->setFilter({
      curSession => $curSession,
      table => $table,
      filter => $filter,
   }) if $accepted;
   return $accepted;
}

sub onDelRow {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{table} && $options->{curSession}) {
      Log("onDelRow: Missing parameters: connection:".$options->{table}.": !", $ERROR);
      return undef;
   }
   if ($options->{$UNIQIDCOLUMNNAME} =~ /^\d+$/)
   {
      if ($options->{oid})
      {
         my $cmd = $options->{cmd} || "DEL";
         my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});

         if (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $MODIFY, $options->{table}, $options->{$UNIQIDCOLUMNNAME})))
         {
            $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 50 " . CGI::escape( $self->{text}->{qx}->{permission_denied} ));
            return Log("DBManager: onNewLineServer: ".$cmd.": ACCESS DENIED: ".$err->[0], $err->[1]);
         }

         if (($curtabledef->{readonly}) || ($curtabledef->{editonly}))
         {
            $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 50 " . CGI::escape( $self->{text}->{qx}->{table_non_modifiable} ));
            return Log("DBManager: onNewLineServer: ".$cmd.": ACCESS DENIED: ACCESS_LOG not allowed!");
         }
         
         #if ($self->{config}->{changelog}) {
         #   unless (syswrite($self->{config}->{changelog}, localtime(time)." ".
         #      $curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME}." ".$_."\n")) {
         #      Log("Unable to write change to Changelog!", $ERROR);
         #      die;
         #   }
         #}

         if (defined(my $err = $self->{dbm}->BeforeNewUpdate($options->{table}, $cmd, { $options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table}) => $options->{$UNIQIDCOLUMNNAME} }, $options->{curSession})))
         {
            Log("ADBGUI::Qooxdoo::onDelRow: BeforeNewUpdate failed: ".$err, $INFO);
            $poe_kernel->yield(sendToQX => "showmessage " . CGI::escape( $self->{text}->{qx}->{internal_error} ) . " 400 200 " . CGI::escape( $self->{text}->{qx}->{delrow_failed} ));
            return;
         }

         my $ret = $self->{dbm}->deleteUndeleteDataset({
            table => $options->{table},
            cmd => $cmd,
            $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
            session => $options->{curSession},
            wherePre => $self->{dbm}->Where_Pre($options)
         });

         if ($ret =~ /^\d+$/)
         {
            # TODO:FIXME:XXX: Das sollte an alle anderen user auch gehen, die auf der tabelle sind!
            $poe_kernel->yield(sendToQX => "delrow ".CGI::escape($options->{table})." ".CGI::escape($options->{$UNIQIDCOLUMNNAME}));
         } else   
         {
            Log("DBManager: onNewLineServer: ".$cmd." ".$options->{table}." FAILED: SQL Query failed: ".$ret, $ERROR);
            $poe_kernel->yield( sendToQX => "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{internal_error} )
                  . " 400 200 "
                  . CGI::escape( $self->{text}->{qx}->{delrow_linex_failed} . $ret ) );
         }

         return $ret;

      }
      else
      {    
         return "DELROW: Bad Object-ID Format: ".$options->{oid}."\n";
      }
   }
   else
   {    
      return "DELROW: Bad ID Format: ".$options->{$UNIQIDCOLUMNNAME}."\n";
   }
}

sub onAuthenticate
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams )
        && $options->{connection}
        && $options->{curSession} )
    {
        Log(
            "onAuthenticate: Missing parameters: connection:"
              . $options->{connection} . ": !",
            $ERROR
        );
        return undef;
    }

    my $user = $options->{connection}->{"q"}->param("user");
    my $pass = $options->{connection}->{"q"}->param("pass");
    my $su   = $options->{connection}->{"q"}->param("su");

    if (
        defined(
            my $err = $self->{dbm}->checkRights( $options->{curSession}, $NOTHING )
        )
      )
    {
        if ($user)
        {
            $poe_kernel->yield(
                    sendToQX => "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{login_error} )
                  . " 400 50 "
                  . CGI::escape( $self->{text}->{qx}->{application_unavailable} )
            );
        }
    }
    else {
        my $dbline;
        if (
            (
                   ($user)
                && ( $dbline = $self->{dbm}->loginUser( $user, $pass, $su ) )
            )
            && (
                $options->{curSession} = $self->{dbm}->initialiseUserSession(
                    $options->{connection},
                    $options->{curSession}->{sessionid},
                    $options->{curSession}->{client},
                    $dbline
                )
            )
          )
        {
            $self->onAuthenticated($options);
            $options->{curSession}->{rights} =
              $self->{dbm}->getRightFlags( $options->{curSession} );
            $poe_kernel->yield( sendToQX => "closeloginwin" );
            return 1;
        }
        else
        {
            my $db = $self->{dbm}->getDBBackend($USERSTABLENAME);
            Log( "DBManager: onNewLineServer: SESSION: Session not found.", $DEBUG );

            #delete $options->{curSession}->{openObjects}->{loginWindow};
            unless (( !$user && $db->{config}->{DB}->{nodefaultloginwin} )) { 
                $self->showLoginWindow($options);
            }

            if ($user) {
                $poe_kernel->yield( sendToQX => "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{login_error} )
                  . " 400 50 "
                  . CGI::escape( $self->{text}->{qx}->{wrong_pw_user_combo} )
            );
            }
        }
    }
    return 0;
}

sub showLoginWindow {
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;
    unless ( ( !$moreparams ) && $options->{curSession} ) {
        Log(
            "showLoginWindow: Missing parameters: connection:"
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }
    $poe_kernel->yield(
        sendToQX => "showloginwin "
          . CGI::escape(
            (
                  $self->{dbm}->{config}->{qooxdooname}
                ? $self->{dbm}->{config}->{qooxdooname} . " "
                : "ADBGUI "
            )
            . "Login"
          )
          . (
            $options->{username} ? " " . CGI::escape( $options->{username} )
            : ''
          )
    );
}

sub getBasicDataDefine {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{action} && $options->{table} && $options->{curSession} && $options->{columns} && (ref($options->{columns}) eq "ARRAY") && scalar(@{$options->{columns}})) {
      Log("getBasicDataDefine: Missing parameters: action:".$options->{action}." table:".$options->{table}.":curSession:".$options->{curSession}.":curtabledef:".$options->{curtabledef}.":columns:".$options->{columns}.":more:".scalar($moreparams).": !", $ERROR);
      return undef;
   }
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $db = $self->{dbm}->getDBBackend($options->{table});
   # TODO:XXX:FIXME: Was ist $self->{links}, wieso ist das Objektglobal?!
   $self->{links} ||= {};
   # TODO:XXX:FIXME: overridecolumns sollte wieder raus... Das sollte im Falle von context (Zeiterfassung) ueber getURL oder so gehen! Muss also ins Qooxdoo (js) rein.
   $options->{overridecolumns} ||= [];
   my $filter = $self->{dbm}->getFilter($options);
   return [
      CGI::escape($options->{table}),                                                                                  # 2. Tabellenname, fuer Drag+Drop
      join(",", ((map {                                           
         my $column = $_;
         my $curTable = undef;
         if ($db && ($curTable = [grep {
           (($curtabledef->{columns}->{$column}->{linkto} &&
            ($curtabledef->{columns}->{$column}->{linkto} eq $_)) ||
            ($self->{dbm}->{config}->{oldlinklogic} && ($column eq $_."_".$UNIQIDCOLUMNNAME)))
         } keys(%{$db->{config}->{DB}->{tables}})]) && scalar(@$curTable)) {
            $options->{links}->{$column} = $curTable;
         }
         CGI::escape($curtabledef->{columns}->{$_}->{label} || $_)
      } @{$options->{columns}}), @{$options->{overridecolumns}})),                                                     # 3. Spaltename, uebersetzt. Zudem werden Tabellenverknuepfungen erkannt.
      join(",", ((map {                    
         CGI::escape(($options->{links}->{$_}) ? "list" :
            (exists($options->{realtype}) && $options->{realtype} && ($curtabledef->{columns}->{$_}->{type} ne "virtual")) ?
               (($_ eq $DELETEDCOLUMNNAME) ? "boolean" : $curtabledef->{columns}->{$_}->{type}) :
               $curtabledef->{columns}->{$_}->{qxtype} ||
               $curtabledef->{columns}->{$_}->{type})
      } @{$options->{columns}}), map { "text" } @{$options->{overridecolumns}})),                                      # 4. Typen, erkannte Tabellenverknuepfungen werden "list".
      join(",", (@{$options->{columns}}, @{$options->{overridecolumns}})),                                             # 5. Der Spaltenname in der Datenbank
      join(",", ((map {
                                    # TODO:XXX:FIXME: Linkto Bug!
         $self->determineCrossLink($_, $options->{crosslink}, $options->{crosstable}) ? "hidden" :
         # TODO:XXX:FIXME: Potentielles OR-Filterprobelm...
         (($_ eq $DELETEDCOLUMNNAME) && exists($filter->{$options->{table}.$TSEP.$DELETEDCOLUMNNAME})) ? "writeonly" :
         CGI::escape( $self->{gui}->getViewStatus({
            %$options,
            column => $_,
            table => $options->{table},
            targetself => $options->{curSession},
            action => $options->{action},
         }))
      } @{$options->{columns}}), map { ($loglevel <= $DEBUG) ? "readonly" : "hidden" } @{$options->{overridecolumns}})) # 6. Nicht Sichtbar oder nur lesbar?
   ];
};

sub onGetRowCount {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table}) {
      Log("onGetRowCount: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   $options->{start} = 0;
   $options->{end} = 0;
   $options->{rowsadded} = 0;
   $self->onGetLines($options);
}

sub handleCrossLink {
   my $self = shift;
   my $options = shift;
   my $where = shift;
   my $tablebackrefs = 0;

   if ($options->{crosslink})
   {
      if ($options->{crossid} && $options->{crosstable})
      {
         # TODO:XXX:FIXME: Hier wird derzeit nur ein Link verarbeitet, wenn mehrere von der gleichen Tabelle auf eine Tabelle zeigen werden diese nicht aktiv oder doppelt.
         my $linktabledef = $self->{dbm}->getTableDefiniton($options->{table});
         my $link = [grep { ($linktabledef->{columns}->{$_}->{linkto} &&
                            ($linktabledef->{columns}->{$_}->{linkto} eq $options->{crosstable})) } (keys %{$linktabledef->{columns}})];
         # TODO:XXX:FIXME: Die cross* auf Sonderzeichen ueberpruefen!!! SQL Injection!!!
         push(@$where, "(".$options->{table}.$TSEP.(scalar(@$link) ? $link->[0] : $options->{crosstable}."_".$self->{dbm}->getIdColumnName($options->{crosstable}))."=".$options->{crossid}.")");
      }
      else
      {
         $poe_kernel->yield(sendToQX => "showmessage ".CGI::escape( $self->{text}->{qx}->{internal_error} )." 400 200 ".CGI::escape( $self->{text}->{qx}->{no_crosslink_id} ));
         push(@$where, "(1 == 2)");
      }

      $tablebackrefs++;
   }

   return ($where, $tablebackrefs);
}

sub onGetLines {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{q} && $options->{curSession} && $options->{table} && $options->{connection} && ($options->{start} =~ /^\d+$/) && ($options->{end} =~ /^\d+$/) && ($options->{end} >= $options->{start})) {
      Log("onGetLines: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}." q=".$options->{"q"}.": !", $ERROR);
      return undef;
   }
   my $oid = $options->{oid};
   $options->{sortby} ||= '';
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $columns = [grep { $_ ne $self->{dbm}->getIdColumnName($options->{table}) } grep {
      my $status = $self->{gui}->getViewStatus({
         %$options,
         column => $_,
         table => $options->{table},
         targetself => $options->{curSession},
         action => $LISTACTION,
      }); ($status ne "hidden") #&& ($status ne "writeonly")
   } grep {
      $self->{dbm}->isMarked($options->{onlyWithMark}, $curtabledef->{columns}->{$_}->{marks})
   } hashKeysRightOrder($curtabledef->{columns})];
   unshift(@$columns, $self->{dbm}->getIdColumnName($options->{table})) if exists($curtabledef->{columns}->{$self->{dbm}->getIdColumnName($options->{table})});
   if (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $ACTIVESESSION, $options->{table}, $options->{$UNIQIDCOLUMNNAME}))) {
      $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape($self->{text}->{qx}->{internal_error})." 400 200 ".CGI::escape($self->{text}->{qx}->{permission_denied})."\n");
      return Log("DBManager: onGetLines: GET: ACCESS DENIED: ".$err->[0], $err->[1]);
   }
   my $ret = undef;
   my $count = ($options->{end}-$options->{start}+1)
      if (($options->{start} =~ m,^\d+$,) &&
          ($options->{end}   =~ m,^\d+$,) &&
          ($options->{end} > $options->{start}));
   my $db    = $self->{dbm}->getDBBackend($options->{table});
   my $where = $self->{dbm}->Where_Pre($options);
   my $tablebackrefs = 0;
   ($where, $tablebackrefs) = $self->handleCrossLink($options, $where);
   $tablebackrefs = 1 if ($curtabledef->{defaulttablebackrefs});
   $db->getDataSet({
      %$options,
      $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
      rows => $count,
      searchdef => $self->{dbm}->getFilter($options),
      wherePre => $where,
      tablebackrefs => $tablebackrefs,
      session => $options->{curSession},
      onlymax => $tablebackrefs,
      onDone => sub {
         my $options = shift;
         my $ret = shift;
         my $msg = shift;
         unless (ref($ret) eq "ARRAY") {
            Log("DBManager: onGetLines: GET ".$options->{table}." FAILED SQL Query failed.", $WARNING);
            $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape($self->{text}->{qx}->{internal_error})." 400 200 ".CGI::escape($self->{text}->{qx}->{failed}."\n"));
            return;         
         };
         # TODO/XXX/FIXME: Derzeit wird onGetLines einmal für getRowsCount und ein zweites mal für getRows abgefragt, das könnten wir cachen!
         $self->sendToQXForSession($options->{connection}->{sessionid} || 0, $msg)
            if ($msg);
         my $dbtype = $db->getDBType();
         if ($options->{end} > 0) {
            foreach my $dbline (@{$ret->[0]}) {
               my $line = "addrow ".$oid." ".($options->{ionum} ? $options->{ionum}." " : " ").join(",", map {
                  my $curcolumn = $_;
                  # TODO/FIXME/XXX: Qooxdoo mag hier kein HTMl.... irgendwie besser loesen als über hidebuttons!
                  $options->{curSession}->{hidebuttons}++;
                  # TODO/FIXME/XXX: Ausgabeformat beliebig ändern?
                  # TODO/FIXME/XXX: Hotfix fuer sayTRUST Logviewer: csv funktioniert mit Column_Handler nicht; es werden Spalten verschluckt.
                  CGI::escape((lc($dbtype) eq "csv") ? $dbline->{$options->{table}.$TSEP.$curcolumn} : $self->{gui}->Column_Handler($options->{curSession}, $options->{table}, $dbline, $curcolumn))
               } @$columns);
               $self->sendToQXForSession($options->{connection}->{sessionid} || 0, $line);
            }
         }
         #print "TABLE:".$options->{table}.":NUM:".$ret->[1].":".($options->{rowsadded}||0).":\n";
         $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addrowsdone ".$oid." ".($ret->[1]+($options->{rowsadded}||0)).($options->{ionum} ? " ".$options->{ionum} : ""));
      },
   });
}

sub createList {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{name} && $options->{connection}) {
      Log("Qooxdoo: createList: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   my $buttons = $self->getTableButtonsDef($options);
   if ($buttons->[0] eq "JSON") {
      $buttons->[1] = CGI::escape(JSON->new->allow_nonref->encode($buttons->[1]));
   }
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, 
     "createlist ".join(" ", (
      CGI::escape($options->{name}),  # 1. Interne Objekt ID
      $options->{table}, # 2. Tabelle
      @$buttons,
      CGI::escape($options->{hilfe} || ''),
      CGI::escape(($options->{crosslink} ? ",crosslink=".CGI::escape($options->{crosslink}).",crossid=".CGI::escape($options->{crossid}).",crosstable=".CGI::escape($options->{crosstable}) : '').($options->{urlappend} || ''))
   ))); # , $options->{connection}->{sessionid} || 0);
}

sub updateList {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   $options->{start} ||= 0;
   $options->{end} ||= 0;

   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{name} && ($options->{start} =~ /^\d+$/) && ((!$options->{end}) || (($options->{end} =~ /^\d+$/) && ($options->{end} >= $options->{start}))) && $options->{connection}) {
      Log("Qooxdoo: updateList: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.":name:".$options->{name}.": !", $ERROR);
      return undef;
   }
   
   $options->{sortby} ||= '';

   if (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $ACTIVESESSION, $options->{table}, $options->{$UNIQIDCOLUMNNAME})))
   {
      $self->sendToQXForSession(
          $options->{connection}->{sessionid} || 0,
          "showmessage "
            . CGI::escape( $self->{text}->{qx}->{internal_error} )
            . " 400 200 "
            . CGI::escape( $self->{text}->{qx}->{permission_denied} . "\n" )
      );
      Log("Qooxdoo: updateList: GET: ACCESS DENIED: ".$err->[0], $err->[1]);
      return undef;
   }

   my $ret = undef;
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $columns = [grep { $_ ne $self->{dbm}->getIdColumnName($options->{table}) } grep { my $status = $self->{gui}->getViewStatus({
      %$options,
      column => $_,
      targetself => $options->{curSession},
      action => $LISTACTION,
   }); ($status ne "hidden") #&& ($status ne "writeonly")
   } grep {
      $self->{dbm}->isMarked($options->{onlyWithMark}, $curtabledef->{columns}->{$_}->{marks})
   } hashKeysRightOrder($curtabledef->{columns})];

   my $count = $options->{end} ? ($options->{end}-$options->{start}+1) : undef;
   my $db = $self->{dbm}->getDBBackend($options->{table});
   my $where = $self->{dbm}->Where_Pre($options);
   my $tablebackrefs = 0;
   
   ($where, $tablebackrefs) = $self->handleCrossLink($options, $where);

   #Log("ROWS:".$options->{table}.":".$count.":".$options->{end}.":", $WARNING)
   #   if ($options->{table} =~ m,tagebuch,i);

   $tablebackrefs = 1 if ($curtabledef->{defaulttablebackrefs});

   unless (
       defined(
           $ret = $db->getDataSet(
               {
                   table             => $options->{table},
                   $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
                   skip              => $options->{start},
                   rows              => $count,
                   searchdef         => $self->{dbm}->getFilter($options),
                   sortby            => $options->{sortby},
                   wherePre          => $where,
                   tablebackrefs     => $tablebackrefs,
                   session           => $options->{curSession}
               }
           )
       )
       && ( ref($ret) eq "ARRAY" )
     )
   {
       Log(
           "Qooxdoo: updateList: GET "
             . $options->{table}
             . " FAILED SQL Query failed.",
           $WARNING
       );
       $self->sendToQXForSession(
           $options->{connection}->{sessionid} || 0,
           "showmessage "
             . CGI::escape( $self->{text}->{qx}->{internal_error} )
             . " 400 200 "
             . CGI::escape( $self->{text}->{qx}->{failed} . "\n" )
       );
       return undef;
   }

   $options->{tmpcounter} = 0;
   $options->{lastid} = 0;
   
   foreach my $dbline ( @{ $ret->[0] } )
   {
       if ( my $line = $self->updateListloopPre( $options, $curtabledef, $columns, $dbline ) )
       {
           $self->updateListloop( $options, $curtabledef, $columns, $dbline, $line );
       }
   }

   return $ret;
}

sub updateListloopPre {
   my $self = shift;
   my $options = shift;
   my $curtabledef = shift;
   my $columns = shift;
   my $dbline = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{name} && $options->{connection}) {
      Log("Qooxdoo: updateListloopPre: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   return undef if ($options->{folderid} &&
            $curtabledef->{foldertable} &&
            $dbline->{$options->{table}.$TSEP.$curtabledef->{foldertable}."_".$self->{dbm}->getIdColumnName($curtabledef->{foldertable})} &&
           ($dbline->{$options->{table}.$TSEP.$curtabledef->{foldertable}."_".$self->{dbm}->getIdColumnName($curtabledef->{foldertable})} ne $options->{folderid}));
   if ($options->{lastid} && ($options->{lastid} eq $dbline->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})})) {
      Log("Qooxdoo: updateListloopPre: More than one line for one id! Skipping the duplicated ones.", $WARNING);
      return undef;
   }
   $options->{lastid} = $dbline->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})} || 0;
   my $line = ($curtabledef->{listtextcolumn} &&
         $dbline->{$options->{table}.$TSEP.$curtabledef->{listtextcolumn}}) ?
         $dbline->{$options->{table}.$TSEP.$curtabledef->{listtextcolumn}} :
      join(defined($curtabledef->{listjoin}) ? $curtabledef->{listjoin} : " | ", map {
         $self->{gui}->Column_Handler($options->{curSession}, $options->{table}, $dbline, $_)
         # TODO/FIXME/XXX: Vermutlich kann das hier ne Funktion aus ABDGUI::GUI besser? getAffectedColumns oder so?
      } grep {
         $self->determineCrossLink($_, $options->{crosslink}, $options->{crosstable}) ? 0 :
         (exists($curtabledef->{columns}->{$_}) &&
          exists($curtabledef->{columns}->{$_}->{showInSelect}) &&
                 $curtabledef->{columns}->{$_}->{showInSelect}) &&
        !(exists($curtabledef->{listimagecolumn}) &&
                 $curtabledef->{listimagecolumn}  &&
          ($_ eq $curtabledef->{listimagecolumn})) } @$columns);
   return $line ? $line : $options->{noidefault} ? undef : $dbline->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})};
}

sub updateListloop {
   my $self = shift;
   my $options = shift;
   my $curtabledef = shift;
   my $columns = shift;
   my $dbline = shift;
   my $line = shift;
   my $moreparams = shift;
   my $curid = $options->{name}."_".($dbline->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})} || $options->{tmpcounter}++);
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{name} && $options->{connection}) {
      Log("Qooxdoo: updateListloop: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createlistitem ".CGI::escape($curid)." ".CGI::escape($dbline->{$options->{table}.$TSEP.$self->{dbm}->getIdColumnName($options->{table})})." ".CGI::escape($line)." ".CGI::escape(
      ($curtabledef->{listimagecolumn} && $dbline->{$curtabledef->{listimagecolumn}}) ?
         $dbline->{$curtabledef->{listimagecolumn}} :
                   $curtabledef->{listimagedefault} ?
                   $curtabledef->{listimagedefault} : ''
   ));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($options->{name})." ".CGI::escape($curid));
}

sub createTable {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{name} && $options->{connection}) {
      Log("onShow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $columns = [
      grep {
         $_ ne $self->{dbm}->getIdColumnName($options->{table})
      } grep {
         my $status = $self->{gui}->getViewStatus({
            %$options,
            column => $_,
            table => $options->{table},
            targetself => $options->{curSession},
            action => $LISTACTION,
         });
         ($status ne "hidden") #&& ($status ne "writeonly")
      } grep {
         $self->{dbm}->isMarked($options->{onlyWithMark}, $curtabledef->{columns}->{$_}->{marks})
      } hashKeysRightOrder($curtabledef->{columns})
   ];
   my $buttons = $self->getTableButtonsDef($options);
   $buttons->[1] = CGI::escape(JSON->new->allow_nonref->encode($buttons->[1]))
      if ($buttons->[0] eq "JSON");
   unshift(@$columns, $self->{dbm}->getIdColumnName($options->{table})) if (exists($curtabledef->{columns}->{$self->{dbm}->getIdColumnName($options->{table})}));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createtable ".join(" ", (
      CGI::escape($options->{name}),  # 1. Interne Objekt ID
      @{$self->getBasicDataDefine({
         %$options,
         crosslink => $options->{crosslink},
         crosstable => $options->{crosstable},
         table => $options->{table},
         columns => $columns,
         curSession => $options->{curSession},
         links => {},
         action => $LISTACTION,
      })},
      #(($curtabledef->{readonly} || $options->{nobuttons}) ? "readonly" : ''),
      join(",", map { (exists($curtabledef->{columns}->{$_}->{qxdefaultsize}) && 
                      defined($curtabledef->{columns}->{$_}->{qxdefaultsize}) &&
                              $curtabledef->{columns}->{$_}->{qxdefaultsize}) ?
                              $curtabledef->{columns}->{$_}->{qxdefaultsize} : '' } @$columns),
      join(",", map { (exists($curtabledef->{columns}->{$_}->{qxminsize}) && 
                      defined($curtabledef->{columns}->{$_}->{qxminsize}) &&
                              $curtabledef->{columns}->{$_}->{qxminsize}) ?
                              $curtabledef->{columns}->{$_}->{qxminsize} : '' } @$columns),
      join(",", map { (exists($curtabledef->{columns}->{$_}->{qxmaxsize}) && 
                      defined($curtabledef->{columns}->{$_}->{qxmaxsize}) &&
                              $curtabledef->{columns}->{$_}->{qxmaxsize}) ?
                              $curtabledef->{columns}->{$_}->{qxmaxsize} : '' } @$columns),
      @$buttons,
      CGI::escape($options->{hilfe} || ''), # 9. Hilfetext
      CGI::escape(($options->{crosslink} ? ",crosslink=".CGI::escape($options->{crosslink}).",crossid=".CGI::escape($options->{crossid}).",crosstable=".CGI::escape($options->{crosstable}) : '').($options->{urlappend} || '')), # 10. URLAppend
      CGI::escape($curtabledef->{qxrowheight} || ""),
      CGI::escape($self->{dbm}->getIdColumnName($options->{table}) || ""),
   ))); # , $options->{connection}->{sessionid} || 0);
   #print "Affected columns: ".join(",", @$columns).":\n";
}

sub doCSVonShow {
   my $self = shift;
   my $options = shift;
   my $suffix = shift;
   my $moreparams = shift;
   my $ret = '';
   unless ((!$moreparams) && $options->{curSession} && $options->{table}) {
      Log("doCSVonShow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   my $db = $self->{dbm}->getDBBackend($options->{table});
   if ($db->{config}->{DB}->{type} =~ /^CSV$/i) {
      my $files = $db->getAvailableDynTableFiles($options->{table});
      if (ref($files) eq "HASH") {
         my $active = $db->getCurrentDynTableFile($options->{table});
         my $selectablefiles = $self->{dbm}->filterAssignFiles({
            table => $options->{table},
            files => $files,
            active => $active,
            session => $options->{curSession}
         });
         my @files = keys %{$selectablefiles->{files}};
         my $foundactive = 0;
         foreach my $file (@files) {
            $foundactive++
               if ($active eq $file)
         }
         $ret .= "\n" if $ret;
         $ret .= "destroy ".$options->{table}."_".$suffix."_data_text";
         if (my $out = $self->{gui}->getSelectionOfDynDBFiles({}, {
            files => [@files],
            mtime => [map { $files->{$_}->[9] } @files],
            active => $active,
            table => $options->{table},
            db => $db->{config}->{DB},
            parent => $self,
            curSession => $options->{curSession},
            filter => $self->{dbm}->getFilter($options),
         })) {
            #$poe_kernel->yield(sendToQX => "showmessage ".CGI::escape("LENGTH")." 400 100 ".CGI::escape("Length: ".$out.":".length($out)));
            #$out .= "LENGTH:".$out.":".length($out)."<br>\n";
            $out =
                "<FORM method='POST' name='myform' action='"
              . $options->{"q"}->url( -relative => 1 ) . "'>\n"
              . $out;
            $out = "<nobr>&nbsp;<select name='filename' id='filename' onChange='var http = false;
               if(navigator.appName == ".chr(34)."Microsoft Internet Explorer".chr(34).") {
                  http = new ActiveXObject(".chr(34)."Microsoft.XMLHTTP".chr(34).");
               } else {
                  http = new XMLHttpRequest();
               }               
               http.open(".chr(34)."GET".chr(34).", ".chr(34)."/ajax?nocache=".rand(999999999999)."&table=".$options->{table}."&job=setfile&sessionid=".$options->{curSession}->{sessionid}."&filename=".chr(34)." + this.options[this.selectedIndex].value);
               http.send(null);'>\n".$out;
            $out .= "</form>\n";
            $ret .= "\n" if $ret;
            $ret .= "createtext ".$options->{table}."_".$suffix."_data_text 1 ".CGI::escape($out);
            $ret .= "\n" if $ret;
            $ret .= "addobject ".$options->{table}."_".$suffix." ".$options->{table}."_".$suffix."_data_text ".$options->{table}."_".$suffix."_data";
         } else {
            $ret = "destroy ".$options->{table}."_".$suffix."\n";
            $ret .=
                "showmessage "
              . CGI::escape( $self->{text}->{qx}->{no_log_data} )
              . " 400 100 "
              . CGI::escape( $self->{text}->{qx}->{no_log_data} );
            return $ret;
         }

         if (($foundactive == 0) && scalar(@files))
         {
            $db->assignFileToDynTable($options->{table}, $files[0]);
         }

      }
      else
      {    
         Log("Qooxdoo: onShow: getAvailableDynTableFiles: did not return ARRAY but: '".ref($files)."'", $WARNING);
         $ret = "destroy " . $options->{table} . "_" . $suffix . "\n";
         $ret .=
             "showmessage "
           . CGI::escape( $self->{text}->{qx}->{no_log_data} )
           . " 400 100 "
           . CGI::escape( $self->{text}->{qx}->{no_log_data} );
         return $ret;
      }
   }

   return $ret;
}

sub onShow {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{connection})
   {
      Log("onShow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.":connection:".$options->{connection}.": !", $ERROR);
      return undef;
   }
   
   my $suffix = "show";
   my $subtext = $self->doCSVonShow($options, $suffix);
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});

   $self->sendToQXForSession( $options->{connection}->{sessionid} || 0, "destroy " . $options->{table} . "_" . $suffix . "_data" );
   $self->sendToQXForSession(
       $options->{connection}->{sessionid} || 0,
       "destroy " . $options->{table} . "_" . $suffix
   );
   $self->sendToQXForSession(
       $options->{connection}->{sessionid} || 0,
       "createwin "
         . $options->{table} . "_"
         . $suffix . " "
         . ( $curtabledef->{qxwidth}  || $qxwidth ) . " "
         . ( $curtabledef->{qxheight} || $qxheight ) . " "
         . CGI::escape(
                $options->{windowtitle}
             || $options->{title}
             || $curtabledef->{label}
             || $options->{table}
         )
         . " "
         . CGI::escape( $curtabledef->{icon} || '' )
   );

   $self->createTable({
      %$options,
      name  => $options->{table}."_".$suffix."_data",
      hilfe => $curtabledef->{infotext},
   });
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($options->{table}."_".$suffix)." ".CGI::escape($options->{table}."_".$suffix."_data")); 
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "open ".$options->{table}."_".$suffix." 1");
   #$poe_kernel->yield(sendToQX => "maximize ".$options->{table}."_".$suffix." 1");
   #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, $subtext) if $subtext;
}

sub onShowList {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{connection}) {
      Log("onShow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   my $suffix = "showlist";
   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "destroy ".CGI::escape($options->{table}."_".$suffix));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "destroy ".CGI::escape($options->{table}."_".$suffix."_data"));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createwin ".CGI::escape($options->{table}."_".$suffix)." ".($curtabledef->{qxwidth} || $qxwidth)." ".($curtabledef->{qxheight} || $qxheight)." ".CGI::escape($curtabledef->{label} || $options->{table})." ".CGI::escape($curtabledef->{icon} ? $curtabledef->{icon} : '')." ".CGI::escape($options->{layout} || ""));
   $self->createList({
      %$options,
      name  => $options->{table}."_".$suffix."_data",
      hilfe => $curtabledef->{infotext},
   });
   $self->onUpdateList($options);
   #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createtext ".CGI::escape($options->{table}."_".$suffix."_text")." rich ".CGI::escape("blah<br>blah<br>blah"));
   #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($options->{table}."_".$suffix)." ".CGI::escape($options->{table}."_".$suffix."_text"));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($options->{table}."_".$suffix)." ".CGI::escape($options->{table}."_".$suffix."_data"));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "open ".CGI::escape($options->{table}."_".$suffix)." 1");
   #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "maximize ".CGI::escape($options->{table}."_".$suffix)." 1");
   return 0;
}

sub onUpdateList {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{connection}) {
      Log("onShow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   my $suffix = "showlist";
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "clearlist ".CGI::escape($options->{name} || $options->{table}."_".$suffix."_data"));
   $self->updateList({
      %$options,
      name       => $options->{name} || $options->{table}."_".$suffix."_data",
      start      => 0,
   });   
}

sub getTableButtonsDef
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;
    
    unless ( ( !$moreparams ) && $options->{table} && $options->{curSession} ) {
        Log(
            "onHTMLPreview: Missing parameters: table:"
              . $options->{table}
              . ":curSession:"
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }

    my $curtabledef = $self->{dbm}->getTableDefiniton( $options->{table} );

    if ( $self->{dbm}->{config}->{nojson} )
    {
        if ( $curtabledef->{readonly} || $options->{nobuttons} )
        {
            return [ "", "", "", "" ];
        }

        
        return [
            CGI::escape( $self->{text}->{qx}->{new} ) . ","
              . CGI::escape( $self->{text}->{qx}->{edit} ) . ","
              . CGI::escape( $self->{text}->{qx}->{delete} ) . ","
              . CGI::escape( $self->{text}->{qx}->{filter} ),
            CGI::escape("resource/qx/icon/Tango/32/actions/list-add.png") . ","
              . CGI::escape("/bilder/edit.png") . ","
              . CGI::escape("resource/qx/icon/Tango/32/actions/list-remove.png")
              . ","
              . CGI::escape(
                "resource/qx/icon/Tango/32/actions/system-search.png"),
            CGI::escape("neweditentry") . ","
              . CGI::escape("neweditentry") . ","
              . CGI::escape("delrow") . ","
              . CGI::escape("filter"),
            CGI::escape("table") . ","
              . CGI::escape("row") . ","
              . CGI::escape("row") . ","
              . CGI::escape("table")
        ];
    }

    my $return = [];

    unless (( $curtabledef->{readonly}
        || $options->{nobuttons} ))
    { 
        push(
        @$return,
        (
            {
                name  => "new",
                label => $self->{text}->{qx}->{new} ,
                image => "resource/qx/icon/Tango/"
                  . ( $options->{smallbuttons} ? "16" : "32" )
                  . "/actions/list-add.png",
                action => "neweditentry",
                bindto => "table",
            },
            {
                name  => "edit",
                label => $self->{text}->{qx}->{edit} ,
                image => ( $options->{smallbuttons} ? "" : "/bilder/edit.png" ),
                action => "neweditentry",
                bindto => "row",
            },
            {
                name  => "del",
                label => $self->{text}->{qx}->{delete} ,
                image => "resource/qx/icon/Tango/"
                  . ( $options->{smallbuttons} ? "16" : "32" )
                  . "/actions/list-remove.png",
                action => "delrow",
                bindto => "row",
            }
        )
      );
    }

    unless ($options->{nobuttons})
    {
        push(
            @$return,
            {
                name  => "filter",
                label => $self->{text}->{qx}->{filter} ,
                image => "resource/qx/icon/Tango/"
                  . ( $options->{smallbuttons} ? "16" : "32" )
                  . "/actions/system-search.png",
                action => "filter",
                bindto => "table",
            }
        );
    }

    return [ "JSON", $return ];
}

sub onHTMLPreview
{
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   unless ((!$moreparams) && $options->{curSession} && $options->{table} && defined($options->{value}) && $options->{column}) {
      Log("onHTMLPreview: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return 0;
   }

   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
   my $suffix = "htmlpreview";

   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createwin"." ".
                                   $options->{table}."_".$options->{column}."_".$suffix." ".
                                   ($curtabledef->{qxeditwidth} || $qxwidth)." ".
                                   ($curtabledef->{qxeditheight} || $qxheight)." ".
                                   CGI::escape( $self->{text}->{qx}->{preview_of} .
                                      (exists($curtabledef->{columns}->{$options->{column}}) &&
                                      defined($curtabledef->{columns}->{$options->{column}}) &&
                                              $curtabledef->{columns}->{$options->{column}}->{label} ? 
                                              $curtabledef->{columns}->{$options->{column}}->{label} :
                                                                        $options->{column})
                                          . ($options->{$UNIQIDCOLUMNNAME} ?  $self->{text}->{qx}->{of_entry} . $options->{$UNIQIDCOLUMNNAME} : $self->{text}->{qx}->{new_entry} ).
                                      $self->{text}->{qx}->{in} . ($curtabledef->{label} || $options->{table})) . " " . 
                                   CGI::escape($curtabledef->{icon}));

   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "open ".$options->{table}."_".$options->{column}."_".$suffix." 1");

   Log("onHTMLPreview: overwriting existing htmlpreview!", $ERROR)
      if (exists($options->{curSession}->{cached}));

   $options->{curSession}->{cached} = htmlUnEscape(CGI::unescape($options->{value}));
   $options->{curSession}->{cached} = $self->{gui}->replacer($options->{curSession}->{cached}, $options->{curset})
      if $options->{curset};

   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createiframe ".$options->{table}."_".$options->{column}."_".$suffix."_iframe"." ".CGI::escape("/ajax?nocache=".rand(999999999999)."&job=getcached&sessionid=".$options->{curSession}->{sessionid}));
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".$options->{table}."_".$options->{column}."_".$suffix." ".$options->{table}."_".$options->{column}."_".$suffix."_iframe");

   $self->sendToQXForSession(
       $options->{connection}->{sessionid} || 0,
       "createbutton "
         . CGI::escape(
           $options->{table} . "_" . $options->{column} . "_" . $suffix . "_button"
         )
         . " "
         . CGI::escape( $self->{text}->{qx}->{close} ) . " "
         . CGI::escape("resource/qx/icon/Tango/32/actions/dialog-close.png") . " "
         . CGI::escape(
               "job=closeobject,oid="
             . $options->{table} . "_"
             . $options->{column} . "_"
             . $suffix
         )
   );

   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($options->{table}."_".$options->{column}."_".$suffix)." ".CGI::escape($options->{table}."_".$options->{column}."_".$suffix."_button")."\n"); 
   #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "maximize ".$options->{table}."_".$options->{column}."_".$suffix." 1");
   $self->sendToQXForSession($options->{connection}->{sessionid} || 0, "modal ".$options->{table}."_".$options->{column}."_".$suffix." 1");

   return 1;
}

sub onCloseObject
{
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   
   unless ((!$moreparams) && $options->{curSession} && $options->{oid})
   {
      Log("onCloseObject: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   
   $poe_kernel->yield(sendToQX => "destroy ".CGI::escape($options->{oid}));
}


sub onSaveEditEntry
{
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{"q"} && $options->{oid} && $options->{connection}) {
      Log("onSaveEditEntry: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }

   my $id = $options->{"q"}->param($UNIQIDCOLUMNNAME) || $options->{"q"}->param($self->{dbm}->getIdColumnName($options->{table}));

   $self->{dbm}->NewUpdateData({
      %$options,
      cmd => ($id ? "UPDATE" : "NEW"),
      nodeleted => 1,
      columns => $options->{columns},
      uniqid => scalar($id) || '',
      qxself => $self,

      onDone => sub {
         my $ret = shift;
         my $options = shift;
         my $self = shift;
         # TODO:FIXME:XXX: Das sollte an alle anderen user auch gehen, die auf der tabelle sind!
         # TODO:FIXME:XXX: ID sollte vom Rückgabewert des NewUpdateData genommen werden, und nicht vom CGI Objekt!
         if (defined($ret))
         {
            my $curid = $options->{"q"}->param($UNIQIDCOLUMNNAME) || $options->{"q"}->param($self->getIdColumnName($options->{table}));
            $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "updaterow ".CGI::escape($options->{table})." ".CGI::escape($curid||""));
            if ($ret =~ /^\d+$/)
            {
               if (($options->{qxself}->{dbm}->{config}->{autocloseeditwindow} || $options->{close}) && $options->{"q"}->param("wid") && !$options->{noclose})
               {
                  $options->{qxself}->onCloseObject({
                     "curSession" => $options->{curSession},
                     "oid" => CGI::escape($options->{"q"}->param("wid"))
                  }) ;
               }
               else {
                  $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "destroy ".CGI::escape($options->{table}."_edit"));
                  $options->{qxself}->onNewEditEntry({
                     %$options,
                     $UNIQIDCOLUMNNAME => $ret,
                  });
               }
               $options->{qxself}->afterNewUpdate($options, $options->{columns}, $ret);
            } elsif($ret) {
               $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "unlock ".CGI::escape($options->{"q"}->param("oid")));
               $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape( $self->{text}->{qx}->{internal_error} ) . " " . ($ret ? ((length($ret)+15) * 7) : 400)." 100 ".CGI::escape($ret));
            } else {
               $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "unlock ".CGI::escape($options->{"q"}->param("oid")));
               $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape( $self->{text}->{qx}->{internal_error} )." 500 100 ".CGI::escape($ret ? "onSaveEditEntry: " . $ret : $self->{text}->{qx}->{onSaveEditEntry_error} ));
            }
         } else {
            $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "unlock ".CGI::escape($options->{"q"}->param("oid")));
            $options->{qxself}->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape( $self->{text}->{qx}->{internal_error} )." 400 100 ".CGI::escape( $self->{text}->{qx}->{onSaveEditEntry_error} ));
         }
         
         return $ret;
      }
   });
}

sub afterNewUpdate {
   my $self = shift;
   my $options = shift;
   my $columns = shift;
   my $id = shift;
   if (my $addAndSelect = $options->{"q"}->param("AddAndSelectOID")) {
      my $table = $options->{"q"}->param("AddAndSelectTable");
      my $column = $options->{"q"}->param("AddAndSelectColumn");
      my $curtable = undef;
      my $basetabledef = $self->{dbm}->getTableDefiniton($table);      
      if ($basetabledef->{columns}->{$column} && $basetabledef->{columns}->{$column}->{linkto}) {
         $curtable = $basetabledef->{columns}->{$column}->{linkto};
      } elsif ($self->{dbm}->{config}->{oldlinklogic} && ($column =~ m,^(.+)_$UNIQIDCOLUMNNAME$,)) {
         $curtable = $1;
      }
      my $value = "".($curtable ? $self->{gui}->getValueForTable($curtable, $columns) : undef) || $self->{text}->{qx}->{created_entry} ;
      my $tmp = "addtoeditlist ".CGI::escape($addAndSelect)." ".CGI::escape($column)." ".CGI::escape($value)." ".CGI::escape($id);
      #Log($tmp, $WARNING);
      $self->sendToQXForSession($options->{connection}->{sessionid} || 0, $tmp);
      $tmp = "selectoneditlist ".CGI::escape($addAndSelect)." ".CGI::escape($column)." ".CGI::escape($id);
      #Log($tmp, $WARNING);
      $self->sendToQXForSession($options->{connection}->{sessionid} || 0, $tmp);
   }
}

sub onFilter {
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams )
        && $options->{curSession}
        && $options->{table}
        && $options->{oid} )
    {
        Log(
            "Qooxdoo: onFilter: Missing parameters: table:"
              . $options->{table}
              . ":curSession:"
              . $options->{curSession} . ":oid:"
              . $options->{oid} . " !",
            $ERROR
        );
        return undef;
    }
    
    my $suffix = "show";

    if (defined(my $err = $self->{dbm}->checkRights(
                $options->{curSession},
                $ACTIVESESSION, $options->{table}
            )))
    {
        $poe_kernel->yield( sendToQX => "showmessage "
              . CGI::escape( $self->{text}->{qx}->{internal_error} )
              . " 400 200 "
              . CGI::escape( $self->{text}->{qx}->{permission_denied} ) );
        Log( "Qooxdoo: onFilter: GET: ACCESS DENIED: " . $err->[0], $err->[1] );
        return undef;
    }

    my $curtabledef = $self->{dbm}->getTableDefiniton( $options->{table} );

    $poe_kernel->yield( sendToQX => "destroy "
          . CGI::escape( $options->{oid} . "_filter_iframe" ) );
    $poe_kernel->yield(
            sendToQX => "createwin "
          . CGI::escape( $options->{oid} . "_filter" ) . " "
          . (
            $curtabledef->{qxfilterwidth}
              || 500    # || $curtabledef->{qxeditwidth} || $qxwidth
          )
          . " "
          . (
                 $curtabledef->{qxfilterwidth}
              || $curtabledef->{qxeditheight}
              || $qxheight
          )
          . " "
          . CGI::escape(
            $self->{text}->{qx}->{filter_in} . ( $curtabledef->{label} || $options->{table} )
          )
          . " "
          . ( CGI::escape( $curtabledef->{icon} || '' ) )
    );
    $poe_kernel->yield(
            sendToQX => "createiframe "
          . CGI::escape( $options->{oid} . "_filter_iframe" ) . " "
          . CGI::escape(
                "/ajax?nocache="
              . rand(999999999999)
              . "&job=filterhtml&table="
              . $options->{table}
              . "&sessionid="
              . $options->{curSession}->{sessionid} . "&oid="
              . $options->{oid}
              . "_filter_iframe"
          )
    );

    $poe_kernel->yield( sendToQX => "createtoolbar "
          . CGI::escape( $options->{oid} . "_filter_toolbar" ) );

    foreach my $curButton (
        {
            id      => $options->{oid} . "_filter_toolbar_add",
            job     => "createtoolbarbutton",
            label   => $self->{text}->{qx}->{filter_criterion} ,
            image   => "resource/qx/icon/Tango/16/actions/list-add.png",
            popupid => $options->{oid} . "_filter_popup",
            action  => "job=filterselecttable,table="
              . $options->{table} . ",oid="
              . $options->{oid}
              . ",popupid="
              . $options->{oid}
              . "_filter_popup",
            popupwidth  => 300,
            popupheight => 300,

            #popupnoshow => 1,
            #popuppadding => 5,
            menutype => "popup",
        },
        {
            id      => $options->{oid} . "_filter_toolbar_open",
            job     => "createtoolbarbutton",
            label   => $self->{text}->{qx}->{load} ,
            image   => "resource/qx/icon/Tango/16/actions/document-open.png",
            popupid => $options->{oid} . "_filteropen",
            action  => "job=filteropen,table="
              . $options->{table} . ",oid="
              . $options->{oid}
              . ",popupid="
              . $options->{oid}
              . "_filteropen",
            popupwidth  => 300,
            popupheight => 300,
            menutype    => "popup",
        },
        {
            id      => $options->{oid} . "_filter_toolbar_save",
            job     => "createtoolbarbutton",
            label   => $self->{text}->{qx}->{save} ,
            image   => "resource/qx/icon/Tango/16/actions/document-save.png",
            popupid => $options->{oid} . "_filtersave",
            action  => "job=filtersave,table="
              . $options->{table} . ",oid="
              . $options->{oid}
              . ",popupid="
              . $options->{oid}
              . "_filtersave",
            popupwidth  => 300,
            popupheight => 300,
            menutype    => "popup",
        }
      )
    {
        if ( $self->{dbm}->{config}->{nojson} ) {
            $poe_kernel->yield( sendToQX => $curButton->{job} . " "
                  . CGI::escape( $curButton->{id} ) . " "
                  . CGI::escape( $curButton->{label} ) . " "
                  . CGI::escape( $curButton->{image} ) . " "
                  . $curButton->{action} );
        }
        else {
            $poe_kernel->yield( sendToQX => "JSON "
                  . CGI::escape( JSON->new->allow_nonref->encode($curButton) )
            );
        }
        $poe_kernel->yield( sendToQX => "addobject "
              . CGI::escape( $options->{oid} . "_filter_toolbar" ) . " "
              . CGI::escape( $curButton->{id} ) );
    }

    $poe_kernel->yield( sendToQX => "addobject "
          . CGI::escape( $options->{oid} . "_filter" ) . " "
          . CGI::escape( $options->{oid} . "_filter_toolbar" ) );
    $poe_kernel->yield( sendToQX => "addobject "
          . CGI::escape( $options->{oid} . "_filter" ) . " "
          . CGI::escape( $options->{oid} . "_filter_iframe" ) );
    $poe_kernel->yield(
        sendToQX => "open " . CGI::escape( $options->{oid} . "_filter" ) );
}

sub getFilterActionForm {
   my $self = shift;
   my $options = shift;
   my $job = shift;
   my $curfilter = shift;
   my $value = shift;
   my $tmp = "";
   $tmp .= "<form method=post action='/ajax'>";
   $tmp .="<input type=hidden name=nocache value='".rand(999999999999)."'>\n";
   $tmp .="<input type=hidden name=sessionid value='".$options->{curSession}->{sessionid}."'>\n";
   $tmp .="<input type=hidden name=oid value='".$options->{oid}."'>\n";
   $tmp .="<input type=hidden name=job value='filterhtml'>\n";
   $tmp .="<input type=hidden name=table value='".$options->{table}."'>\n";
   $tmp .="<input type=hidden name=filterjob value='".$job."'>\n";
   $tmp .="<input type=hidden name=filtername value='".$curfilter."'>\n";
   $tmp .="<input type=hidden name=filtervalue value='".$value."'>\n"
      if $value;
   return $tmp;
}

sub getFilterActionLink {
    my $self      = shift;
    my $options   = shift;
    my $job       = shift;
    my $curfilter = shift;
    my $value     = shift;

    return
        "<a href='/ajax?nocache="
      . rand(999999999999)
      . "&filterjob="
      . $job
      . "&filtername="
      . $curfilter
      . ( $value ? "&filtervalue=" . $value : "" )
      . "&job=filterhtml&table="
      . $options->{table} . "&oid="
      . $options->{oid}
      . "&sessionid="
      . $options->{curSession}->{sessionid} . "'>";
}

sub onFilterHTML {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{oid} && $options->{response}) {
      Log("Qooxdoo: onFilterHTML: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.":oid:".$options->{oid}." !", $ERROR);
      return undef;
   }

   my $suffix = "show";

   if (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $ACTIVESESSION, $options->{table})))
   {
      $poe_kernel->yield(sendToQX => "showmessage ".CGI::escape( $self->{text}->{qx}->{internal_error} )." 400 200 ".CGI::escape( $self->{text}->{qx}->{permission_denied} . "\n" ));
      Log("Qooxdoo: onFilterHTML: GET: ACCESS DENIED: ".$err->[0], $err->[1]);
      return undef;
   }

   $options->{response}->code(RC_OK);
   $options->{response}->content_type("text/html; charset=UTF-8");
   #${$options->{content}} .= "Hello world ".time().".<br><br>";
   #$options->{curSession}->{filtergui} ||= [
   #   { table  => "Test",
   #     column => "lala",
   #   },
   #];
   #foreach my $curfilter (@{$options->{curSession}->{filtergui}}) {
   #   ${$options->{content}} .= "FILTER: ".$curfilter->{table}.".".$curfilter->{column}."<br>\n";
   #}
   my $filter = $self->{dbm}->getFilter({
      curSession => $options->{curSession},
      table => $options->{table},
   });
   # TODO:XXX:FIXME: Hier werden die Benutzereingaben ungefiltert übernommen!!!!
   my $filterjob = $options->{q}->param("filterjob") || "";
   my $filtername = $options->{q}->param("filtername");
   my $filtervalue = $options->{q}->param("filtervalue");
   my $doFilterUpdate = 0;
   if ($filterjob eq "deletefilter") {
      if ($filtername) {
         delete($filter->{$filtername});
         delete($filter->{$filtername."_begin"});
         delete($filter->{$filtername."_end"});
         $doFilterUpdate++;
      }
   } elsif($filterjob eq "addtoarray") {
      if ($filtervalue &&
          exists($filter->{$filtername}) &&
            (ref($filter->{$filtername}) eq "ARRAY")) {
         push(@{$filter->{$filtername}}, $filtervalue);
         $doFilterUpdate++;
      }
   } elsif($filterjob eq "deletearrayentry") {
      if ($filtervalue &&
          exists($filter->{$filtername}) &&
            (ref($filter->{$filtername}) eq "ARRAY")) {
         $filter->{$filtername} = [grep { $_ ne $filtervalue } @{$filter->{$filtername}}];
         $doFilterUpdate++;
      }
   } elsif($filterjob eq "setfilterval") {
      if ($filtervalue) {
         $filter->{$filtername} = $filtervalue;
         $doFilterUpdate++;
      }
   } elsif($filterjob eq "deletefilterval") {
      $filter->{$filtername} = undef;
      $doFilterUpdate++;
   } elsif($filterjob eq "setfilterdatebegin") {
      #print "XXX:".$filtername.":".$filtervalue.":\n";
      my $values = $self->{gui}->parseDateDefintion($filtervalue, $options->{q});
      $filter->{$filtername."_begin"} = $values->[0];
      $doFilterUpdate++;
   } elsif($filterjob eq "setfilterdateend") {
      my $values = $self->{gui}->parseDateDefintion($filtervalue, $options->{q});
      $filter->{$filtername."_end"} = $values->[1];
      $doFilterUpdate++;
   } elsif($filterjob eq "deletefilterdatebegin") {
      delete $filter->{$filtername."_begin"};
      $doFilterUpdate++;
   } elsif($filterjob eq "deletefilterdateend") {
      delete $filter->{$filtername."_end"};
      $doFilterUpdate++;
   }
   if ($doFilterUpdate) {
      $self->{dbm}->setFilter({
         curSession => $options->{curSession},
         table => $options->{table},
         filter => $filter,
      });
      $poe_kernel->yield(sendToQX => "updaterow ".CGI::escape($options->{table})." ");
   }
   ${$options->{content}} .= "<font face='Arial'><br>";
   if (scalar(keys %$filter))
   {
      my $showtype = 0;

      ${$options->{content}} .= "<table width=100%><tr><td></td><td><b>" . $self->{text}->{qx}->{filter_criterion}
                      . "</b></td><td><b>" . $self->{text}->{qx}->{table} . "</b></td>"
                      . ($showtype ? "<td><center><b>" . $self->{text}->{qx}->{filter_criterion} . "</b></center></td>" : "")."</tr>";

      foreach my $curfilter ( sort {  (     (($b =~ m,^$options->{table},) ? 1 : 0)
                                        <=> (($a =~ m,^$options->{table},) ? 1 : 0))
                                      ||  $a cmp $b } keys %$filter
                            )
      {
         next if scalar(grep { ($curfilter eq $_."_end") || ($curfilter eq $_."_begin") } keys %$filter);

         ${$options->{content}} .= "<tr><td colspan=".(3 + ($showtype ? 1 : 0))."><font size=1>&nbsp;</font></td></tr>";

         ${ $options->{content} } .=
             "<tr><td width=1%><center><a href='/ajax?nocache="
           . rand(999999999999)
           . "&filterjob=deletefilter&filtername="
           . $curfilter
           . "&job=filterhtml&table="
           . $options->{table} . "&oid="
           . $options->{oid}
           . "_filter_iframe&sessionid="
           . $options->{curSession}->{sessionid}
           . "'><img src='resource/qx/icon/Tango/16/actions/list-remove.png' alt='-' align=absmiddle></a></center></td>";

         if ($curfilter =~ m,^([^\.]+)\.([^\.]+)$,)
         {
            my $table = $1;
            my $column = $2;
            my $tablelabel = $table;
            my $columntype = "";
            my $columnlabel = $column;

            if (my $curtabledef = $self->{dbm}->getTableDefiniton($table))
            {
               $tablelabel = $curtabledef->{label}
                  if $curtabledef->{label};
               
               $columnlabel = $curtabledef->{columns}->{$column}->{label}
                           if $curtabledef->{columns}->{$column}->{label};

               $columntype  = $curtabledef->{columns}->{$column}->{type}
                           if $curtabledef->{columns}->{$column}->{type};
            }

            if ($column eq $self->{dbm}->getIdColumnName($table))
            {
               $columnlabel = $tablelabel;
               $tablelabel = "";
            }

            ${$options->{content}} .= "<td";

            my $doTableColumn = (($table ne $options->{table}) && $tablelabel) ? 1 : 0;
            ${$options->{content}} .= " colspan=2"
               if !$doTableColumn;
            ${$options->{content}} .= "><img src='resource/qx/icon/Tango/16/".(($columntype eq $self->{dbm}->getIdColumnName($table)) ? "places/folder" : "mimetypes/office-document").".png' align=absmiddle> ".encode("utf8", $columnlabel);
            if ($doTableColumn) {
               ${$options->{content}} .= "</td><td>";
               ${$options->{content}} .= "<nobr><img src='resource/qx/icon/Tango/16/places/folder.png' align=absmiddle><font size=2> ".encode("utf8", $tablelabel)."</font></nobr>";
            }
            if ($showtype) {
               ${$options->{content}} .= "</td><td><center>";
               ${$options->{content}} .= "<font size=2>".$columntype."</font>"
                  if ($columntype);
               ${$options->{content}} .= "</center>";
            }
            if ($columntype) {
               ${$options->{content}} .= "</td></tr>";
               ${$options->{content}} .= "</tr><tr><td></td><td colspan=".(2 + ($showtype ? 1 : 0)).">";
               my $plusimg = "<img src='resource/qx/icon/Tango/16/actions/list-add.png' align=absmiddle>";
               my $minusimg = "<img src='resource/qx/icon/Tango/16/actions/list-remove.png' align=absmiddle>";
               if ($column eq $self->{dbm}->getIdColumnName($table)) {
                  my $tableslist = $self->{dbm}->getDBBackend($table)->getTableList();
                  if ($tableslist->{$table}) {
                     ${$options->{content}} .= "<font size=2>";
                     my $wherePre = $self->{dbm}->Where_Pre({ %$options, table => $table, prgcontext => "" });
                     #push(@$wherePre, join(" OR ", map { "( ".$table.$TSEP.$self->{dbm}->getIdColumnName($table)." = '".$_."' )" } @{$filter->{$curfilter}}))
                     #   if ($filter->{$curfilter} && (ref($filter->{$curfilter}) eq "ARRAY"));
                     my $db = $self->{dbm}->getDBBackend($table);
                     my $ret = $db->getDataSet({
                        table => $table,
                        #nodeleted => 1,
                        wherePre => $wherePre,
                        session => $options->{curSession},
                     });
                     my $addtext = $self->{text}->{qx}->{selected_entries_only} ;
                     if ($filter->{$curfilter} && (ref($filter->{$curfilter}) eq "ARRAY") && scalar(@{$filter->{$curfilter}}))
                     {
                        ${ $options->{content} } .=  $self->{text}->{qx}->{only_the_following} . join(
                            "",
                            map {
                                my $id    = $_;
                                my $label = $id;
                                if (   defined($ret)
                                    && ( ref($ret) eq "ARRAY" )
                                    && ( ref( $ret->[0] ) eq "ARRAY" ) )
                                {
                                    foreach my $dbline ( @{ $ret->[0] } ) {
                                        if (
                                            $dbline->{
                                                    $table
                                                  . $TSEP
                                                  . $self->{dbm}
                                                  ->getIdColumnName($table)
                                            } eq $_
                                          )
                                        {
                                            $label =
                                              $self->{gui}
                                              ->getLineForTable( $table,
                                                $dbline, 1 );
                                            last;
                                        }
                                    }
                                }
                                $self->getFilterActionLink( $options,
                                    "deletearrayentry", $curfilter, $id )
                                  . $minusimg . "</a> "
                                  . encode( "utf8", $label ) . "<br>"
                            } @{ $filter->{$curfilter} }
                        );

                        #${$options->{content}} .= "<br>";
                        $addtext = $self->{text}->{qx}->{further_selection} ;
                     }

                    if (defined($ret)
                        && ( ref($ret) eq "ARRAY" )
                        && ( ref( $ret->[0] ) eq "ARRAY" )
                        && (
                               !$filter->{$curfilter}
                            || ( ref( $filter->{$curfilter} ) ne "ARRAY" )
                            || (
                                scalar( @{ $ret->[0] } ) >
                                scalar( @{ $filter->{$curfilter} } ) )
                        )
                      )
                    {
                        ${ $options->{content} } .= hidebegin(
                            "filter" . $table . $curfilter,
                            $plusimg . " " . $addtext
                        );

       #${$options->{content}} .= "<table border=1><tr><td><font size=1><nobr>";
                        ${ $options->{content} } .=
                          $self->getFilterActionForm( $options, "addtoarray",
                            $curfilter );

                        ${ $options->{content} } .=
                          "<select name='filtervalue'>\n";

                        foreach my $dbline ( @{ $ret->[0] } )
                        {
                            next
                              if (
                                   $filter->{$curfilter}
                                && ( ref( $filter->{$curfilter} ) eq "ARRAY" )
                                && scalar(
                                    grep {
                                        $dbline->{ $table
                                              . $TSEP
                                              . $self->{dbm}
                                              ->getIdColumnName($table) } eq $_
                                    } @{ $filter->{$curfilter} }
                                )
                              );
                            next
                              unless my $label =
                              $self->{gui}
                              ->getLineForTable( $table, $dbline, 1 );

                            #${$options->{content}} .= $label."<br>";
                            ${ $options->{content} } .=
                              "<option value='"
                              . $dbline->{ $table
                                  . $TSEP
                                  . $self->{dbm}->getIdColumnName($table) }
                              . "'>"
                              . encode( "utf8", $label )
                              . "</option>\n";
                        }
                        ${ $options->{content} } .=
                            "</select><input type=submit value=$self->{text}->{qx}->{add} ></form>";

                  #${$options->{content}} .= "</nobr></font></td></tr></table>";
                        ${ $options->{content} } .= hideend();
                    }
                     ${$options->{content}} .= "</font>";
                  } else {
                     ${$options->{content}} .= "<font color=red>$self->{text}->{qx}->{link_to_broken}" . $table . "</font>";
                  }
               }
               elsif (($columntype eq "date") ||
                        ($columntype eq "datetime"))
               {
                  my $datedef = clone($self->{gui}->{datedef});

                  if ($columntype eq "date")
                  {
                     $datedef = [@$datedef[0..2]];
                     $datedef->[2]->[1] = "";
                     $datedef->[0]->[4] = "";
                  }

                  ${$options->{content}} .= "<font size=2>";

                  my $addtext = $plusimg . " " . $self->{text}->{qx}->{before_specific_date} ; #  . "<br>" . $curfilter . "_begin" . "<br>" . join(";", map { $_ . "=" . $filter->{$_} } keys %$filter);

                  if ($filter->{$curfilter."_begin"})
                  {
                     ${$options->{content}} .= $self->getFilterActionLink($options, "deletefilterdatebegin", $curfilter).$minusimg."</a>" . $self->{text}->{qx}->{before} ;
                     $addtext = $filter->{$curfilter."_begin"};
                  }

                  ${$options->{content}} .= hidebegin("filter".$table.$curfilter."begin", $addtext);
                  ${$options->{content}} .= $self->getFilterActionForm($options, "setfilterdatebegin", $curfilter, $column);
                  ${$options->{content}} .= $self->{gui}->printDateQuestion("search".$column."_begin_", $self->{gui}->getDatePredefFor($column, $filter->{$curfilter."_begin"}), $datedef);
                  ${$options->{content}} .= "<input type=submit value=" .  $self->{text}->{qx}->{refresh} . ">";
                  ${$options->{content}} .= "</form>";
                  ${$options->{content}} .= hideend();
                  $addtext = $plusimg . " " . $self->{text}->{qx}->{after_specific_date} ;

                  if ($filter->{$curfilter."_end"})
                  {
                     ${$options->{content}}  .= $self->getFilterActionLink($options, "deletefilterdateend", $curfilter) . $minusimg . "</a>" . $self->{text}->{qx}->{after} ;
                     $addtext = $filter->{$curfilter."_end"};
                  }
                  ${$options->{content}} .= hidebegin("filter".$table.$curfilter."end", $addtext);
                  ${$options->{content}} .= $self->getFilterActionForm($options, "setfilterdateend", $curfilter, $column);
                  ${$options->{content}} .= $self->{gui}->printDateQuestion("search".$column."_end_", $self->{gui}->getDatePredefFor($column, $filter->{$curfilter."_end"}, 1), $datedef);
                  ${$options->{content}} .= "<input type=submit value=" .  $self->{text}->{qx}->{refresh} . ">";
                  ${$options->{content}} .= "</form>";
                  ${$options->{content}} .= hideend();
                  ${$options->{content}} .= "</font>";
               } elsif ($columntype eq "boolean") {
                  ${$options->{content}} .= "<font size=2>";
                  if ($filter->{$curfilter} eq "1") {
                     ${$options->{content}} .= $self->{text}->{qx}->{has_to_be_set} ;
                  } elsif ($filter->{$curfilter} eq "0") {
                     ${$options->{content}} .= $self->{text}->{qx}->{must_not_be_set} ;
                  } else {
                     ${$options->{content}} .= $plusimg . $self->{text}->{qx}->{has_to_be_set} ;
                     ${$options->{content}} .= "<br>";
                     ${$options->{content}} .= $plusimg . $self->{text}->{qx}->{must_not_be_set} ;
                  }
                  ${$options->{content}} .= "</font>";
               } elsif ($columntype eq $DELETEDCOLUMNNAME) {
                  ${$options->{content}} .= "<font size=2>";
                  if ($filter->{$curfilter} eq "1") {
                     ${$options->{content}}  .= $minusimg . $self->{text}->{qx}->{only_archived_entries} ;
                  } elsif ($filter->{$curfilter} eq "0") {
                     ${$options->{content}} .= $minusimg . $self->{text}->{qx}->{only_non_archived} ;
                  } else {
                     ${$options->{content}} .= $plusimg . $self->{text}->{qx}->{only_archived_entries} ;
                     ${$options->{content}} .= "<br>";
                     ${$options->{content}} .= $plusimg . $self->{text}->{qx}->{only_non_archived} ;
                  }
                  ${$options->{content}} .= "</font>";
               } elsif ($columntype eq "number") {
                  ${$options->{content}} .= "<font size=2>" . $self->{text}->{qx}->{number} . "</font>";
               #if (($columntype eq "text") ||
               #    ($columntype eq "textarea")) {
               } else {
                  ${$options->{content}} .= "<font size=2>";
                  my $addtext = $plusimg . " " . $self->{text}->{qx}->{filter_for_text} ;
                  if ($filter->{$curfilter}) {
                     ${$options->{content}} .= $self->getFilterActionLink($options, "deletefilterval", $curfilter).$minusimg."</a> " . $self->{text}->{qx}->{contains} . ": ";
                     $addtext = $filter->{$curfilter};
                  }
                  ${$options->{content}} .= hidebegin("filter".$table.$curfilter, $addtext);
                  ${$options->{content}} .= $self->getFilterActionForm($options, "setfilterval", $curfilter);
                  ${$options->{content}} .= "<table width=100%><tr><td>"; # " width=1%><font size=2>".$minusimg." Beinhaltet: ".$filter->{$curfilter}."</font>"."</td><td>";
                  ${$options->{content}} .= "<input type=text name=filtervalue style='width:100%' value='".($filter->{$curfilter}||"")."'>";
                  ${$options->{content}} .= "</td><td>";
                  ${$options->{content}} .= "<input type=submit value=" . $self->{text}->{qx}->{refresh} . ">";
                  ${$options->{content}} .= "</td></tr></table>";
                  ${$options->{content}} .= "</form>";
                  ${$options->{content}} .= hideend();
                  ${$options->{content}} .= "</font>";
               #} else {
               #   ${$options->{content}} .= "<font color=red>Unbekannter type: ".$columntype."</font>";
               }
            }
         } else {
            ${$options->{content}} .= "<td colspan=".(2 + ($showtype ? 1 : 0)).">";
            ${$options->{content}} .= $curfilter." (<font color=red>" . $self->{text}->{qx}->{unknown_filter_crit} . "</font>)";
         }
         ${$options->{content}} .= "</td></tr>";
         #${$options->{content}} .= " = ".(
         #   (ref($filter->{$curfilter}) eq "ARRAY") ? "OR(".  join(",",                                                @{$filter->{$curfilter}}).")" : 
         #   (ref($filter->{$curfilter}) eq "HASH")  ? "HASH:".join(",", map { $_."=".$filter->{$curfilter}->{$_}} keys %{$filter->{$curfilter}}) :
         #        $filter->{$curfilter})
         #   if $filter->{$curfilter};
         #${$options->{content}} .= "<br>\n";
      }
      ${$options->{content}} .= "</table>";
   } else {
       ${$options->{content}} .= "<br><font size=4><center>" . $self->{text}->{qx}->{no_filter_crit_selected} . "</center></font>";
   }
   ${$options->{content}} .= "</font>";
}


sub onTableSelect
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams )
        && $options->{curSession}
        && $options->{table}
        && $options->{oid} )
    {
        Log("Qooxdoo: onTableSelect: Missing parameters: table:"
              . $options->{table}
              . ":curSession:"
              . $options->{curSession} . ":oid:"
              . $options->{oid} . " !",
            $ERROR
        );
        return undef;
    }

    my $suffix = $options->{suffix} || "show";
    if (
        defined(
            my $err = $self->{dbm}->checkRights(
                $options->{curSession},
                $ACTIVESESSION, $options->{table}
            )
        )
      )
    {
        $poe_kernel->yield( sendToQX => "showmessage "
              . CGI::escape( $self->{text}->{qx}->{internal_error} )
              . " 400 200 "
              . CGI::escape( $self->{text}->{qx}->{permission_denied} . "\n") );
        Log( "Qooxdoo: onTableSelect: GET: ACCESS DENIED: " . $err->[0],
            $err->[1] );
        return undef;
    }

#$poe_kernel->yield(sendToQX => "createiframe ".CGI::escape($options->{oid}."_tableselect_iframe")." ".CGI::escape("/ajax?nocache=".rand(999999999999)."&job=prefilter&oid=".$options->{oid}."&table=".$options->{table}."&sessionid=".$options->{curSession}->{sessionid}));
    my $curtabledef      = $self->{dbm}->getTableDefiniton( $options->{table} );
    my $db               = $self->{dbm}->getDBBackend( $options->{table} );
    my $tableconnections = {};
    if (
        (
            $tableconnections = $db->searchTableConnections(
                $options->{table}, $curtabledef->{defaulttablebackrefs} ? 1 : 0
            )
        )
        && ( ref($tableconnections) eq "HASH" )
        && exists( $tableconnections->{history} )
        && defined( $tableconnections->{history} )
        && ( ref( $tableconnections->{history} ) eq "ARRAY" )
      )
    {
        my $curtree = {};
        my $curelement = { $options->{table} => $curtree, };
        foreach my $curlink ( @{ $tableconnections->{history} } ) {
            unless ( $curelement->{ $curlink->{table} } ) {
                Log(    "Error: Unresolvable link: "
                      . $curlink->{ctable} . "("
                      . $curlink->{asname} . ") "
                      . ( $curlink->{type} eq $FORWARD ? "->" : "<-" ) . " "
                      . $curlink->{table} );
                next;
            }
            if (
                exists(
                    $curelement->{ $curlink->{table} }->{ $curlink->{ctable} }
                )
              )
            {
                Log(    "Error: link already exiting: "
                      . $curlink->{ctable} . "("
                      . $curlink->{asname} . ") "
                      . ( $curlink->{type} eq $FORWARD ? "->" : "<-" ) . " "
                      . $curlink->{table} );
            }
            else {
                $curelement->{ $curlink->{table} }->{ $curlink->{asname} } =
                  { name => $curlink->{ctable} };  # type => $curlink->{type} };
                $curelement->{ $curlink->{ctable} } =
                  $curelement->{ $curlink->{table} }->{ $curlink->{asname} };
            }
        }
        $poe_kernel->yield(
                sendToQX => "createtree "
              . CGI::escape( $options->{oid} . "_tableselect_tree" ) . " "
              . CGI::escape( $self->{text}->{qx}->{search_criteria} ) . " "
              . CGI::escape(
                    ",treeaction=filter,table="
                  . $options->{table}
                  . ",loid="
                  . $options->{oid}
                  . $options->{urlappend}
              )
        );
        $self->addFilterTables(
            $options->{curSession},
            $options->{oid} . "_tableselect_tree",
            "",
            { name => $options->{table} },
            $options->{onlyWithMark}
        );
        $self->addFilterTables(
            $options->{curSession},
            $options->{oid} . "_tableselect_tree",
            "", $curtree, $options->{onlyWithMark}
        );
    }
    else {
        $poe_kernel->yield( sendToQX => "showmessage "
              . CGI::escape( $self->{text}->{qx}->{internal_error} )
              . " 400 200 "
              . CGI::escape( $self->{text}->{qx}->{table_ref_tree_error} ) );
    }
}

#sub onTableSelectWindow {
#   my $self = shift;
#   my $options = shift;
#   my $moreparams = shift;
#   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{oid}) {
#      Log("Qooxdoo: onTableSelectWindow: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.":oid:".$options->{oid}." !", $ERROR);
#      return undef;
#   }
#   my $suffix = $options->{suffix} || "show";
#   my $curtabledef = $self->{dbm}->getTableDefiniton($options->{table});
#   $poe_kernel->yield(sendToQX => "createwin ".CGI::escape($options->{oid}."_tableselect")." ".($curtabledef->{qxsearchwidth} || $curtabledef->{qxeditwidth} || $qxsearchwidth || $qxwidth)." ".($curtabledef->{qxsearchheight} || $curtabledef->{qxeditheight} || $qxsearchheight || $qxheight)." ".CGI::escape("Filter in ".($curtabledef->{label} || $options->{table}))." ".(CGI::escape($curtabledef->{icon} || '')));
#   $self->onTableSelect($options);
#   $poe_kernel->yield(sendToQX => "createbutton ".CGI::escape($options->{oid}."_tableselect_button")." ".
#                                                  CGI::escape("Schliessen")." ".
#                                                  CGI::escape("resource/qx/icon/Tango/32/actions/dialog-close.png")." ".
#                                                  CGI::escape("job=closeobject,oid=".$options->{table}."_".$options->{column}."_".$suffix));
#   $poe_kernel->yield(sendToQX => "addobject ".CGI::escape($options->{oid}."_tableselect")." ".CGI::escape($options->{oid}."_tableselect_tree"));
#   $poe_kernel->yield(sendToQX => "addobject ".CGI::escape($options->{oid}."_tableselect")." ".CGI::escape($options->{oid}."_tableselect_button"));
#   $poe_kernel->yield(sendToQX => "open ".CGI::escape($options->{oid}."_tableselect"));
#}

sub addFilterTables
{
   my $self       = shift;
   my $curSession = shift;
   my $oid        = shift;
   my $table      = shift;
   my $tree       = shift;
   my $mark       = shift;

   my $curtabledef = undef;

   foreach my $curtable (keys %$tree)
   {
      next if ($curtable eq "name");
      $curtabledef = $self->{dbm}->getTableDefiniton($tree->{$curtable}->{name});
      $poe_kernel->yield(sendToQX => "addtreefolder ".CGI::escape($oid)." ".CGI::escape($table)." ".CGI::escape($curtable)." ".CGI::escape(($curtabledef->{label} || $table))); #.( "(".$curtable.":".$tree->{$curtable}->{name}.")")));
      $self->addFilterTables($curSession, $oid, $curtable, $tree->{$curtable}, $mark);
   }
   if ($tree->{name}) {
      $curtabledef = $self->{dbm}->getTableDefiniton($tree->{name});
      foreach my $curcolum (grep {
      #   $_ ne $self->{dbm}->getIdColumnName($tree->{name})
      #} grep {
         my $status = $self->{gui}->getViewStatus({
            column => $_,
            table => $tree->{name},
            targetself => $curSession,
            action => $LISTACTION,
         });
         ($status ne "hidden") #&& ($status ne "writeonly")
      } grep {
         $self->{dbm}->isMarked($mark, $curtabledef->{columns}->{$_}->{marks}) &&
                                      ($curtabledef->{columns}->{$_}->{type} ne "virtual")
      } hashKeysRightOrder($curtabledef->{columns})) {
         my $label = $curtabledef->{columns}->{$curcolum}->{label};
         $label =~ s,^\s+,,g;
         $label =~ s,\s+$,,g;
         $label ||= $curcolum;
         $poe_kernel->yield(sendToQX => "addtreeentry ".CGI::escape($oid)." ".CGI::escape($table)." ".CGI::escape($tree->{name}.$TSEP.$curcolum)." ".CGI::escape($label));
      }
   }
}

sub getDefaults {
    my $self       = shift;
    my $params     = shift;

    my $options    = $params->{options};
    my $mydefaults = $options->{defaults} || {};

    foreach my $column ( @{ $params->{columns} } ) {
        $mydefaults->{ $options->{table} . $TSEP . $column } =
          $options->{q}->param( $options->{table} . $TSEP . $column )
          if ( exists( $options->{q} )
            && defined( $options->{q} )
            && $options->{q}
            && $options->{q}->param( $options->{table} . $TSEP . $column ) );
        $mydefaults->{ $options->{table} . $TSEP . $column } ||=
          $params->{ret}->[0]->[0]->{ $options->{table} . $TSEP . $column }
          if (
            defined(
                $params->{ret}->[0]->[0]
                  ->{ $options->{table} . $TSEP . $column }
            )
            && ( $options->{$UNIQIDCOLUMNNAME} )
          );
        if (
            (
                !defined(
                    $mydefaults->{ $options->{table} . $TSEP . $column }
                )
            )
            || (
                (
                    $params->{curtabledef}->{columns}->{$column}
                    ->{defaultoverwritesnull}
                )
                &&

# TODO:XXX:FIXME: Hier sollte die Überprüfung auf undef im Datentypenliegen, und nicht manuell selbst gemacht werden
                ( !$mydefaults->{ $options->{table} . $TSEP . $column } )
                || (
                    (
                        $params->{curtabledef}->{columns}->{$column}->{type} eq
                        "date"
                        || ($params->{curtabledef}->{columns}->{$column}->{type} eq "datetime" )
                    )
                    && ( $mydefaults->{ $options->{table} . $TSEP . $column } eq "0000-00-00 00:00:00" )
                )
            )
          )
        {
            if (ref( $params->{curtabledef}->{columns}->{$column}->{default} )
                eq "CODE" )
            {
                $mydefaults->{ $options->{table} . $TSEP . $column } =
                  $params->{curtabledef}->{columns}->{$column}
                  ->{default}( $params->{ret}->[0]->[0],
                    $options->{curSession} );
                Log(
                    'YOU HAVE TO USE "code" AND NOT "default" for code execution!',
                    $ERROR
                );
            }
            elsif (
                (
                    !exists(
                        $params->{curtabledef}->{columns}->{$column}->{default}
                    )
                    || !defined(
                        $params->{curtabledef}->{columns}->{$column}->{default}
                    )
                    || ( $params->{curtabledef}->{columns}->{$column}->{default}
                        eq '' )
                )
                && (
                    ref(
                        $params->{curtabledef}->{columns}->{$column}
                          ->{defaultfunc}
                    ) eq "CODE"
                )
              )
            {
                $mydefaults->{ $options->{table} . $TSEP . $column } =
                  $params->{curtabledef}->{columns}->{$column}
                  ->{defaultfunc}( $options->{targetself},
                    $params->{ret}->[0]->[0] );
            }
            else {
                $mydefaults->{ $options->{table} . $TSEP . $column } =
                  $params->{curtabledef}->{columns}->{$column}->{default};
            }
        }
        $mydefaults->{ $options->{table} . $TSEP . $column } ||= '';
        $mydefaults->{ $options->{table} . $TSEP . $column } =~
          s/([:\s])0(\d)/$1$2/g
          if ( $params->{curtabledef}->{columns}->{$column}->{type} eq
            "datetime" );
    }
    return $mydefaults;
}

sub determineCrossLink {
   my $self = shift;
   my $column = shift;
   my $crosslink = shift;
   my $crosstable = shift;
   
   return 0 unless $crosslink;

   if ($self->{dbm}->{config}->{oldlinklogic})
   {
      return ($crosstable . "_" . $self->{dbm}->getIdColumnName($crosstable) eq $column) ? 1 : 0;
   }
   else     
   {
      my $curtabledef = $self->{dbm}->getTableDefiniton($crosslink);
      #print "Q\tCOLUMN=".$column."\tXTABLE=".$crosstable."\tXLINK=".$crosslink."\tLINKTO=".$curtabledef->{columns}->{$column}->{linkto}."\n";
      return (exists($curtabledef->{columns}->{$column}->{linkto}) &&
             defined($curtabledef->{columns}->{$column}->{linkto}) &&
                     $curtabledef->{columns}->{$column}->{linkto} eq $crosstable) ? 1 : 0;
   }
}


sub onNewEditEntry
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams )
        && $options->{curSession}
        && $options->{table}
        && $options->{connection} )
    {
        Log(
            "Qooxdoo: onNewEditEntry: Missing parameters: table:"
              . $options->{table}
              . ":curSession:"
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }

    my $suffix = "edit";
    if (
        defined(
            my $err = $self->{dbm}->checkRights(
                $options->{curSession}, $ACTIVESESSION,
                $options->{table},      $options->{$UNIQIDCOLUMNNAME}
            )
        )
      )
    {
        $self->sendToQXForSession(
            $options->{connection}->{sessionid} || 0,
            "showmessage "
              . CGI::escape( $self->{text}->{qx}->{internal_error} )
              . " 400 200 "
              . CGI::escape( $self->{text}->{qx}->{permission_denied} . "\n"),
            $options->{connection}->{sessionid} || 0
        );
        Log( "Qooxdoo: onNewEditEntry: GET: ACCESS DENIED: " . $err->[0],
            $err->[1] );
        return undef;
    }
    my $curtabledef = $self->{dbm}->getTableDefiniton( $options->{table} );
    my $columns = [    #grep { my $status = $self->{gui}->getViewStatus({
                       #      column => $_,
                       #      table => $options->{table},
                       #      targetself => $options->{curSession}
                       #   }); ($status ne "hidden") }
        grep {
            (        exists( $curtabledef->{columns}->{$_}->{type} )
                  && defined( $curtabledef->{columns}->{$_}->{type} )
                  && ( $curtabledef->{columns}->{$_}->{type} ne "htmltext" )
                  && ( $curtabledef->{columns}->{$_}->{type} ne "longtext" ) )
              && $self->{dbm}->isMarked( $options->{onlyWithMark},
                $curtabledef->{columns}->{$_}->{marks} )
          }

    # TODO:FIXME:XXX: Typ "virtual" hier rausfiltern oder als readonly schicken?
          hashKeysRightOrder(
            $curtabledef->{columns},
            0, $options->{specialordercolumn}
          )
    ];
    my $ret = [];
    if ( $options->{$UNIQIDCOLUMNNAME} ) {
        my $db = $self->{dbm}->getDBBackend( $options->{table} );
        unless (
            defined(
                $ret = $db->getDataSet(
                    {
                        table             => $options->{table},
                        nodeleted         => 1,
                        $UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
                        wherePre          => $self->{dbm}->Where_Pre($options),
                        session           => $options->{curSession}
                    }
                )
            )
            && ( ref($ret) eq "ARRAY" )
            && ( scalar( @{ $ret->[0] } ) >= 1 )
          )
        {
            Log(
                "DBManager: onNewLineServer: GET "
                  . $options->{table}
                  . " FAILED SQL Query failed.",
                $WARNING
            );
            $self->sendToQXForSession(
                $options->{connection}->{sessionid} || 0,
                "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{permission_denied} )
                  . " 300 50 "
                  . CGI::escape( $self->{text}->{qx}->{permission_denied} ),
                $options->{connection}->{sessionid} || 0
            );
            return undef;
        }
    }

    my $window = undef;

    if ( $options->{window} )
    {
        $window = $options->{window};
        $self->sendToQXForSession( $options->{connection}->{sessionid} || 0,
            "destroy " . $window . "_tabs" )
          ;    # , $options->{connection}->{sessionid} || 0);
        $self->sendToQXForSession( $options->{connection}->{sessionid} || 0,
            "destroy " . $window . "_data" )
          ;    # , $options->{connection}->{sessionid} || 0);
        $self->sendToQXForSession(
            $options->{connection}->{sessionid} || 0,
            "destroy " . $window . "_button"
        );     # , $options->{connection}->{sessionid} || 0);
    }
    else {
        $window = $options->{table} . "_" . $suffix;
        $self->sendToQXForSession( $options->{connection}->{sessionid} || 0,
            "destroy " . $window )
          ;    # , , $options->{connection}->{sessionid} || 0);
        $self->sendToQXForSession(
            $options->{connection}->{sessionid} || 0,
            "createwin "
              . $window . " "
              . ( $curtabledef->{qxeditwidth}  || $qxwidth ) . " "
              . ( $curtabledef->{qxeditheight} || $qxheight ) . " "
              . CGI::escape(
                (
                         $options->{newedittitle}
                      || $options->{title}
                      || ( $options->{$UNIQIDCOLUMNNAME}
                        ?  $self->{text}->{qx}->{details_of_entry} . $options->{$UNIQIDCOLUMNNAME}
                        :  $self->{text}->{qx}->{new_entry} )
                      . $self->{text}->{qx}->{in} 
                      . ( $curtabledef->{label} || $options->{table} )
                )
              )
              . " "
              . ( CGI::escape( $curtabledef->{icon} || '' ) )
        );    # , , $options->{connection}->{sessionid} || 0);
        $self->sendToQXForSession( $options->{connection}->{sessionid} || 0,
            "open " . $window . " 1" )
          ;    # , , $options->{connection}->{sessionid} || 0);
               # TODO:FIXME:XXX: Modal sollte konfigurierbar sein!
         #$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "modal ".$window." 1", $options->{connection}->{sessionid} || 0);
    }
    my $links      = {};
    my $mydefaults = $self->getDefaults(
        {
            options     => $options,
            curtabledef => $curtabledef,
            columns     => $columns,
            ret         => $ret,
        }
    );
    my $overridecolumns = [];
    if ( $options->{override} ) {
        $ret->[0]->[0] = { %{ $ret->[0]->[0] }, %{ $options->{override} } };

        #Log("COLUMNS PRE:".scalar(@$columns), $WARNING);
        $overridecolumns = [
            grep {
                my $column = $_;
                scalar( grep { $_ eq $column } @$columns ) ? 0 : 1
            } keys %{ $options->{override} }
        ];

        #Log("COLUMNS POST:".scalar(@$columns), $WARNING);
    }
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "createedit " . join(
            " ",
            (
                CGI::escape( $window . "_data" ),    # 1. Interne Objekt ID
                @{
                    $self->getBasicDataDefine(
                        {
                            %$options,
                            crosslink       => $options->{crosslink},
                            crosstable      => $options->{crosstable},
                            table           => $options->{table},
                            columns         => $columns,
                            overridecolumns => $overridecolumns,
                            links           => $links,
                            curSession      => $options->{curSession},
                            realtype        => 1,
                            action          => (
                                  $options->{$UNIQIDCOLUMNNAME} ? $UPDATEACTION
                                : $NEWACTION
                            ),
                        }
                    )
                },
                join(
                    ",",
                    (
                        (
                            map {
                                $self->determineCrossLink( $_,
                                    $options->{crosslink},
                                    $options->{crosstable} )
                                  ? $options->{crossid}
                                  : CGI::escape(
                                    $self->{gui}->doFormularColumn(
                                        {
                                            table  => $options->{table},
                                            column => $_,
                                            targetself =>
                                              $options->{curSession},
                                            mydefaults => $mydefaults
                                        }
                                    )
                                  )
                            } @$columns
                        ),
                        map { $options->{override}->{$_} } @$overridecolumns
                    )
                  )
                , # 7. Die Werte des Eintrags, oder die Defaultwerte wenns neu is
                join(
                    ",",
                    (
                        (
                            map {
                                CGI::escape(
                                    $curtabledef->{columns}->{$_}->{unit}
                                      || "" )
                            } @$columns
                        ),
                        map { "" } @$overridecolumns
                    )
                ),    # 8. Units
                CGI::escape( $curtabledef->{infotextedit} || '' )
                ,     # 9. Hilfetext
                CGI::escape( $window || '' ),    # 10. Parentwindow
                CGI::escape(
                    (
                        $options->{crosslink}
                        ? ",crosslink="
                          . CGI::escape( $options->{crosslink} )
                          . ",crossid="
                          . CGI::escape( $options->{crossid} )
                          . ",crosstable="
                          . CGI::escape( $options->{crosstable} )
                        : ''
                    )
                    . ( $options->{urlappend} || '' )
                ),    # 11. urlappend
            )
        )
    );                # , $options->{connection}->{sessionid} || 0);
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "createtabview " . CGI::escape( $window . "_tabs" )
    );                # , $options->{connection}->{sessionid} || 0);
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "addtab "
          . CGI::escape( $window . "_tabs" ) . " "
          . CGI::escape( $window . "_tabs_tab1" )
          . " " . $self->{text}->{qx}->{basis_data} 
    );                # , $options->{connection}->{sessionid} || 0);
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "addobject "
          . CGI::escape($window) . " "
          . CGI::escape( $window . "_tabs" )
    );                # , $options->{connection}->{sessionid} || 0);
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "addobject "
          . CGI::escape( $window . "_tabs_tab1" ) . " "
          . CGI::escape( $window . "_data" )
    );                # , $options->{connection}->{sessionid} || 0);

#$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "createtoolbarbutton ".CGI::escape($window."_data_toolbar_close")." Abbrechen resource/qx/icon/Tango/32/actions/dialog-close.png job=closeobject,oid=".$window, $options->{connection}->{sessionid} || 0);
    $self->sendToQXForSession(
        $options->{connection}->{sessionid} || 0,
        "addobject "
          . CGI::escape( $window . "_data_toolbar" ) . " "
          . CGI::escape( $window . "_data_toolbar_close" )
    );                # , $options->{connection}->{sessionid} || 0);

    $self->doSpecialColumns(
        {
            %$options,
            basetable => $options->{table},

            #table => $options->{table},
            window => $window,

            #curSession => $options->{curSession},
            defaults => $ret->[0]->[0],
            oid      => $options->{oid},

            #connection => $options->{connection},
            #onlyWithMark => $options->{onlyWithMark},
            #$UNIQIDCOLUMNNAME => $options->{$UNIQIDCOLUMNNAME},
        }
    );

#$self->sendToQXForSession($options->{connection}->{sessionid} || 0, $options->{connection}->{sessionid} || 0, "createbutton ".CGI::escape($window."_button")." ".
#                                               CGI::escape("Schliessen")." ".
#                                               CGI::escape("resource/qx/icon/Tango/32/actions/dialog-close.png")." ".
#                                               CGI::escape("job=closeobject,oid=".$window), $options->{connection}->{sessionid} || 0);
#$self->sendToQXForSession($options->{connection}->{sessionid} || 0, $options->{connection}->{sessionid} || 0, "addobject ".CGI::escape($window)." ".CGI::escape($window."_button")."\n", $options->{connection}->{sessionid} || 0);
    my $return = { $options->{table} => $ret };
    $options->{override} ||= {};
    foreach my $column ( keys %$links ) {
        my $curTable = $links->{$column}->[0];
        my $cursubtabledef =
          $self->{dbm}->getTableDefiniton( $options->{table} );
        my $columns = [
            @{
                getAffectedColumns(
                    $self->{dbm}->getDBBackend( $options->{table} )->{config}
                      ->{DB},
                    $cursubtabledef->{columns}, 1
                )
            }
        ];
        if (
            defined(
                my $err = $self->{dbm}->checkRights(
                    $options->{curSession},
                    $ACTIVESESSION, $curTable
                )
            )
          )
        {
#$self->sendToQXForSession($options->{connection}->{sessionid} || 0, "showmessage ".CGI::escape("Internal error")." 400 200 ".CGI::escape("onNewEditEntry ACCESS DENIED\n"), $options->{connection}->{sessionid} || 0);
            Log( "Qooxdoo: onNewEditEntry: GET: ACCESS DENIED: " . $err->[0],
                $err->[1] );
            next;
        }
        my $db        = $self->{dbm}->getDBBackend($curTable);
        my $nodeleted = 0;
        my $curwhere  = $self->{dbm}->Where_Pre(
            {
                %$options,
                basetable => $options->{table},
                baseid    => $options->{$UNIQIDCOLUMNNAME},
                table     => $curTable
            }
        );
        push( @$curwhere, $options->{orselection}->{$column} )
          if ( $options->{orselection}->{$column} );

        if ( $ret->[0]->[0]->{ $options->{table} . $TSEP . $column } )
        {
            $curwhere = [
                map {
                        "(("
                      . $_ . ")"
                      . ( $nodeleted
                        ? ""
                        : " AND ("
                          . $curTable
                          . $TSEP
                          . $DELETEDCOLUMNNAME
                          . " != 1)" )
                      . ") OR ("
                      . $curTable
                      . $TSEP
                      . $self->{dbm}->getIdColumnName($curTable) . " = "
                      . $ret->[0]->[0]->{ $options->{table} . $TSEP . $column }
                      . ")"
                } @$curwhere
            ];
            $nodeleted++;
        }

        my $curret = undef;

        unless (
            defined(
                $curret = $db->getDataSet(
                    {
                        table     => $curTable,
                        wherePre  => $curwhere,
                        session   => $options->{curSession},
                        nodeleted => $nodeleted,
                        searchdef => $self->{dbm}->getFilter($options),
                    }
                )
            )
            && ( ref($curret) eq "ARRAY" )
          )
        {
            Log(
                "Qooxdoo: onNewEditEntry: GET "
                  . $curTable
                  . " FAIL: SQL Query failed.",
                $WARNING
            );
            $self->sendToQXForSession(
                $options->{connection}->{sessionid} || 0,
                "showmessage "
                  . CGI::escape( $self->{text}->{qx}->{internal_error} )
                  . " 400 200 "
                  . CGI::escape( $self->{text}->{qx}->{failed} )
            );    # , $options->{connection}->{sessionid} || 0);
            return undef;
        }
        $return->{$curTable} = $curret;
        $self->sendToQXForSession(
            $options->{connection}->{sessionid} || 0,
            "addtoeditlist "
              . $window
              . "_data "
              . $column . " "
              . CGI::escape("-") . " "
        );        # , $options->{connection}->{sessionid} || 0);
        my $curtabledef = $self->{dbm}->getTableDefiniton($curTable);
        foreach my $dbline ( @{ $curret->[0] } ) {
            $self->sendToQXForSession(
                $options->{connection}->{sessionid} || 0,
                "addtoeditlist " . $window . "_data " . $column . " " . (
                    CGI::escape(

#$self->{gui}->Column_Handler($options->{curSession}, $options->{table}, $dbline, $column)
                        $self->{gui}->getValueForTable( $curTable, $dbline )
                      )
                      || $dbline->{
                            $curTable
                          . $TSEP
                          . $self->{dbm}->getIdColumnName($curTable)
                      }
                  )
                  . " "
                  . (
                    (
                        exists(
                            $options->{override}->{
                                    $curTable
                                  . $TSEP
                                  . $self->{dbm}->getIdColumnName($curTable)
                            }
                          )
                          && defined(
                            $options->{override}->{
                                    $curTable
                                  . $TSEP
                                  . $self->{dbm}->getIdColumnName($curTable)
                            }
                          )
                          && $options->{override}->{
                                $curTable
                              . $TSEP
                              . $self->{dbm}->getIdColumnName($curTable)
                          }
                    )
                    ? $options->{override}->{
                            $curTable
                          . $TSEP
                          . $self->{dbm}->getIdColumnName($curTable)
                      }
                    : $dbline->{
                            $curTable
                          . $TSEP
                          . $self->{dbm}->getIdColumnName($curTable)
                    }
                  )
            );    # $options->{connection}->{sessionid} || 0);
        }
    }
    return $return;
}

sub noCrossShowTable
{
   my $self = shift;
   my $table = shift;
   my $crosslinktablename = shift;
   my $curSession = shift;
   my $id = shift;

   my $crosstabledef = $self->{dbm}->getTableDefiniton($crosslinktablename);

   return ($crosstabledef->{crossshowonlyfrom} &&
      (ref($crosstabledef->{crossshowonlyfrom}) eq "ARRAY") &&
     (!scalar(grep { $_ eq $table }
         @{$crosstabledef->{crossshowonlyfrom}}))) ? 1 : 0;
}

sub doSpecialColumns
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams )
        && $options->{table}
        && $options->{defaults}
        && $options->{window}
        && $options->{curSession}
        && $options->{connection} )
    {
        Log( "doSpecialColumns: Missing parameters: table:"
              . $options->{table}
              . ":window="
              . $options->{window}
              . ":defaults="
              . $options->{defaults}
              . ":session="
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }

    return unless $options->{$UNIQIDCOLUMNNAME};
    my $curtabledef = $self->{dbm}->getTableDefiniton( $options->{table} );

    foreach my $column ( hashKeysRightOrder( $curtabledef->{columns} ) )
    {
        next
          unless $self->{dbm}->isMarked( $options->{onlyWithMark},
            $curtabledef->{columns}->{$column}->{marks} );
        next
          if ( ( $curtabledef->{columns}->{$column}->{type} ne "htmltext" )
            && ( $curtabledef->{columns}->{$column}->{type} ne "longtext" ) );
        next
          if ( $curtabledef->{columns}->{$column}->{hidden}
            || $curtabledef->{columns}->{$column}->{readonly} );
        $self->sendToQXForSession(
            $options->{connection}->{sessionid},
            "addtab "
              . CGI::escape( $options->{window} . "_tabs" ) . " "
              . CGI::escape( $options->{window} . "_tabs_" . $column ) . " "
              . CGI::escape(
                $curtabledef->{columns}->{$column}->{label} || $column
              )
        );    # , $options->{connection}->{sessionid} || 0);
        $self->sendToQXForSession(
            $options->{connection}->{sessionid},
            "create"
              . (
                (
                    $curtabledef->{columns}->{$column}->{type}
                      && ( $curtabledef->{columns}->{$column}->{type} eq
                        "htmltext" )
                ) ? "html" : ""
              )
              . "textedit "
              . CGI::escape( $options->{window} . "_tabs_" . $column . "_data" )
              . " "
              . CGI::escape( $options->{table} ) . " "
              . CGI::escape($column) . " "
              . CGI::escape(
                defined( $options->{$UNIQIDCOLUMNNAME} )
                ? $options->{$UNIQIDCOLUMNNAME}
                : Log( "ID is undefined!", $ERROR )
              )
              . " "
              . CGI::escape(
                $options->{defaults}->{ $options->{table} . $TSEP . $column }
                  || ''
              )
              . " "
              . CGI::escape( $curtabledef->{columns}->{$column}->{help} || '' )
              . " "
              . CGI::escape( $options->{urlappend} )
        );
        $self->sendToQXForSession( $options->{connection}->{sessionid},
                "addobject "
              . CGI::escape( $options->{window} . "_tabs_" . $column ) . " "
              . CGI::escape( $options->{window} . "_tabs_" . $column . "_data" )
              . "\n" );    # , $options->{connection}->{sessionid} || 0);
    }

    my $tables = $self->{dbm}->getDBBackend( $options->{table} )->getTableList();

    foreach my $onlycross ( 1, 0 )
    {
        foreach my $crosstable (
            sort {
                ( $tables->{$a}->{order} || 999999 )
                  <=> ( $tables->{$b}->{order} || 999999 )
            } keys %$tables
          )
        {
            my $crosslinktabledef  = undef;
            my $crosslinktablename = undef;
            my $linktabledef = $self->{dbm}->getTableDefiniton($crosstable);
            if ($onlycross) {
                $crosslinktablename =
                  $self->{dbm}
                  ->getTableDefiniton( $options->{table} . "_" . $crosstable )
                  ? $options->{table} . "_" . $crosstable
                  : $self->{dbm}
                  ->getTableDefiniton( $crosstable . "_" . $options->{table} )
                  ? $crosstable . "_" . $options->{table}
                  : undef;
                delete $tables->{crosslinktablename}
                  if defined($crosslinktablename);
            }
            else {
                $crosslinktablename = (
                    (
                        grep {
                            $linktabledef->{columns}->{$_}->{linkto}
                              && ( $linktabledef->{columns}->{$_}->{linkto} eq
                                $options->{table} )
                        } ( keys %{ $linktabledef->{columns} } )
                    )
                      || (
                        exists(
                            $linktabledef->{columns}->{
                                    $options->{table} . "_"
                                  . $self->{dbm}
                                  ->getIdColumnName( $options->{table} )
                            }
                        )
                        && defined(
                            $linktabledef->{columns}->{
                                    $options->{table} . "_"
                                  . $self->{dbm}
                                  ->getIdColumnName( $options->{table} )
                            }
                        )
                      )
                ) ? $crosstable : undef;

# TODO:FIXME:XXX: Das zeigt Tabellen an, die per 1:n auf mich zeigen koennen. Das ist derzeit unschoen,
#                 da man in diesem Fall die Eintraege an sich sieht und diese aendert/loescht und nicht
#                 die Verknuepfung. Das sollte man ueberarbeiten und dann ggf. hier wieder einschalten.
            }
            if (
                $crosslinktablename
                && ( $crosslinktabledef =
                    $self->{dbm}->getTableDefiniton($crosslinktablename) )
              )
            {
                next
                  if $self->noCrossShowTable(
                    $options->{table},      $crosslinktablename,
                    $options->{curSession}, $options->{$UNIQIDCOLUMNNAME}
                  );
                $self->sendToQXForSession(
                    $options->{connection}->{sessionid} || 0,
                    "addtab "
                      . CGI::escape( $options->{window} . "_tabs" ) . " "
                      . CGI::escape(
                            $options->{window}
                          . "_tabs_cross_"
                          . $crosslinktablename
                      )
                      . " "
                      . CGI::escape(
                        (
                                 $linktabledef->{crosslinklabel}
                              || $linktabledef->{label}
                              || $crosslinktabledef->{crosslinklabel}
                              || $self->{text}->{qx}->{assigned} . " " . $crosstable
                        )
                      )
                );    # , $options->{connection}->{sessionid} || 0);
                if ( $crosslinktabledef->{crossshowastable} ) {
                    $self->createTable(
                        {
                            %$options,
                            table      => $crosslinktablename,
                            crosslink  => $crosstable,
                            crosstable => $options->{table},
                            crossid    => $options->{$UNIQIDCOLUMNNAME},
                            oid        => $options->{oid},

                            #crossdst   => "hidden",
                            name => $options->{window}
                              . "_tabs_cross_"
                              . $crosslinktablename . "_data",
                            hilfe => $curtabledef->{infotext},

                            #nobuttons  => 1,
                        }
                    );
                }
                else {
                    $self->createList(
                        {
                            %$options,
                            table      => $crosslinktablename,
                            crosslink  => $crosstable,
                            crosstable => $options->{table},
                            oid        => $options->{oid},
                            crossid    => $options->{$UNIQIDCOLUMNNAME},
                            name       => $options->{window}
                              . "_tabs_cross_"
                              . $crosslinktablename . "_data",
                            hilfe => $curtabledef->{infotext},

#nobuttons  => 1,
#urlappend  => ",crosslink=".CGI::escape($crosstable).",crossid=".CGI::escape($options->{$UNIQIDCOLUMNNAME}).",crosstable=".CGI::escape($options->{table})
                        }
                    );
                    $self->onUpdateList(
                        {
                            table      => $crosslinktablename,
                            crosslink  => $crosstable,
                            crosstable => $options->{table},
                            connection => $options->{connection},
                            crossid    => $options->{$UNIQIDCOLUMNNAME},
                            curSession => $options->{curSession},
                            oid        => $options->{oid},
                            name       => $options->{window}
                              . "_tabs_cross_"
                              . $crosslinktablename . "_data",
                        }
                    );
                }
                $self->sendToQXForSession(
                    $options->{connection}->{sessionid} || 0,
                    "addobject "
                      . CGI::escape(
                            $options->{window}
                          . "_tabs_cross_"
                          . $crosslinktablename
                      )
                      . " "
                      . CGI::escape(
                            $options->{window}
                          . "_tabs_cross_"
                          . $crosslinktablename . "_data"
                      )
                      . "\n"
                );    # , $options->{connection}->{sessionid} || 0);
            }
        }
    }
}

sub showTabellen
{
    my $self       = shift;
    my $options    = shift;
    my $moreparams = shift;

    unless ( ( !$moreparams ) && $options->{curSession} ) {
        Log(
            "showTabellen: Missing parameters: curSession:"
              . $options->{curSession} . ": !",
            $ERROR
        );
        return undef;
    }

    unless ( $options->{curSession}->{openObjects}->{showTabellen} )
    {
        foreach my $DB ( @{ $self->{dbm}->{dbbackend} } )
        {
            foreach my $curtable (hashKeysRightOrder( $DB->{config}->{DB}->{tables} ) )
            {
                my $db = $self->{dbm}->getDBBackend($curtable);

                #print "showTabellen: ".$db.":".join(",", keys(%$db))."\n";
                my $menuname =
                  $db->{config}->{DB}->{tables}->{$curtable}->{menuname}
                  || $self->{text}->{qx}->{tables} ;
                $poe_kernel->yield(
                    sendToQX => "addmenu "
                      . CGI::escape(
                        ( $menuname eq  $self->{text}->{qx}->{tables} ) ? "" : $self->{text}->{qx}->{tables} )
                      . " "
                      . CGI::escape($menuname) . " "
                      . CGI::escape(
                        $db->{config}->{DB}->{menu}->{$menuname}->{text}
                          || ( ( $menuname eq  $self->{text}->{qx}->{tables} )
                            ? $self->{text}->{qx}->{start} 
                            :  $self->{text}->{qx}->{unnamed} )
                      )
                      . " "
                      . CGI::escape(
                        $db->{config}->{DB}->{menu}->{$menuname}->{icon}
                          || "resource/qx/icon/Tango/32/places/folder.png"
                      )
                  )
                  unless ( $options->{curSession}->{openObjects}->{showTabellen}
                    ->{$menuname} );
                $options->{curSession}->{openObjects}->{showTabellen}
                  ->{$menuname}++;
                next
                  if (
                    ( $db->{config}->{DB}->{tables}->{$curtable}->{qxhidden} )
                    || ( $db->{config}->{DB}->{tables}->{$curtable}->{hidden} )
                  );
                $poe_kernel->yield(
                        sendToQX => "addbutton "
                      . CGI::escape($menuname) . " "
                      . CGI::escape($curtable) . " "
                      . CGI::escape(
                             $db->{config}->{DB}->{tables}->{$curtable}->{label}
                          || $curtable
                      )
                      . " "
                      . CGI::escape(
                        $db->{config}->{DB}->{tables}->{$curtable}->{icon} || ''
                      )
                      . " "
                      . CGI::escape( "job=show,table=" . $curtable )
                );
            }
        }
    }
    $poe_kernel->yield( sendToQX => "addbutton "
          . CGI::escape( $self->{text}->{qx}->{tables} ) . " "
          . CGI::escape("statistic") . " "
          . CGI::escape( $self->{text}->{qx}->{live_stats} ) . " "
          . CGI::escape("icon") . " "
          . CGI::escape("job=statswin") );
}


sub onAuthenticated
{
   my $self = shift;
   my $options = shift;
   my $moreparams = shift || 0;

   unless ((!$moreparams) && $options->{curSession} && $options->{connection})
   {
      Log("onAuthenticated: Missing parameters: curSession:".$options->{curSession}." connection:".$options->{connection}.": !", $ERROR);
      return undef;
   }
   # TODO:FIXME:XXX: noReset macht noch nicht wirklich Sinn....

   $self->resetQX({
      curSession => $options->{curSession},
      connection => $options->{connection},
   })
      unless $options->{noReset};

   $self->showTabellen({curSession => $options->{curSession}})
      unless (defined(my $err = $self->{dbm}->checkRights($options->{curSession}, $ADMIN)) || $options->{noStartMenu});
}

1;
