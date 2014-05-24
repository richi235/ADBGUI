package ADBGUI::DBManager;

use warnings;
use strict;
use Carp;
use Cwd;
use POSIX ();
use Clone qw(clone);

$SIG{__DIE__} = \&confess;

use POE qw( Wheel::Run );
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT getIncludedTables mergeColumnInfos Log md5pw daemonize ReadConfig);
use ADBGUI::DBBackend;
use Email::MIME::CreateHTML;
use Email::Send;

# RefCycle Detection
#use Devel::Cycle qw/find_cycle/;
#use PadWalker;

my $qxsessiontimeout = 240;
my $qxmaxquesize = 4000;

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $DB = shift;
   my $keys = shift;
   my $configfile = shift;
   my $self  = {};
   bless ($self, $class);

   # States, die unsere Handler einnehmen koennen
   $self->{NOSTATE}      = 0;
   $self->{NEW_DATA}     = 1;
   $self->{NEW_DATA_LOG} = 2;
   Log("You need to migrate to multi DB! You have now to use getDBBackend to access the DB Backend!", $WARNING) unless (ref($DB) eq "ARRAY");
   $self->{DBs} = (ref($DB) eq "ARRAY") ? $DB : [$DB];
   $self->{DB} = "YOU NEED TO MIGRAGE!!!";

   my $i = 0;

   # Oeffnet die Konfigurationsdatei, und oeffnet die Ports
   # fuer die Entgegennahme der Laufzeitkonfiguration

   # Das Folgende macht nun ReadConfigAndInit, damit openSocket bereits auf die DB zugreifen kann.
   $self->ReadConfigAndInit($configfile || "/etc/sshplex/dbm.cfg", {
      # Die folgenden Definitionen sollten eigentlich aus der
      # Konfigurationsdatei kommen. Falls diese das nicht tun,
      # werden folgende gewisse Standardwerte verwendet:
      listenip => '127.0.0.1', # Standardmaessig binden wir uns auf localhost
      qooxdoolistenip => '127.0.0.1', # Standardmaessig binden wir uns auf localhost
      readtimeout => 0,        # Wie lange lassen wir einen Connect offen,
                               # der keine Daten schickt? Einheiten: Sekunden
      readlinetimeout => 0,    # So lange warte wir bis eine Zeile fertig
                               # ist (-> "\n" ). Einheiten: Sekunden
      debug  => 0,
   }, $keys);
   #Log("DBManager: Startup: Can't connect to database!", $ERROR) && die
   #   unless ($config->{dbbackend}->db_open());
   #unlink($PIDFILE);
   #$kernel->run();
   #exit(0);

   return $self;
}

sub getIdColumnName {
   my $self = shift;
   my $table = shift;
   my $db = $self->getDBBackend($table);
   return $UNIQIDCOLUMNNAME unless $db;
   return $db->getIdColumnName($table);
}

sub contextAllowed {
   my $self = shift;
   my $contextid = shift;
   my $options = shift;
   return undef if ($contextid eq $options->{curSession}->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)});
   return undef if (exists($options->{curSession}->{context}->{cache}->{$contextid}) && !($options->{mustRevalidate}));
   my $err = $self->checkRights($options->{curSession}, $ADMIN);
   return (defined($err) ? $err->[0] : undef);
}

sub onRunCmd {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{command}) {
      Log("onDelRow: Missing parameters: curSession:".$options->{curSession}.": command:".$options->{command}.":!", $ERROR);
      return undef;
   }
   POE::Session->create(
      inline_states => {
         _start  => sub {
            my ( $kernel, $heap, $shell, $command, $timeout, $poll, $options, $curSession, $filter ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG4, ARG5, ARG6, ARG7 ];
            $heap->{timeout} = $timeout;
            $heap->{shell} = $shell;
            $heap->{command} = $command;
            $heap->{curSession} = $curSession;
            $heap->{options} = $options;
            $heap->{poll} = $poll;
            my $cmd = undef;
            eval {
               $cmd = POE::Wheel::Run->new(
                  Program      => $shell,
                  ProgramArgs  => (ref($command) eq "ARRAY") ? $command : [$command || "/bin/true"],
                  #CloseOnCall => 1,
                  StdoutEvent  => 'output',
                  StderrEvent  => 'outputerr',
                  ErrorEvent   => 'error',
                  CloseEvent   => 'close',
                  StdioFilter  => $filter || POE::Filter::Stream->new(),
               );
            };
            if ($@) {
               if (ref($options->{onCmdError}) eq "CODE") {
                  $options->{onCmdError}($heap, "ERROR STARTING:".$@);
               } else {
                  Log("Qooxdoo: onRunCmd: Unhandled error: ERROR STARTING:".$@, $WARNING);
               }
            }
            $heap->{cmd} = $cmd;
            my $pid = "Unknown";
            if (defined($heap->{cmd})) {
               $pid = $heap->{cmd}->PID;
            }
            if (ref($options->{onCmdInfo}) eq "CODE") {
               $options->{onCmdInfo}($heap, "Program started (PID:".$pid.")");
            }
            if (ref($options->{onCmdStart}) eq "CODE") {
               $options->{onCmdStart}($heap);
            }
            $poe_kernel->delay("timeout" => $heap->{timeout})
               if $heap->{timeout};
            $poe_kernel->delay("poll" => $heap->{poll})
               if ($heap->{poll} && (ref($options->{onCmdPoll}) eq "CODE"));
         },
         poll => sub {
            if (ref($options->{onCmdPoll}) eq "CODE") {
               $options->{onCmdPoll}($_[HEAP]);
            }
            $poe_kernel->delay("poll" => $_[HEAP]->{poll});
         },
         _stop   => sub {
            if (ref($options->{onCmdStop}) eq "CODE") {
               $options->{onCmdStop}($_[HEAP]);
            }
            #print "DONE\n";
         },
         output => sub {
            #print "OUTPUT\n";
            my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
            #$output =~ s,\n,<br>\n,g;
            #$output = $output.(join(",", split(//, $output)));
            if (ref($options->{onCmdRead}) eq "CODE") {
               $options->{onCmdRead}($heap, $output, 0);
            } else {
               Log("Qooxdoo: onRunCmd: Unhandled input: ".length($output)." Bytes", $WARNING);
            }
         },
         outputerr => sub {
            #print "OUTPUT\n";
            my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
            #$output =~ s,\n,<br>\n,g;
            #$output = $output.(join(",", split(//, $output)));
            if (ref($options->{onCmdRead}) eq "CODE") {
               $options->{onCmdRead}($heap, $output, 1);
            } else {
               Log("Qooxdoo: onRunCmd: Unhandled error input: ".length($output)." Bytes", $WARNING);
            }
         },
         error  => sub {
            my ($kernel, $heap, $operation, $errnum, $errstr, $wheel_id) = @_[KERNEL, HEAP, ARG0..ARG3];
            return if ($operation eq "read") && ($errnum == 0);
            if (ref($options->{onCmdError}) eq "CODE") {
               $options->{onCmdError}($heap, [$operation, $errnum, $errstr]);
            } else {
               Log("Qooxdoo: onRunCmd: Unhandled error: operation=".$operation." errnum=".$errnum." errstr=".$errstr, $WARNING);
            }
         },
         close  => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            my $pid = "Unknown";
            my $return = "Unknown";
            #print "CLOSE\n";
            if (defined($heap->{cmd})) {
               $pid = $heap->{cmd}->PID;
               $return = waitpid($pid, 0);
            }
            delete $heap->{cmd};
            if (ref($options->{onCmdInfo}) eq "CODE") {
               $options->{onCmdInfo}($heap, "Program terminated (PID:".$pid.", RET:".$return.")");
            }
            if (ref($options->{onCmdClose}) eq "CODE") {
               $options->{onCmdClose}($heap);
            } else {
               Log("Qooxdoo: onCmdClose: Unhandled", $WARNING);
            }
            $poe_kernel->delay("poll" => undef);
            $poe_kernel->delay("timeout" => undef);
            #print "CLOSEEND\n";
         },
         timeout => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            my $pid = "unknown";
            if (defined($heap->{cmd})) {
               $pid = $heap->{cmd}->PID;
            }
            if (ref($options->{onCmdInfo}) eq "CODE") {
               $options->{onCmdInfo}($heap, "TIMEOUT: Killing process(PID:".$pid.") after ".$heap->{timeout}." seconds.");
            }
            if (ref($options->{onCmdClose}) eq "CODE") {
               $options->{onCmdClose}($heap);
            } else {
               Log("Qooxdoo: onCmdClose: Unhandled", $WARNING);
            }
            $poe_kernel->yield("terminate");
         },
         terminate => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            # TODO:XXX:FIXME: kill() scheint leider nicht zu funktionieren!!!
            $heap->{cmd}->kill()
               if (defined($heap->{cmd}));
         }
      }, args => [ $options->{shell} || "/bin/bash", $options->{command}, $options->{timeout} || $self->{dbm}->{config}->{"cmdtimeout"} || 3600, $options->{poll} || 0, $options, $options->{curSession}, $options->{filter} ],
   );
}

sub setContext {
   my $self = shift;
   my $curSession = shift;
   my $id = shift || 0;
   my $contextkey = shift || "";
   delete $curSession->{context}->{$contextkey}->{id};
   $curSession->{context}->{$contextkey}->{id} = $id if ($id);
}

sub getFilter {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table}) {
      Log("DBManager: getFilter: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return {};
   }
   my $return = {};
   $return = $options->{curSession}->{filter}->{$options->{table}}
      if (exists($options->{curSession}->{filter}->{$options->{table}}) &&
         defined($options->{curSession}->{filter}->{$options->{table}}));
   $return = $options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}->{$options->{table}}
      if (                                                    $options->{prgcontext}   &&
          exists($options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}) &&
          exists($options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}->{$options->{table}}) &&
         defined($options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}->{$options->{table}}));
   #Log("Returning: ".$options->{table}.":".($options->{prgcontext} || "UNDEF").":".join(",", keys %$return), $WARNING);
   return clone($return);
}

sub setFilter {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{filter}) {
      Log("DBManager: setFilter: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.":filter:".$options->{filter}.": !", $ERROR);
      return undef;
   }
   if ($options->{prgcontext}) {
      #Log("SETTING FILTER: ".$options->{table}.":".($options->{prgcontext}).":".join(",", keys %{$options->{filter}}), $WARNING);
      return $options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}->{$options->{table}} = $options->{filter};
   } else {
      #Log("SETTING ALLFILTER: ".$options->{table}.":".join(",", keys %{$options->{filter}}), $WARNING);
      return $options->{curSession}->{filter}->{$options->{table}} = $options->{filter};
   }
   return undef;
}

sub removeFilter {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table}) {
      Log("DBManager: setFilter: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }
   if ($options->{prgcontext}) {
      return delete $options->{curSession}->{prgcontextfilter}->{$options->{prgcontext}}->{$options->{table}};
   } else {
      return delete $options->{curSession}->{filter}->{$options->{table}};
   }
   return undef;
}

sub getDBBackend {
   my $self = shift;
   my $table = shift;
   
   unless (exists($self->{dbbackend})) {
      foreach my $curDB (@{$self->{DBs}}) {
         push(@{$self->{dbbackend}}, $self->createDBBackend({
            debug  => 0,
            DB     => $curDB,
            supassword => $self->{config}->{supassword},
            oldlinklogic => $self->{config}->{oldlinklogic},
         }));
      }
   }
   
   foreach my $dbbackend (@{$self->{dbbackend}}) {
      return $dbbackend
         if ($table && exists($dbbackend->{config}->{DB}->{tables}->{$table}));
   }
   return undef;
}

sub createDBBackend {
   my $self = shift;
   my $params = shift;
   return ADBGUI::DBBackend->new($params);   
}

sub getTableDefiniton {
   my $self = shift;
   my $table = shift;
   my $db = $self->getDBBackend($table);
   return clone($db->{config}->{DB}->{tables}->{$table})
      if (defined($db) && exists($db->{config}->{DB}->{tables}->{$table}));
   return undef;
}

sub ReadConfigAndInit {
   my $self = shift;
   my $configfile = shift;
   my $config = shift;
   my $keys = shift;

   $self->{cwd} = getcwd();
   
   $config = ReadConfig($configfile, $keys, {
      "daemon" => sub {
         my $valueref = shift;
         daemonize() if ($$valueref);
      },
      "changelog" => sub {
         my $valueref = shift;
         unless (open(CHANGELOG, ">>".$$valueref)) {
            Log("ToolsLib: ReadConfigAndInit: Can't open changelogfile :".$$valueref.":", $ERROR);
            die;
         }
         $$valueref = \*CHANGELOG;
      },
   });

   #do {{ Log("ToolsLib: ReadConfigAndInit: No definitions found in config file. ".
   #          "Please check your configfile (".$configfile.")!", $ERROR); die; }} if ($i < 0);
   #if ($self->{dbmanager}) {
   #   Log("Tools: Startup: Can't connect to database!", $ERROR) && die
   #      unless ($self->{dbmanager}->db_open());
   #}
   $self->{config} = $config;
   $self->{sessions} = {};

   @_ = grep { ! defined($self->{config}->{lc($_)}) } @$keys;
   Log("DBManager: openSocket: ".$self->{config}->{lc('Name')}." is missing ".scalar(@_)." required key(s): ".'"'.join(",", @_).'"', $ERROR) if @_;
   Log("DBManager: openSocket: This listening Socket is skipped.", $ERROR) if @_;
   exit if @_;

   if ($self->{config}->{listenip} &&
       $self->{config}->{listenport}) {
      # Telnetserverobjekt erzeugen
      $self->{TelnetServer} = ADBGUI::DBManagerServer->new({
         listenip        => $self->{config}->{listenip},
         listenport      => $self->{config}->{listenport},
         readtimeout     => $self->{config}->{readtimeout},
         readlinetimeout => $self->{config}->{readlinetimeout},
         # Wir verkraften mehrere Clients.
         MultipleConnections => 1
      }, $self);
   } else {
      Log("DBManager: DBManagerServer: Keine oder fehlerhafte DBManagerServer TCP/IP Information. listenip=".$self->{config}->{listenip}." listenport=".$self->{config}->{listenport}, $WARNING);
   }
}

sub getSession {
   my $self = shift;
   my $sessionID = shift;
   $self->clearTimeoutedSessions;
   if (defined($sessionID) && $sessionID && exists($self->{sessions}->{$sessionID})) {
      $self->{sessions}->{$sessionID}->{lastSessionAccessTime} = time();
      return $self->{sessions}->{$sessionID};
   } else {
      return undef;
   }
}

sub outputForked {
   my $self = shift;
   my $session = shift;
   my $function = shift;
   my $params = shift;
   my $forktimeout = shift;
   my $noterminate = shift || 0;
   my $presend = shift;
   my $postsend = shift;
   # ToDo:FIXME:XXX: Es sollte moeglich sein eine Que zu hinterlegen,
   # zum einen pro Client und zum anderen Global.
   POE::Session->create(
      inline_states => {
         _start           => sub {
            $_[HEAP]->{clientsession} = $_[ARG0];
            my $function = $_[ARG1];
            my $params = $_[ARG2];
            my $forktimeout = $_[ARG3];
            $_[HEAP]->{noterminate} = $_[ARG4];
            $_[HEAP]->{presend} = $_[ARG5];
            $_[HEAP]->{postsend} = $_[ARG6];
            #$poe_kernel->yield("loop");
            Log("Running function ".$function, $DEBUG);
            $_[HEAP]->{child} = POE::Wheel::Run->new(
               Program => sub {
                  POSIX::close($_) for 3 .. 1024;
                  alarm($forktimeout || 60);
                  open(OUTCOPY, ">&STDOUT")   or die "Couldn't dup STDOUT: $!";
                  open(STDOUT, ">&STDERR") or die "Can't dup OUTALIAS: $!";
                  syswrite(OUTCOPY, &{$function}($params, \*OUTCOPY, 1));
                  close OUTCOPY;
               },
               StdioDriver  => POE::Driver::SysRW->new,
               StdioFilter  => POE::Filter::Stream->new,
               StdoutEvent  => "got_child_stdout",
               StderrEvent  => "got_child_stderr",
               CloseEvent   => "got_child_close",
            );
            Log("Resuming other things.", $DEBUG);
            $_[KERNEL]->sig_child($_[HEAP]->{child}->PID, "got_child_signal");
            $poe_kernel->post($_[HEAP]->{clientsession} => send_message => $_[HEAP]->{presend})
               if ($_[HEAP]->{clientsession} && $_[HEAP]->{presend});
         }, got_child_stderr => sub {
            my ($stderr_line, $wheel_id) = @_[ARG0, ARG1];
            #$poe_kernel->post($_[HEAP]->{clientsession} => send_message => $stderr_line)
            #   if $_[HEAP]->{clientsession};
            Log($wheel_id." INPUT ".$stderr_line, $WARNING);
         }, got_child_stdout => sub {
            my ($stdout_line, $wheel_id) = @_[ARG0, ARG1];
            $poe_kernel->post($_[HEAP]->{clientsession} => send_message => $stdout_line);
            #Log("STDERR: ", $WARNING);
            #$poe_kernel->post($_[HEAP]->{clientsession} => "shutdown")
            #   unless $_[HEAP]->{noterminate};
         }, got_child_close  => sub {
            my ($wheel_id) = $_[ARG0];
            Log($wheel_id." Child Close", $DEBUG);
            $poe_kernel->call($_[HEAP]->{clientsession} => send_message => $_[HEAP]->{postsend})
               if ($_[HEAP]->{clientsession} && $_[HEAP]->{postsend});
            delete $_[HEAP]->{child};
            $poe_kernel->post($_[HEAP]->{clientsession} => "shutdown")
               unless $_[HEAP]->{noterminate};
         }, got_child_signal => sub {
            my ($wheel_id) = $_[ARG0];
            #Log($wheel_id." Child Signal", $WARNING);
            delete $_[HEAP]->{child};
            $poe_kernel->post($_[HEAP]->{clientsession} => "shutdown")
               unless $_[HEAP]->{noterminate};
         }
      }, args => [ $session, $function, $params, $forktimeout, $noterminate, $presend, $postsend ],
   );
}

sub initialiseUserSession {
   my $self = shift;
   my $connection = shift;
   my $sessionid = shift;
   my $client = shift;
   my $line = shift;
   my $return = undef;
   if (ref($line) eq "HASH") {
      $return = {client => $client};
      $self->deleteSession($sessionid);
      $self->registerSession($return, $sessionid);
      $return->{ip}   = $connection->{ip};
      $return->{port} = $connection->{port};
      foreach my $key (keys %$line) {
         $return->{$key} = $line->{$key};
      }
      $return->{rights} = $self->getRightFlags($return);
   }
   return $return;
}

sub registerSession {
   my $self = shift;
   my $dbline = shift;
   my $sessionID = shift || int(rand(2**48));
   $self->{sessions}->{$sessionID} = $dbline;
   $self->{sessions}->{$sessionID}->{lastSessionAccessTime} = time();
   $self->{sessions}->{$sessionID}->{sessionid} = $sessionID;
   $self->clearTimeoutedSessions;
   return $sessionID;
}

sub clearTimeoutedSessions {
   my $self = shift;
   foreach my $sessionID (keys(%{$self->{sessions}})) {
      my $curSession = $self->{sessions}->{$sessionID};
      #find_cycle($curSession #);
      #  , sub {
      #   my $cycles = shift;
      #   foreach my $curerror (@$cycles) {
      #      Log("ADBGUI::DBMANAGER: CYCLE FOUND:".$curSession.":".join(";", @$curerror), $WARNING);
      #   }
      #});
      if ((ref($curSession->{que}) eq "ARRAY") && 
            (@{$curSession->{que}} > $qxmaxquesize)) {
         Log("Too many qued packets: ".scalar(@{$curSession->{que}})." with the maximum of ".$qxmaxquesize." packets!", $ERROR);
         $self->deleteSession($sessionID);
      } elsif ($curSession->{lastaccess} && ((time() - $curSession->{lastaccess}) > $qxsessiontimeout)) {
         Log("Sessiontimeout for ".$sessionID.": ".(time() - $curSession->{lastaccess})." seconds are over the maximum of ".$qxsessiontimeout." seconds!", $DEBUG);
         $self->deleteSession($sessionID);
      } elsif (($curSession->{lastSessionAccessTime}+$self->{config}->{loginsessiontimeout}) < time()) {
         $self->deleteSession($sessionID);
      }
   }
}

sub deleteSession {
   my $self = shift;
   my $sessionID = shift;
   delete $self->{sessions}->{$sessionID};
}

sub BeforeNewUpdate {
   my $self = shift;
   my $table = shift;
   my $cmd = shift;
   my $columns = shift;
   my $curSession = shift;
   #die("You have to update to the new usage of BeforeNewUpdate!") if shift;
   my $db = $self->getDBBackend($table);
   if ($db->{config}->{DB}->{tables}->{$table}->{readonly}) {
      Log("DBManager: onNewLineServer: NEW: ACCESS DENIED: New/Update in ".($db->{config}->{DB}->{tables}->{$table}->{label}||$table)." not allowed!");
      return "ACCESS DENIED";
   } elsif (($db->{config}->{DB}->{tables}->{$table}->{editonly}) && ($cmd eq "NEW")) {
      Log("DBManager: onNewLineServer: NEW: ACCESS DENIED: New in ".($db->{config}->{DB}->{tables}->{$table}->{label}||$table)." not allowed!");
      return "ACCESS DENIED";
   }
   #$config->{columns}->{statustimestamp} = Tools::MakeTime(time);
   return undef;
}

sub getRightFlags {
   my $self = shift;
   my $curSession = shift;
   my $return = 0;
   $return |= $ADMIN if $curSession->{$USERSTABLENAME.$TSEP.$ADMINFLAGCOLUMNNAME};
   $return |= $MODIFY if $curSession->{$USERSTABLENAME.$TSEP.$MODIFYFLAGCOLUMNNAME};
   return $return;
}

sub isNull {
   my $curcolumndef = shift;
   my $value = shift;
   return 1
      if (($curcolumndef->{type} =~ /date/i) && ($value eq "null"));
   return 1 unless $value; 
   return 0;
}

sub deleteUndeleteDataset {
   my $self = shift;
   my $options = shift;
   my $db = $self->getDBBackend($options->{table});
   my $ok = undef;
   if (uc($options->{cmd}) eq "UNDEL") {
      $ok = $db->undeleteDataSet($options);
   } else {
      $ok = $db->deleteDataSet($options);
   }
   return $ok ? 0 : "(un)deleteDataSet reported error";
}

sub NewUpdateData {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;
   unless ((!$moreparams) && $options->{curSession} && $options->{table} && $options->{cmd} && $options->{columns}) {
      Log("DBManager: NewUpdateData: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return "ACCESS DENIED";
   }
   my $db = $self->getDBBackend($options->{table});
   # ACHTUNG: Wenn irgendwann mal nicht nur der Admin Eintraege Updaten/Anlegen
   # darf, muss unbedingt darauf geachtet werden, dass das Admin-Flag auch nur
   # der Admin setzen darf!
   # Ausserdem darf der User natuerlich dann nur seine eigenen Eintraege, bzw.
   # ggf. die Eintraege fuer User fuer die er Bereichsleiter ist, aendern.
   # Beides ist hier im Moment nicht behandelt und ueberprueft!!11!11einselfelfeins
   if (defined(my $err = $self->checkRights($options->{curSession}, $MODIFY, $options->{table}, $options->{uniqid}))) {
      Log("DBManager: NewUpdateData: NEW/UPDATE: ".$options->{cmd}.": ACCESS DENIED: ".$err->[0], $err->[1]);
      return "ACCESS DENIED";
   }
   if (defined(my $err = $self->BeforeNewUpdate($options->{table}, $options->{cmd}, $options->{columns}, $options->{curSession}))) {
      return $err;
   }
   foreach (keys(%{$options->{columns}})) {
      Log("DBManager: NewUpdateData: NEW/UPDATE: COL:".$_."=".((
         exists($options->{columns}->{$_}) && 
        defined($options->{columns}->{$_})) ?
                $options->{columns}->{$_} : "UNDEFINED").":", $DEBUG);
   }
   foreach my $column (keys(%{$options->{columns}})) {
      my @matchingcolumns = (grep { $column eq $options->{table}.$TSEP.$_ } keys %{$db->{config}->{DB}->{tables}->{$options->{table}}->{columns}});
      #if (scalar(@matchingcolumns>1)) {
      #   Log("DBManager: onNewLineServer: NEW/UPDATE: Multiple matching columns ?! Can't be!!!", $ERROR);
      #   return $self->protokolError($client);
      #}
      unless ($matchingcolumns[0]) {
         Log("DBManager: NewUpdateData: NEW/UPDATE: Column: Unknown column :".$column.": in table :".$options->{table}.":", $WARNING);
         return "Unknown column :".$column.": in table :".$options->{table}.":";
      }      
      my $curcolumndef = mergeColumnInfos($db->{config}->{DB}, $db->{config}->{DB}->{tables}->{$options->{table}}->{columns}->{$matchingcolumns[0]});
      if (!(defined($options->{columns}->{$column}) &&
                    $options->{columns}->{$column})) {
         if ($curcolumndef->{notnull} && (!$curcolumndef->{hidden}) && (!((($curcolumndef->{type} eq $DELETEDCOLUMNNAME) ||
                                                                           ($curcolumndef->{type} eq "boolean")) && defined($options->{columns}->{$column})))) {
            # TODO:XXX:FIXME: Man sollte im Qooxdooformular die entsprechende Spalte rot highlight und den Cursor gleich reinsetzen.
            Log("DBManager: NewUpdateData: NEW/UPDATE: Column: :".$column.": must have a value!", $WARNING);
            return '"'.($curcolumndef->{label} || $matchingcolumns[0]).'"'." darf nicht leer sein!";
         }
      } else {
         $options->{columns}->{$column} =~ s/,/./gi
            if $curcolumndef->{replacecommas};
         if (isNull($curcolumndef, $options->{columns}->{$column})) {
            if ($curcolumndef->{notnull}) {
               # TODO:XXX:FIXME: Man sollte im Qooxdooformular die entsprechende Spalte rot highlight und den Cursor gleich reinsetzen.
               Log("DBManager: NewUpdateData: NEW/UPDATE: Column: :".$column.": failed syntaxcheck ".$curcolumndef->{syntaxcheck}." !", $WARNING);
               return "".((!$curcolumndef->{label} || ($curcolumndef->{label} =~ m,^\s*$,)) ? $matchingcolumns[0] : '"'.$curcolumndef->{label}.'"')." darf nicht leer sein!";
            }
         } elsif ($curcolumndef->{syntaxcheck} && ($options->{columns}->{$column} !~ $curcolumndef->{syntaxcheck})) {
            # TODO:XXX:FIXME: Man sollte im Qooxdooformular die entsprechende Spalte rot highlight und den Cursor gleich reinsetzen.
            Log("DBManager: NewUpdateData: NEW/UPDATE: Column: :".$column.": failed syntaxcheck ".$curcolumndef->{syntaxcheck}." !", $WARNING);
            return "".((!$curcolumndef->{label} || ($curcolumndef->{label} =~ m,^\s*$,)) ? $matchingcolumns[0] : '"'.$curcolumndef->{label}.'"')." hat mit ".'"'.$options->{columns}->{$column}.'"'." ein falsches Format!".($curcolumndef->{syntaxchecktext} ? " ".$curcolumndef->{syntaxcheck} : "");
         }
      }
      # Secrets koennen nicht mit "" ueberschrieben werden.
      # Sonst ist das Passwort weg, wenn man was aendert...
      delete $options->{columns}->{$column} if ((!$options->{columns}->{$column}) &&
         $curcolumndef->{secret});
      if (exists($options->{columns}->{$column}) &&
         defined($options->{columns}->{$column}) && 
                 $options->{columns}->{$column} &&
            ($curcolumndef eq "password")) {
         $options->{columns}->{$column} = md5pw($options->{columns}->{$column});
      }
   }
   my $ret = undef;
   if ($options->{cmd} eq "NEW") {
      $ret = $db->insertDataSet({
         table => $options->{table},
         columns => $options->{columns},
         session => $options->{curSession},
         wherePre => $self->Where_Pre($options)
      });
   } elsif ($options->{cmd} eq "UPDATE") {
      $ret = $db->updateDataSet({
         table => $options->{table},
         $UNIQIDCOLUMNNAME => $options->{uniqid},
         nodeleted => $options->{nodeleted},
         searchdef => $self->getFilter({ curSession => $options->{curSession}, table => $options->{table} }),
         columns => $options->{columns},
         session => $options->{curSession},
         wherePre => $self->Where_Pre($options)
      });
   } else {
      Log("DBManager: NewUpdateData: NEW/UPDATE: Unknown command: ".$options->{cmd}, $ERROR);
   }
   unless (defined($ret)) {
      Log("DBManager: onNewLineServer: NEW/UPDATE: ".$options->{cmd}." ".$options->{table}." FAILED: SQL Query failed.", $WARNING);
      return "INTERNAL ERROR";
   }
   return $ret;
}

sub loginUser {
   my $self = shift;
   my $user = shift;
   my $pass = shift;
   my $su = shift;
   die if shift;
   my $db = $self->getDBBackend($USERSTABLENAME);
   if (my $dbline = $db->verifyLoginData($user, $pass, $su)) {
      return $dbline;
   }
   return undef;
}

sub LineHandler {
   my $self = shift;
   $_ = shift;
   my $client = shift;
   my $connection = $client->getTrackingHash();
   my $onConnect = shift;

   no warnings 'uninitialized';
   if ($onConnect) {
      $connection->{state} = $self->{NOSTATE};
   } else {
      Log("DBManager: onNewLineServer: LINE:".$_.":", $DEBUG);
      my $curSession = $self->getSession($connection->{sessionID});
      if (/^AUTH\s(\S+)(\s(\S+))?(\s(\S+))?$/) {
         my $user = $1;
         my $pass = $3;
         my $su = $5;
         if (defined(my $err = $self->checkRights($curSession, $NOTHING))) {
            $client->send("AUTH FAILED\n");
            return Log("DBManager: onNewLineServer: AUTH: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         if (my $dbline = $self->loginUser($user, $pass, $su)) {
            $connection->{sessionID} = $self->registerSession($dbline);
         }
         if ($connection->{sessionID}) {
            $curSession = $self->getSession($connection->{sessionID});
            $client->send("AUTH OK ".$connection->{sessionID}." ".$self->getRightFlags($curSession)."\n");
         } else {
            Log("DBManager: onNewLineServer: SESSION: Session not found.", $DEBUG);
            delete $connection->{sessionID};
            return $client->send("AUTH FAILED\n");
         }
      } elsif (/^SESSION\s(\S+)$/) {
         $connection->{sessionID} = $1;
         if (defined(my $err = $self->checkRights($curSession, $NOTHING))) {
            $client->send("SESSION FAILED\n");
            delete $connection->{sessionID};
            return Log("DBManager: onNewLineServer: SESSION ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         if ($curSession = $self->getSession($connection->{sessionID})) {
            $client->send("SESSION OK ".$curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME}." ".$self->getRightFlags($curSession)."\n");
         } else {
            Log("DBManager: onNewLineServer: SESSION: Unknown SESSION!", $INFO);
            delete $connection->{sessionID};
            return $client->send("SESSION FAILED\n");
         }
      } elsif (/^LOGOUT$/) {
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION))) {
            $client->send("LOGOUT FAILED\n");
            return Log("DBManager: onNewLineServer: LOGOUT ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         $self->deleteSession($connection->{sessionID});
         delete $connection->{sessionID};
         $client->send("LOGOUT OK\n");
         $client->close;
      } elsif (/^PING$/) {
         if (defined(my $err = $self->checkRights($curSession, $NOTHING))) {
            $client->send("PING FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: PING: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         $client->send("PONG\n");
      } elsif (/^GET\s(\S+)(\s(\S*))?(\s(\S*))?(\s(\S*))?(\s(\S*))?(\s(\S*))?$/) {
         my $table = $1;
         my $uniqid = $3;
         my $from = $5;        # Zeilenauswahlstart
         my $linecount = $7;   #       -anzahl
         my $sortby = $9;
         my $backref = $11;
         #Log("INSTR:".$backref.":", $DEBUG);
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table, $uniqid))) {
            $client->send("GET ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: GET: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         my $searchdef = $self->getFilter({ curSession => $curSession, table => $table });
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         $uniqid = undef if (defined($uniqid) && ($uniqid eq "")); # 0 ist OK, nur "" bedeuted undef, was wir hier normalisieren muessen.
         my $ret;
         #if (($table eq "ACCESS_LOG") && !($curSession->{$USERSTABLENAME.$TSEP.$ADMINFLAGCOLUMNNAME})) {
         #   Log("DBManager: onNewLineServer: GET ".$table." FAILED No permission to table ".$table, $WARNING);
         #   return $client->send("GET ".$table." FAILED No permission to table ".$table."\n");
         #}
         my $db = $self->getDBBackend($table);
         unless (defined($ret = $db->getDataSet({
            table => $table,
            $UNIQIDCOLUMNNAME => $uniqid,
            skip => $from,
            rows => $linecount,
            searchdef => $searchdef,
            sortby => $sortby,
            wherePre => $self->Where_Pre({ curSession => $curSession, table => $table }),
            tablebackrefs => $backref,
            session => $curSession
         })) && (ref($ret) eq "ARRAY")) {
            Log("DBManager: onNewLineServer: GET ".$table." FAILED SQL Query failed.", $WARNING);
            return $client->send("GET ".$table." FAILED\n")
         }
         my $i = 0;
         my $j = 0;
         #print "UUUUIO:".join(",", keys(%$searchdef)).":\n";
         $client->send("GET ".$table." BEGIN ".$ret->[1]." ".(scalar(keys(%$searchdef))?1:0)."\n");
         foreach my $dbline (@{$ret->[0]}) {
            $client->send("GET ".$table." NEXT ".$ret->[1]." ".(scalar(keys(%$searchdef))?1:0)."\n") if $j++;
            foreach my $column (keys(%$dbline)) {
               # Damit nicht kommt "Use of uninitialized value in concatenation (.) or string..."
               $dbline->{$column} = '' unless (defined($dbline->{$column}) && ($dbline->{$column} || ($dbline->{$column} ne '')));
               #$dbline->{$column} =~ s/\#/##/g;
               # TODO:FIXME:XXX: Das ist absolut boese... Zeilenumbrueche funktionieren de fakto gar nicht... Durch escapen oder am besten JSON loesen!
               $dbline->{$column} =~ s/(\r?\n)/#13/g;
               $client->send($column.": ".$dbline->{$column}."\n");
            }
         }
         $client->send("GET ".$table." END ".scalar($ret->[1])." ".(scalar(keys(%$searchdef))?1:0)."\n");
      } elsif (/^GETTABLEINFO\s(\S+)$/) {
         my $table = $1;
         my $searchdef = $self->getFilter({ curSession => $curSession, table => $table });
         my $ret = undef;
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table, undef))) {
            $client->send("GETTABLEINFO ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: GETTABLEINFO: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         my $db = $self->getDBBackend($table);
         unless (defined($ret = $db->getTableInfo($table, $searchdef)) && (ref($ret) eq "ARRAY")) {
            Log("DBManager: onNewLineServer: GETTABLEINFO: SQL Query failed for table :".$table.":", $WARNING);
            return $client->send("GETTABLEINFO ".$table." FAILED\n")
         }
         unless (scalar(@{$ret}) == 1) {
            Log("DBManager: onNewLineServer: GETTABLEINFO: Got :".scalar(@{$ret}).": row for INFO-Question for table :".$table.":!", $WARNING);
            return $client->send("GETTABLEINFO ".$table." FAILED\n")
         }
         $client->send("GETTABLEINFO ".$table." BEGIN\n");
         my $j = 0;
         foreach my $column (keys(%{$ret->[0]})) {
            # Damit nicht kommt "Use of uninitialized value in concatenation (.) or string..."
            #$ret->[0]->{$column} = '' unless $ret->[0]->{$column};
            $client->send($column.": ".$ret->[0]->{$column}."\n");
         }
         $client->send("GETTABLEINFO ".$table." END\n");
      } elsif (/^GETGROUPED\s(\S+)\s(\S+)$/) {
         my $table = $1;
         my $column = $2;
         my $searchdef = $self->getFilter({ curSession => $curSession, table => $table }),;
         if (defined(my $err = $self->checkRights($curSession, $ADMIN, $table, undef))) {
            $client->send("GETGROUPED ".$table." ".$column." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: GETGROUPED: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         my $ret;
         my $db = $self->getDBBackend($table);
         unless (defined($ret = $db->getDataSet({
            table => $table, 
            searchdef => $searchdef,
            groupcolumn => $column,
            wherePre => $self->Where_Pre({ curSession => $curSession, table => $table }),
            session => $curSession
         })) &&(ref($ret) eq "ARRAY")) {
            Log("DBManager: onNewLineServer: GETGROUPED ".$table." ".$column." FAILED SQL Query failed.", $WARNING);
            return $client->send("GETGROUPED ".$table." ".$column." FAILED\n")
         }
         $client->send("GETGROUPED ".$table." ".$column." BEGIN ".$ret->[1]."\n");
         my $j = 0;
         foreach my $dbline (@{$ret->[0]}) {
            $client->send("GETGROUPED ".$table." ".$column." NEXT ".$ret->[1]."\n") if $j++;
            foreach my $column (keys(%$dbline)) {
               # Damit nicht kommt "Use of uninitialized value in concatenation (.) or string..."
               #$dbline->{$column} = '' unless $dbline->{$column};
               $client->send($column.": ".$dbline->{$column}."\n");
            }
         }
         $client->send("GETGROUPED ".$table." ".$column." END ".scalar($ret->[1])."\n");
      } elsif (/^((UN)?DEL)\s(\S+)\s(\S+)$/) {
         my $cmd = $1;
         my $table = $3;
         my $uniqid = $4;
         if (defined(my $err = $self->checkRights($curSession, $MODIFY, $table, $uniqid))) {
            $client->send($cmd." ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: ".$cmd.": ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         my $db = $self->getDBBackend($table);
         if (($db->{config}->{DB}->{tables}->{$table}->{readonly}) || ($db->{config}->{DB}->{tables}->{$table}->{editonly})) {
            $client->send($cmd." ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: ".$cmd.": ACCESS DENIED: ACCESS_LOG not allowed!");
         }
         if ($self->{config}->{changelog}) {
            unless (syswrite($self->{config}->{changelog}, localtime(time)." ".
               $curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME}." ".$_."\n")) {
               Log("Unable to write change to Changelog!", $ERROR);
               die;
            }
         }
         my $ok = undef;
         $connection->{columns}->{$table.$TSEP.$self->getIdColumnName($table)} = $uniqid;
         if (defined(my $err = $self->BeforeNewUpdate($table, $cmd, $connection->{columns}, $curSession))) {
            return $client->send($cmd." ".$table." FAILED ".$err."\n");
         }
         my $params = {
            table => $table,
            $UNIQIDCOLUMNNAME => $uniqid,
            session => $curSession
         };         if (uc($cmd) eq "UNDEL") {
            $ok = $db->undeleteDataSet($params);
         } else {
            $ok = $db->deleteDataSet($params);
         }
         if ($ok) {
            $client->send($cmd." ".$table." OK\n");
        } else {
            Log("DBManager: onNewLineServer: ".$cmd." ".$table." FAILED: SQL Query failed.", $ERROR);
            return $client->send($cmd." ".$table." FAILED\n");
         }
      } elsif (/^PASSWD\s(\S+)(\s(\S+)?)$/) {
         my $password = $1;
         my $username = $3 || '';
         if (defined(my $err = $self->checkRights($curSession, $username ? $ADMIN : $ACTIVESESSION))) {
            $client->send("PASSWD".($username ? " ".$username : "")." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: PASSWD: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         unless ($password) { 
            Log("DBManager: onNewLineServer: PASSWD: Empty passwords are not allowed!", $ERROR);
            return $client->send("PASSWD".($username ? " ".$username : "")." FAILED Empty password!\n");
         }
         my $db = $self->getDBBackend($USERSTABLENAME);
         my $userid = $curSession->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)};
         my $ret = undef;
         if ($username) {
            $userid = undef;
            unless (defined($ret = $db->getDataSet({
               table => $USERSTABLENAME,
               simple => 1,
               wherePre => ["(".$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME."='".$username."')"],
               session => $curSession
            })) && (ref($ret) eq "ARRAY")) {
               Log("DBManager: onNewLineServer: PASSWD: GET ".$USERSTABLENAME." FAILED SQL Query failed.", $WARNING);
               return $client->send("PASSWD".($username ? " ".$username : "")." FAILED Internal error.\n")
            }
            if (scalar(@{$ret->[0]}) == 1) {
               $userid = $ret->[0]->[0]->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)};
            } else { 
               Log("DBManager: onNewLineServer: PASSWD: More than one user for username ".$username, $ERROR);
               return $client->send("PASSWD".($username ? " ".$username : "")." FAILED Internal error.\n");
            }
         }
         unless (defined($userid) && $userid) {
            Log("DBManager: onNewLineServer: PASSWD: I don't have your UniqID!", $ERROR);
            return $client->send("PASSWD".($username ? " ".$username : "")." FAILED Internal error.\n");
         }
         my $curcolumn = mergeColumnInfos($db->{config}->{DB}, $db->{config}->{DB}->{tables}->{$USERSTABLENAME}->{columns}->{$PASSWORDCOLUMNNAME});
         $ret = $db->updateDataSet({
            table   => $USERSTABLENAME,
            $UNIQIDCOLUMNNAME      => $userid,
            session => {},
            columns => { $USERSTABLENAME.$TSEP.$PASSWORDCOLUMNNAME => ($curcolumn->{secret} ? md5pw($password) : $password) },
            user    => $curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME},
         });
         if (defined($ret)) {
            $client->send("PASSWD".($username ? " ".$username : "")." OK\n");
         } else {
            Log("DBManager: onNewLineServer: PASSWD FAILED: changepassword failed.", $ERROR);
            return $client->send("PASSWD FAILED Unknown error.\n");
         }
     } elsif (/^(FILTERRESET)(\s+(\S+))?$/) {
         my $table = $3;
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION))) {
            $client->send("FILTERRESET FAILED\n");
            return Log("DBManager: onNewLineServer: FILTERRESET: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         $self->removeFilter({ curSession => $curSession, table => $table }),
         $client->send("FILTERRESET OK\n");
     } elsif (/^(SETFILTER)\s(\S+)\s(\S+)(\s(\S+))?$/) {
         my $cmd = $1;
         my $table = $2;
         my $action = $3;
         my $or = $5;
         if ($action eq "BEGIN") {
            return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
            $connection->{state} = $self->{NEW_DATA};
            $connection->{table} = $table;
            $connection->{columns} = {};
         } elsif ($action eq "END") {
            return $self->protokolError($client) unless ($connection->{state} == $self->{NEW_DATA});
            $connection->{state} = $self->{NOSTATE};
            # TODO: Admin/Modify m�ssen auf die neue Bedeutung angepasst werden.
            if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table))) {
               $client->send($cmd." ".$table." FAILED ACCESS DENIED\n");
               return Log("DBManager: onNewLineServer: SETFILTER: ".$cmd.": ACCESS DENIED: ".$err->[0], $err->[1]);
            }
            foreach (keys(%{$connection->{columns}})) {
               Log("DBManager: onNewLineServer: SETFILTER: COL:".$_."=".$connection->{columns}->{$_}.":", $DEBUG);
            }
            my $ret = undef;
            #my $db = $self->getDBBackend($table);
            #my $mergedcolumns = getIncludedTables($db, $table, 1);
            # TODO:FIXME:XXX: Sollten wir ung�ltige SETFILTER-Spalten bereits hier erkennen, oder
            #                 erst beim getSQLSTringForTable?
            #foreach my $column (keys(%{$config->{columns}})) {
            #   $column =~ s/_(begin|end|active|selected)//;
            #   unless (($column && defined($db->{config}->{DB}->{tables}->{$table}->{columns}->{$column})) ||  
            #      ($or && (grep { my $tmp=$_; grep { $tmp."_".$_ eq $column }  keys %{$db->{config}->{DB}->{tables}->{$tmp}->{columns}} } keys %{$db->{config}->{DB}->{tables}})) ||
            #      scalar(grep { my $tmp=$_; grep { $tmp."_".$_ eq $column } @{$mergedcolumns->{$tmp}} } keys %$mergedcolumns)) {
            #      Log("DBManager: onNewLineServer: SETFILTER: Column: Unknown column :".$column, $ERROR);
            #      return $client->send($cmd." ".$table." FAILED Unknown column :".$column.":\n");
            #   }
            #}
            $or ? $connection->{columns}->{orsearch} = 1 : delete $connection->{columns}->{orsearch};
            $self->setFilter({ curSession => $curSession, table => $table, filter => $connection->{columns} });
            $client->send($cmd." ".$table." OK\n");
         } else {
            return $self->protokolError($client);
         }         
     } elsif (/^(GETFILTER)\s(\S+)$/) {
         my $cmd = $1;
         my $table = $2;
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table))) {
            $client->send($cmd." ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: GETFILTER: ".$cmd.": ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         $client->send($cmd." ".$table." BEGIN\n");
         my $filter = $self->getFilter({ curSession => $curSession, table => $table });
         foreach my $key (keys %$filter) {
            $client->send($key.": ".$filter->{$key}."\n");
         }
         $client->send($cmd." ".$table." END\n");
      } elsif (/^(NEW|UPDATE)\s(\S+)\s(\S+)(\s(\S+))?$/) {
         if ($self->{config}->{changelog}) {
            unless (syswrite($self->{config}->{changelog}, localtime(time)." ".
               $curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME}." ".$_."\n")) {
               Log("Unable to write change to Changelog!", $ERROR);
               die;
            }
         }
         my $cmd = $1;
         my $table = $2;
         my $action = $3;
         my $uniqid = undef;
         if (defined($5)) { $action = $5; $uniqid = $3; }
         if ($action eq "BEGIN") {
            return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
            $connection->{state} = $self->{NEW_DATA_LOG};
            $connection->{table} = $table;
            $connection->{columns} = {};
         } elsif ($action eq "END") {
            return $self->protokolError($client) unless ($connection->{state} == $self->{NEW_DATA_LOG});
            $connection->{state} = $self->{NOSTATE};
            my $ret = undef;
            # Wir machen erst hier ACCESS DENIED, da wir ansonsten bereits beim
            # BEGIN in b�sem Zustand sind. Wenn dann der Client einfach trotzdem
            # seine Daten schickt, gibts den Connection Close, und der Client
            # checked gar nix mehr. Also warten wir ab bis er gesagt hat was er
            # sagen will, und verweigern dann.
            if (defined($ret = $self->NewUpdateData({
               cmd => $cmd,
               table => $table,
               columns => $connection->{columns},
               uniqid => $uniqid,
               curSession => $curSession
            })) && ($ret !~ /^\d+/)) {
               $client->send($cmd." ".$table." FAILED".($ret ? " ".$ret : "")."\n");
            } else {
               $client->send($cmd." ".$table." OK\n");
            }
            delete $connection->{columns};
         } else {
            return $self->protokolError($client);
         }
      } elsif (/^ACTIVATE\s+(\S+)(\s*(.*))$/) {
         my $action = lc($1);
         my $params = [grep { /^[a-zA-Z0-9]+$/ } split(" ", $3)];
         if (exists($self->{config}->{"activatecmd".$action}) && ($self->{config}->{"activatecmd".$action})) {
            my $tmpsession = POE::Session->create(
               inline_states => {
                  _start  => sub {
                      my ( $kernel, $heap, $session, $config ) = @_[ KERNEL, HEAP, SESSION, ARG0 ];
                      $heap->{config} = $config;
                      $kernel->yield("activate_startup");
                  },
                  _stop   => sub {
                     Log("custom_Server_Cmd: activate_error: Stopped.", $DEBUG);
                  },
                  activate_startup  => sub {
                     my ($kernel, $heap) = @_[KERNEL, HEAP];
                     my $config = $heap->{config};
                     my $cmdrunning;
                     eval {
                        Log("custom_Server_Cmd: params: :".join(";", @$params).":", $DEBUG); 
                        $cmdrunning = POE::Wheel::Run->new(
                           Program     => $config->{"activatecmd".$action},
                           ProgramArgs => $params,
                           StdoutEvent => 'activate_output',
                           StderrEvent => 'activate_output',
                           ErrorEvent  => 'activate_error',
                           CloseEvent  => 'activate_close'
                        );
                     };
                     $config->{cmdrunning} = $cmdrunning;
                     Log("custom_Server_Cmd: activate_startup: I run :"."/bin/bash -c '".$config->{"activatecmd".$action}." 2>&1'".":", $DEBUG);
                     if ($@) {
                        chomp $@;
                        $client->send("ACTIVATE FAIL\n");
                        Log("custom_Server_Cmd: activate_error: POE::Wheel::Run-Error: ".$@, $ERROR);
                        Log("custom_Server_Cmd: activate_error: Faild to run :"."/bin/bash -c '".$config->{"activatecmd".$action}." &'".": ".$@, $ERROR);
                     }
                  },
                  activate_output =>  sub {
                     my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
                     my $config = $heap->{config};
                     Log("custom_Server_Cmd: activate_output: I read :".$output.":", $DEBUG);
                     $client->send("ACTIVATE BEGIN\n") unless $heap->{sentbegin}++;
                     $client->send($output."\n");
                  },
                  activate_error  => sub {
                     my ($kernel, $heap, $operation, $errnum, $errstr, $wheel_id) = @_[KERNEL, HEAP, ARG0..ARG3];
                     # ignore senseless message
                     return if $operation eq "read" && $errnum == 0;
                     Log("custom_Server_Cmd: activate_error: ERROR: ".$operation." error ".$errnum.": ".$errstr, $ERROR);
                     $client->send("ACTIVATE FAIL\n");
                  },
                  activate_close => sub {
                     my ($kernel, $heap, $wheel_id) = @_[KERNEL, HEAP, ARG0];
                     my $config = $heap->{config};
                     $client->send("* End *\n");
                     $client->send("ACTIVATE END\n");
                     Log("custom_Server_Cmd: activate_close: Program exited.", $INFO);
                  }
               },
               args => [ $self->{config} ]
            );
         } else {
            Log("custom_Server_Cmd: activate_error: ERROR: The action :".$action.": is not configured in config file!", $ERROR);
            $client->send("ACTIVATE FAILED\n");
         }
      } elsif (/^ASSIGNFILE\s(\S+)\s(\S+)$/) {
         my $table = $1;
         my $filename = $2;
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table))) {
            $client->send("ASSIGNFILE ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: ASSIGNFILE: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         my $ret;
         my $db = $self->getDBBackend($table);
         if ($db->{config}->{DB}->{type} =~ /^CSV$/i) {
            unless ($ret = $db->assignFileToDynTable($table, $filename)) {
               Log("DBManager: onNewLineServer: ASSIGNFILE ".$table." failed: Not a CSV Database!", $WARNING);
               return $client->send("ASSIGNFILE ".$table." FAILED\n")
            }
            return $client->send("ASSIGNFILE ".$table." OK\n")
         } else {
            return $client->send("ASSIGNFILE ".$table." FAILED\n");
         }
      } elsif (/^GETASSIGNFILES\s(\S+)$/) {
         my $table = $1;
         if (defined(my $err = $self->checkRights($curSession, $ACTIVESESSION, $table))) {
            $client->send("GETASSIGNFILES ".$table." FAILED ACCESS DENIED\n");
            return Log("DBManager: onNewLineServer: GETASSIGNFILES: ACCESS DENIED: ".$err->[0], $err->[1]);
         }
         return $self->protokolError($client) unless ($connection->{state} == $self->{NOSTATE});
         my $db = $self->getDBBackend($table);
         my $files = $db->getAvailableDynTableFiles($table);
         if (ref($files) eq "HASH") {
            $client->send($self->sendAssignFiles($self->filterAssignFiles({
               table => $table,
               files => $files,
               active => $db->getCurrentDynTableFile($table),
               session => $curSession
            })));
         } else {
            Log("DBManager: GETASSIGNFILES: getAvailableDynTableFiles: did not return ARRAY but: '".ref($files)."'", $WARNING);
            $client->send($self->sendAssignFiles($self->filterAssignFiles({
               table => $table,
               files => {},
               active => '',
               session => $curSession
            })));
         }
      } elsif ((($connection->{state} == $self->{NEW_DATA}) || ($connection->{state} == $self->{NEW_DATA_LOG})) && (/^(\S+):\s(.*)$/)) {
         if ($self->{config}->{changelog} && ($connection->{state} == $self->{NEW_DATA_LOG})) {
            unless (syswrite($self->{config}->{changelog}, localtime(time)." ".
               $curSession->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME}." ".$_."\n")) {
               Log("Unable to write change to Changelog!", $ERROR);
               die;
            }
         }
         $connection->{columns}->{lc($1)} = $2;
         Log("DBManager: onNewLineServer: SET :".$1.":=:".$2.":", $DEBUG);
      } else {
         Log("DBManager: onNewLineServer: UNKNOWN COMMAND: Dropping bad client.", $WARNING);
         return $self->protokolError($client, "UNKNOWN COMMAND");
      }
   }
   use warnings;
} 

sub sendAssignFiles {
   my $self = shift;
   my $options = shift;
   my $ret = '';
   $ret .= "GETASSIGNFILES ".$options->{table}." BEGIN\n";
   foreach my $file (keys %{$options->{files}}) {
      $ret .= "filename: ".$file."\n";
      $ret .= "mtime: ".$options->{files}->{$file}->[9]."\n";
      $ret .= "active: ".$file."\n" if ($file eq $options->{active});
   }
   $ret .= $options->{addlines} if $options->{addlines};
   $ret .= "GETASSIGNFILES ".$options->{table}." END\n";
   return $ret;
}

sub filterAssignFiles {
   my $self = shift;
   my $options = shift;
   return $options;
}

sub protokolError {
   my $self = shift;
   my $client = shift;
   my $error = shift || 'UNSPECIFIED';
   $client->send("PROTOKOLL ERROR; CLOSING CONNECTION: ".$error."\n");
   $client->close;
}

sub Where_Pre {
   my $self = shift;
   my $a = shift;
   my $b = shift;
   my $moreparams = shift;
   my $options = undef;
   if ($b) {
      $options->{curSession} = $a;
      $options->{table} = $b;
   } else {
      $options = $a;
   }
   unless ((!$moreparams) && $options->{curSession} && $options->{table}) {
      Log("DBManager: Where_Pre: Missing parameters: table:".$options->{table}.":curSession:".$options->{curSession}.": !", $ERROR);
      return "ACCESS DENIED";
   }
   return (defined(my $err = $self->checkRights($options->{curSession}, $ADMIN))) ? [] : undef;
}

sub checkRights {
   my $self = shift;
   my $session = shift;
   my $rights  = shift;
   my $table   = shift || undef;
   my $id      = shift || undef;

   return [$ERROR, "No needed rights given!"] unless defined($rights);
   if ($rights & $ACTIVESESSION) {
      unless ($session) {
         return ["No active session, please first login!", $WARNING];
      }
      unless ($session->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)}) {
         return ["No UserID in current session! CAPITAL ERROR!", $ERROR];
      }
   }
   my $tmp = 0;
   $tmp |= $ADMIN if $session->{$USERSTABLENAME.$TSEP.$ADMINFLAGCOLUMNNAME};
   $tmp |= $MODIFY if $session->{$USERSTABLENAME.$TSEP.$MODIFYFLAGCOLUMNNAME};
   foreach ([$ADMIN,                  "No summary permission!"],
            [$MODIFY,                 "No change permission!" ]
            )
   {
      return [$_->[1], $WARNING] unless ((!($rights & $_->[0])) || ($tmp & $_->[0]));
   }
   my $db = $self->getDBBackend($table);
   unless ((!defined($table)) || grep { $table eq $_ } keys(%{$db->{config}->{DB}->{tables}})) {
      return ["Requested Table :".$table.": doesn't exist in its DB Manager !", $ERROR];
   }
   unless ((!defined($id)) || ($id =~ /^\d+$/)) {
      return ["ID '".$id."' not numeric!", $ERROR];
   }
   return undef;
}

sub isMarked {
   my $self = shift;
   my $onlyWithMark = shift;
   my $marks = shift;
   return 1 unless ($onlyWithMark && (ref($onlyWithMark) eq "ARRAY") && scalar($onlyWithMark));
   return 1 if ($marks && (ref($marks) eq "ARRAY") && scalar(@$marks) && scalar(grep { my $curmark = $_; grep { $curmark eq $_ } @$onlyWithMark } @$marks));
   return 0;
}

sub sendTheMail {
   my $self = shift;
   my $options = shift;
   my $moreparams = shift;

   unless ((!$moreparams) && $options->{curSession} && $options->{to} && $options->{mailbody}) {
      Log("DBManager: sendTheMail: Missing parameters: curSession:".$options->{curSession}.": !", $ERROR);
      return undef;
   }

   my $email = Email::MIME->create_html(
     header => [
         From => $options->{from} || $self->{config}->{sourceemail} || 'no-reply@adbgui.org',
         To => $options->{to},
         Subject => $options->{subject} || "ADBGUI Mail without subject specified",
      ],
      body => $options->{mailbody},
      text_body => "You have a non-HTML mailreader, you cannot read this email.",
   );
   my $sender = Email::Send->new({mailer => 'SMTP'});
   $sender->mailer_args([Host => $self->{config}->{mailhost} || '127.0.0.1']);
   return $sender->send($email);
}

package ADBGUI::DBManagerServer;

use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT getIncludedTables Log);
use ADBGUI::TelnetServer;

our @ISA = ("ADBGUI::TelnetServer");

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $self = ADBGUI::TelnetServer->new(shift);
   $self->{parent} = shift;
   bless ($self, $class);
   return $self;
}

sub LineHandler {
   my $self = shift;
   $_ = shift;
   my $client = shift;
   my $onConnect = shift;

   #Log("DBManager: DBManagerServer: ".($onConnect ? "Connected." : "Read ".$_), $DEBUG);
   $self->{parent}->LineHandler($_, $client, $onConnect);
}

1;
