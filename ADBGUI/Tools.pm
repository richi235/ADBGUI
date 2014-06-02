package ADBGUI::Tools;

use strict;
use warnings;
use Carp qw(cluck confess);

BEGIN {
   use Exporter;
   our @ISA = qw/Exporter/;
   our @EXPORT = qw/$LOG_SYSLOG $LOG_STDERR $LOG_STDOUT $loglevel $logdst/;
   our @EXPORT_OK = qw/daemonize mergeColumnInfos hashKeysRightOrder ensureLength
                       getAffectedColumns simplehashclone arraycompare getFileUploadJavascriptForIDs
                       hashcompare padNumber time2human time2sql normaliseLine queryLDAP
                       Log MakeTime getIncludedTables makeInfoLine new_anon_scalar
                       getTimeLineHTML printLine printLineNospan htmlUnEscape removeTime
                       beschriftung cutDateInfos preZero toDateObj hidebegin hideend
                       md5crypt md5pw secsToHours hoursToHourMinute getURL ReadConfig/;
}

use Digest::MD5;
use Unix::Syslog qw(:macros :subs);
use POSIX qw(errno_h setsid);
use ADBGUI::BasicVariables;
use Time::HiRes qw(gettimeofday);
use POE;
#use DateTime;

# Logarten
our $LOG_STDOUT = 2**0;
our $LOG_STDERR = 2**1;
our $LOG_SYSLOG = 2**2;

our $logdst = $LOG_STDOUT;
our $loglevel = $INFO;

sub removeTime {
   my $text = shift;
   if (defined($text) && ($text =~ m,^(\d+)\-(\d+)\-(\d+)\s*\s*\d+\:\d+\:\d+\s*$,)) {
      return (($1 == 0) && ($2 == 0) && ($3 == 0)) ? undef : $3.".".$2.".".$1;
   }
   return $text;
}

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
            if ($ldap_search->done) {
               $poe_kernel->post($heap->{config}->{dstsession} || $session => $heap->{config}->{dstevent} || "done" => [$ldap_search->entries] => ($ldap_search->code ? ($ldap_search->error || "unknown") : undef));
               delete $heap->{ldap} ;
               $poe_kernel->delay("timeout" => undef);
            }
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

sub ReadConfig {
   my $configfile = shift;
   my $keys = shift || [];
   my $actions = shift || {};
   my $config = {};
   Log("ToolsLib: ReadConfigAndInit: Beginning to read config", $DEBUG);
   open (CONFIG, "<".$configfile) || die("Can't open config file ".$configfile.":".$!);
   while (<CONFIG>) {
      chomp;
      s/\#.*$//g;
      if (/^\s*(\S+)\s+([^\n\r]*)/) {
         Log("ToolsLib: ReadConfigAndInit: FOUND KEY:".$1.":".$2.":", $DEBUG);
         my $key = lc($1);
         my $value = $2;
         if ($keys && (!grep { my $a = $_; ($key =~ m,^$a$,i) } map { my $a = $_; $a =~ s,\*,\.\*,g; $a } (@{$keys}, 'logdst', 'loglevel'))) {
            Log("ToolsLib: ReadConfigAndInit: Unknown global key ".$key." in config.", $WARNING);
         }
         $config->{$key} = $value;
         foreach my $curaction (keys %$actions) {
            if (lc($key) eq lc($curaction)) {
               $actions->{$curaction}(\$value);
               next;
            }
         }
         if (lc($key) eq "logdst") {
            $logdst = 0;
            $logdst = $logdst | $LOG_STDOUT if ($value =~ /stdout/i);
            $logdst = $logdst | $LOG_STDERR if ($value =~ /stderr/i);
            $logdst = $logdst | $LOG_SYSLOG if ($value =~ /syslog/i);
         } elsif (lc($key) eq "loglevel") {
            if      ($value =~ /ERROR/i  ) {
               $loglevel = $ERROR;
            } elsif ($value =~ /WARNING/i) {
               $loglevel = $WARNING;
            } elsif ($value =~ /INFO/i   ) {
               $loglevel = $INFO;
            } elsif ($value =~ /DEBUG/i  ) {
               $loglevel = $DEBUG;
            }
         }
      }
   }
   close(CONFIG);
   return $config;
}

sub hidebegin {
   my $someid = shift;
   my $lable = shift;
   my $showit = shift;

   return '<a href="#" onClick="if (document.getElementById('.chr(39).
          $someid.chr(39).').style.display=='.chr(39).'none'.chr(39).')'.
          '{document.getElementById('.chr(39).$someid.chr(39).').style.display='.chr(39).'block'.chr(39)."} ".
          'else '.
          '{document.getElementById('.chr(39).$someid.chr(39).').style.display='.chr(39).'none'.chr(39).'}; '.
          'return false">'.$lable.'</a>'.
          '<div><span id="'.$someid.'" style="display: '.($showit? 'block' : 'none').';">';
}

sub getURL {
   my $curSession = shift || Log("getURL1", $ERROR);
   my $params = shift || undef;
   my $context = shift;
   Log("getURL2", $ERROR) if shift;
   return "/ajax?nocache=".rand(999999999999)."&sessionid=".
      $curSession->{sessionid}.
      # FIXME:XXX:TODO: Hier wird direkt auf context zugegriffen... das is schlecht!
      (($curSession->{context}->{$context}->{id} && !(defined($params) && (ref($params) eq "HASH") && $params->{context})) ? "&context=".$curSession->{context}->{$context}->{id} : '').
      (defined($params) && (ref($params) eq "HASH") && (keys %$params) ?
         "&".join("&", map { $_."=".($params->{$_} || '') } keys %$params) : 
         '');
}

sub hideend {
   return "</span></div>\n";
}

sub htmlUnEscape {
   my $bad = shift || '';
   $bad =~ s,\&lt;,<,g;
   return $bad;
}

sub new_anon_scalar {
   my $temp;
   return \$temp;
}

sub ensureLength {
   my $text = shift;
   my $len = shift;
   my $char = shift;
   #print length($text).":".$len.":".($len - length($text))."\n";
   $text = "".($char x ($len - length($text))).$text if (length($text) < $len);
   return $text;
}

sub daemonize {
   chdir '/'                 or die "Can't chdir to /: $!";
   open(PIDFILE,">".$PIDFILE)or die "Can't open pidfile ".$PIDFILE;
   defined(my $pid = fork)   or die "Can't fork: $!";
   if ($pid) { Log("ToolsLib: Daemonize: Daemonizing ... PID is ".$pid, $INFO); print PIDFILE $pid."\n"; }
   close(PIDFILE);
   open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
   open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
   exit if $pid;
   $SIG{__DIE__} = sub {
      unlink($PIDFILE);
      confess;
   };
   setsid()                  or die "Can't start a new session: $!";
   open STDERR, '>&STDOUT'   or die "Can't dup stdout: $!";
}

sub time2human {
   my @time = gmtime(shift);
   return $time[3].".".($time[4]+1).".".($time[5]+1900); # ." ".$time[2].":".$time[1].":".$time[0];
   
}

sub time2sql {
   my @time = gmtime(shift);
   return ($time[5]+1900)."-".($time[4]+1)."-".$time[3]." ".$time[2].":".$time[1].":".$time[0];
}

sub secsToHours {
   return (int(shift() / 36) / 100);
}

sub hoursToHourMinute {
   my $hour = shift;
   unless (defined($hour)) {
      Log('BAD: $hour is undefined', $ERROR);
      return "0:00";
   }
   $hour =~ s/\,/\./gi;
   unless ($hour =~ /^(\-)?[\d\.]*$/) {
      Log("Time '".$hour."' not a number!", $WARNING);
      return "0:00";
   }
   my $minus = $1;
   my $minute = abs(($hour - int($hour)) * 60);
	$minute = sprintf ("%.0f", $minute);
   $hour = abs(int($hour));
   return ($minus ? "-" : "").$hour.":".($minute ? ((length($minute) == 1) ? "0" : '').$minute : '00');
}

sub mergeColumnInfos {
   my $DB = shift;
   my $column = shift;
   
   my $tmphash = {};
   unless ($column->{type} && (ref($DB->{types}) eq "HASH") &&
           (ref($DB->{types}->{$column->{type}}) eq "HASH")) {
      Log("There is no such type :".(exists($column->{type}) ? $column->{type} : '').": for :".(exists($column->{label}) ? $column->{label} : '').": available in DB Definition!", $ERROR);
      return undef;
   }
   foreach (keys(%{$DB->{types}->{$column->{type}}})) {
      $tmphash->{$_} = $DB->{types}->{$column->{type}}->{$_};
   }
   if (exists($DB->{type}) && $DB->{type} && exists($DB->{types}->{$column->{type}}->{$DB->{type}})) {
      foreach (keys(%{$DB->{types}->{$column->{type}}->{$DB->{type}}})) {
         $tmphash->{$_} = $DB->{types}->{$column->{type}}->{$DB->{type}}->{$_};
      }
   }
   foreach (keys(%{$column})) {
      $tmphash->{$_} = $column->{$_};
   }
   return $tmphash;
}

sub hashKeysRightOrder {
   my $hash = shift;
   my $dborder = shift;
   return sort { return 1 unless (my $tmpa = (($dborder && $hash->{$a}->{dborder}) ? $hash->{$a}->{dborder} : $hash->{$a}->{order}));
   return -1 unless (my $tmpb = ($dborder && $hash->{$b}->{dborder}) ? $hash->{$b}->{dborder} : $hash->{$b}->{order});
   return ($tmpa <=> $tmpb)} keys %$hash;
}

sub getAffectedColumns {
   my $DB = shift;
   my $tabledef = shift;
   my $onlyShowInSelect = shift || 0;
   my $all = shift || 0;
   my $selectQuestion = shift;
   my $getVirtuals = shift;

   unless (defined($tabledef) && (ref($tabledef) eq "HASH")) {
      Log("ToolsLib: getAffectedColumns: Unknown tabledef :".$tabledef.":!!!", $ERROR);
      return [];
   }
   my @tmp;
   foreach my $column (hashKeysRightOrder($tabledef)) {
      my $columndef = mergeColumnInfos($DB, $tabledef->{$column});
      #my $columndef = $tabledef->{$column};
         #print "COL:".$column.":".$columndef->{label}.":\n"; 
      next if $columndef->{secret};
      next unless ($getVirtuals || $columndef->{dbtype});
      next if ($onlyShowInSelect && (!$columndef->{showInSelect}));
      next unless ((!$columndef->{hidden}) || $all || ($selectQuestion && $columndef->{selectAlsoIfHidden}));
      push(@tmp, $column); 
   }
   return [@tmp];
}


# Cloned lediglich auf erstem Level - Das reicht fuer
# das was ich hier brauche.
sub simplehashclone {
   my $hash = shift;
   my $result = {};
   foreach my $key (keys %$hash) {
      $result->{$key} = $hash->{$key};
   }
   return $result;
}

sub arraycompare {
   my $arry1 = shift;
   my $arry2 = shift;
   grep { return 0 unless defined($arry2->[$_]) } @$arry1;
   return 1;
}

sub hashcompare {
   my $hash1 = shift;
   my $hash2 = shift;
   my $onlykeys = shift || 0;
   my $onlythiskeys = shift || undef;
   foreach (keys %$hash1) {
      unless (($onlythiskeys && (!exists($onlythiskeys->{$_}))) || (defined($hash2->{$_}) && ($onlykeys || ($hash1->{$_} eq $hash2->{$_})))) {
         #print "HASHCOMPARE:Hash1->".$_."=".$hash1->{$_}.":Hash2->".$_."->".$hash2->{$_}.":\n";
    return 0;
      }
   }
   foreach (keys %$hash2) {
      unless (($onlythiskeys && (!exists($onlythiskeys->{$_}))) || (defined($hash1->{$_}) && ($onlykeys || ($hash1->{$_} eq $hash2->{$_})))) {
         #print "HASHCOMPARE:Hash2->".$_."=".$hash2->{$_}.":Hash1->".$_."->".$hash1->{$_}.":\n";
         return 0;
      }
   }
   return 1;
}

sub padNumber {
   my $number = shift;
   my $dstlen = shift;
   my $diff = $dstlen-length($number);
   for (my $i = 0; $i < $diff; $i++) {
      $number = "0".$number;
   }
   return $number;
}

sub Log {
   my $msg = shift;
   my $severity = shift || $ERROR;
   my ($seconds, $microseconds) = gettimeofday;
   my @curtime = localtime($seconds);
   my $line = join(".", map { padNumber($_, 2) } ( $curtime[3], $curtime[4]+1, $curtime[5]+1900 ))." ".join(":", map { padNumber($_, 2) } ( reverse @curtime[0..2] ) ).".".$microseconds.": ".$msg;
   if ($severity >= $loglevel) {
      my $level = undef;
      if      ($severity == $ERROR  ) {
         $level = LOG_ERR;
         $line = "###  ERROR: ".$line;
      } elsif ($severity == $WARNING) {
         $level = LOG_WARNING;
         $line = "## WARNING: ".$line;
      } elsif ($severity == $INFO   ) {
         $level = LOG_INFO;
         $line = "#     INFO: ".$line;
      } elsif ($severity == $DEBUG  ) {
         $level = LOG_DEBUG;
         $line = ".    DEBUG: ".$line;
      } else {
         $line = "   UNKNOWN: ".$line;
      }
      # Standardmaessig nach STDOUT.
      syswrite(STDOUT, $line."\n") if ((!defined($logdst)) || ($logdst & $LOG_STDOUT));
      syswrite(STDERR, $line."\n") if  ($logdst && ($logdst & $LOG_STDERR));
      syslog($level, $line) if ($logdst && ($logdst & $LOG_SYSLOG));
   }
   if ($severity >= $ERROR) {
      if ($loglevel <= $DEBUG) {
         confess();
      } else {
         cluck();
      }
   }
}

sub MakeTime {
   $_ = shift;
   @_ = gmtime($_);
   return ($_[5]+1900)."-".($_[4]+1)."-".($_[3])." ".($_[2]).":".$_[1].":".$_[0];
}

sub getIncludedTables {
   my $DB = shift;
   my $table = shift;
   my $onlyOrColumns = shift || 0;
   my $includeTable = shift || '';
   my $tmp = "_".$UNIQIDCOLUMNNAME;
   my $tmpr = {};
   foreach (@{getAffectedColumns($DB, $DB->{tables}->{$table}->{columns}, 0, 0, undef, $onlyOrColumns)}) {
      if (($_ =~ /^(.*)$tmp$/) && (defined($DB->{tables}->{$1}))) {
         foreach (@{getAffectedColumns($DB, $DB->{tables}->{$1}->{columns}, 0, 1, undef, $onlyOrColumns)}) {
            push(@{$tmpr->{$1}}, $_) if (($DB->{tables}->{$1}->{columns}->{$_}->{orsearch}) || (!$onlyOrColumns));
         }
      } else {
         push(@{$tmpr->{$table}}, $_) if (($DB->{tables}->{$table}->{columns}->{$_}->{orsearch}) || (!$onlyOrColumns));
      }
   }
   grep {
      $includeTable = $_;
      foreach (@{getAffectedColumns($DB, $DB->{tables}->{$includeTable}->{columns}, 0, 1, undef, $onlyOrColumns)}) {
         push(@{$tmpr->{$includeTable}}, $_) if (($DB->{tables}->{$includeTable}->{columns}->{$_}->{orsearch}) || (!$onlyOrColumns));
      }
   } grep { exists($DB->{tables}->{$_}) } @$includeTable if (ref($includeTable) eq "ARRAY");
   return $tmpr;
}

sub makeInfoLine {
   my $config = shift;
   my $SID = shift;
   my $pre = shift;
   my $hash = shift;
   my $tmp = [];
   foreach my $key (keys %$hash) {
      $config->{TelnetServer}->send($SID, $pre.":".$key.":".$hash->{$key}.":\n") if (($hash->{$key} ne "") && !(ref($hash->{$key})));
   }
}

################# TIMELINE

my $debug = 0;

my $TIMELINE_SECONDS  = 6;
my $TIMELINE_MINUTE   = 5;
my $TIMELINE_QUARTER  = 4;
my $TIMELINE_HOUR     = 3;
my $TIMELINE_DAY      = 2;
#my $TIMELINE_TWOWEEKS = 2;
my $TIMELINE_MONTH    = 1;
my $TIMELINE_YEAR     = 0;

my $TIMELINE_DEF = [];                                           # Column to cut and # Column after to normalise
$TIMELINE_DEF->[$TIMELINE_SECONDS]  = [1,                                             5];
$TIMELINE_DEF->[$TIMELINE_MINUTE]   = [$TIMELINE_DEF->[$TIMELINE_SECONDS]->[0] * 60,  4];
$TIMELINE_DEF->[$TIMELINE_QUARTER]  = [$TIMELINE_DEF->[$TIMELINE_MINUTE]->[0]  * 15,  5, 15];
$TIMELINE_DEF->[$TIMELINE_HOUR]     = [$TIMELINE_DEF->[$TIMELINE_MINUTE]->[0]  * 60,  3];
$TIMELINE_DEF->[$TIMELINE_DAY]      = [$TIMELINE_DEF->[$TIMELINE_HOUR]->[0]    * 24,  2];
#$TIMELINE_DEF->[$TIMELINE_TWOWEEKS] = [$TIMELINE_DEF->[$TIMELINE_DAY]->[0]     * 14,  3, 15];
$TIMELINE_DEF->[$TIMELINE_MONTH]    = [$TIMELINE_DEF->[$TIMELINE_DAY]->[0]     * 27,  1];
$TIMELINE_DEF->[$TIMELINE_YEAR]     = [$TIMELINE_DEF->[$TIMELINE_DAY]->[0]     * 364, 0];

my $FOLLOWED = "***followed***";

sub getTimeLineHTML {
   my $oben = [];
   my $unten = [];
   my $lastday = '';
   my $start = shift;
   my $end = shift;
   my $timelinedata = shift || [[]];
   my $untenTrenner = shift || ''; # '|';
   my $stdcolor = shift || '#EEEEEE';
   my $heigh = shift || 5;
   # Gesamtlaenge der Timeline in Pixel
   my $width = shift || 900;
   my $lineheight = $untenTrenner ? 1 : $heigh;
   my $zeitraum = $end - $start;
   my $return = '';

   # Wie breit soll eine Zelle sein? Damit wird die Auflösung der Timeline festgelegt!
   my $widthCell = 2; # Pixel

   # Wieviele Pixel braucht das Datum auf jedem Browser mindestens?
   my $widthText = 60; # Pixel

   # Wieviele Pixel braucht die Uhrzeit auf jedem Browser mindestens?
   my $widthTimeText = 30; # Pixel

   my $cells = int($width/$widthCell);
   my $timeCellSize = ($zeitraum / $cells);

   my $i = 0;
   foreach my $timedef (@$TIMELINE_DEF) {
   print "TIMEDEF:".$timedef.":\n" if $debug;
   my $curtime = $start;
   unless ($timedef->[0]) {
      print "Dateobj has no timejump!\n";
      $debug ? die : return "ERROR";
   }
   last if ($zeitraum / $timedef->[0]) > ($cells * 3);
   while ($curtime < $end) {
      my $niceTimePoint = cutDateInfos(toDateObj($curtime), $timedef);
      my $epochNiceTimePoint = $niceTimePoint->epoch();
      last unless ($epochNiceTimePoint < $end);
      print "RUN WITH ".$epochNiceTimePoint.":\n" if $debug;
      if ($epochNiceTimePoint > $start) {
         my $dstCell = int(($epochNiceTimePoint - $start) / $timeCellSize);
         my $inCell = '|';
         my $curTextSize = $widthText;
         my @beschr = @{beschriftung($niceTimePoint, 0)};
         my $prelastday = $beschr[scalar(@beschr)-1];
         if (($lastday eq $beschr[scalar(@beschr)-1])) {
            $beschr[scalar(@beschr)-1] = '';
            $curTextSize = $widthTimeText;
         } else {
            $beschr[scalar(@beschr)-1] = "<strong>".$beschr[scalar(@beschr)-1]."</strong>";
         }
         last if (($dstCell+($curTextSize/$widthCell)) > $cells);
         my $text = $inCell.join("<br>".$inCell."", @beschr);
         print "Want to write ".$text." to cell ".$dstCell."\n" if $debug;
         my @oben = @$oben;
         if (my @a = grep { defined($_) && $_ } (@oben[$dstCell..($dstCell+($curTextSize/$widthCell)+1)])) {
            print "There are already ".scalar(@a)." used to satify ".$text."\n" if $debug;
         } else {
            $lastday = $prelastday;
            my $j = 0;
            for ($j = 0; $j <= ($curTextSize/$widthCell); $j++) {
               $oben->[$dstCell+$j] = $unten->[$dstCell+$j] = $FOLLOWED;
            }
            $oben->[$dstCell+$j] = $text;
            $unten->[$dstCell] = $untenTrenner;
         }
      }
         $curtime += $timedef->[0];
      }
      $i++;
   }
   $return .= '<table border=0 cellpadding="0" cellspacing="0">'."\n";
   $return .= "  <tr style='padding-top:0px;padding-bottom:0px;margin-top:0px;margin-bottom:0px;'>\n";
   my $span = 0;
   my $spanline = 0;
   $return .= printLine($oben, $widthCell);
   foreach my $highlights (@$timelinedata) {
      $return .= "  <tr style='padding-top:0px;padding-bottom:0px;margin-top:0px;margin-bottom:0px;'>\n";
      $return .= '  <tr>'."\n";
      $return .= printLineNospan($unten, $highlights, $start, $timeCellSize, $widthCell, $stdcolor, $lineheight);
   }
   $return .= '  </tr>'."\n";
   $return .= '</table>'."\n";
}

sub printLine {
   my $obj = shift;
   my $widthCell = shift;
   my $span = 0;
   my $spanline = 0;
   my $return = '';
   foreach my $line (@$obj) {
      if ($line eq $FOLLOWED) {
         $return .= "    <td".($spanline > 1 ? " colspan=".($spanline) : "")." valign=top style='padding-top:0px;     padding-bottom:0px;padding-left:0px;padding-right:0px;'></td>\n" if ($spanline);
         $spanline = 0;
         $span++;
      } elsif ($line) {
         $return .= "    <td".($spanline > 1 ? " colspan=".($spanline) : "")." valign=top style='padding-top:0px;     padding-bottom:0px;padding-left:0px;padding-right:0px;'></td>\n" if ($spanline);
         $spanline = 0;
         $span++;
         $return .= "    <td".($span > 1 ? " colspan=".($span) : "")." valign=bottom style='padding-top:0px;     padding-bottom:0px;padding-left:0px;padding-right:0px;'><font face='Arial, Helvetica, sans-serif' size=1>".$line."</font></td>\n";
         $span = 0;
      } else {
         $spanline++;
      }
   }
   $return .= "    <td colspan=".($spanline)." style='padding-top:0px;     padding-bottom:0px;padding-left:0px;padding-right:0px;'><img src='/bilder/spacer.gif' height=1 width='".($spanline*$widthCell)."'></td>\n" if ($spanline);
   return $return;
}

sub printLineNospan {
   my $obj = shift;
   my $startend = shift;
   my $start = shift;
   my $timeCellSize = shift;
   my $widthCell = shift;
   my $stdcolor = shift;
   my $lineheight = shift || 1;
   my $span = 0;
   my $spanline = 0;
   my $colors = [];
   my $return = '';
   foreach my $startstoptime (@$startend) {
      my $i = 0;
      foreach my $line (@$obj) {
         if (($startstoptime->[0] >= ((($i*$timeCellSize)+$start))) &&
             ($startstoptime->[0] < ((($i+1)*$timeCellSize)+$start))) {
               $colors->[$i] = $startstoptime->[2];
         } elsif (($startstoptime->[0] < (($i*$timeCellSize)+$start)) &&
                  ($startstoptime->[1] > (($i*$timeCellSize)+$start))) {
             $colors->[$i] = $startstoptime->[2];
             #print "-------------------\n".(($i*$timeCellSize)+$start)."\n".$startstoptime->[0]."\n".$startstoptime->[1]."<br>\n";
         }
         $i++;
      }
   }
   my $i = 0;
   foreach my $line (@$obj) {
      $return .=  "    <td valign=top bgcolor='".($colors->[$i] || $stdcolor)."' style='padding-top:0px;     padding-bottom:0px;padding-left:0px;padding-right:0px;'>";
      $return .=  "<font face='Arial, Helvetica, sans-serif' size=1>".$line."</font><br>" if ($line && ($line ne $FOLLOWED));
      $return .=  "<img src='/bilder/spacer.gif' height='".$lineheight."' width='".($widthCell)."'>";
      $return .=  "</td>\n";
      $i++;
   }
   return $return;
}

sub beschriftung {
   my $dateobj = shift;
   my $seconds = shift || 0;
   my $tmp = $dateobj->day() eq "1" ? '' : preZero($dateobj->day()).".";
   $tmp .= $dateobj->month() eq "1" ? '' : preZero($dateobj->month()).".";
   $tmp .= $dateobj->year();
   return [$tmp] if (
              ($dateobj->hour()   eq "0") &&
              ($dateobj->minute() eq "0"));
   my $tmp2 = preZero($dateobj->hour()).":";
   $tmp2 .= preZero($dateobj->minute());
   $tmp2 .= ($seconds ? ":".preZero($dateobj->second()) : '');
   return [$tmp2, $tmp];
}

sub cutDateInfos {
   my $dateobj = shift;
   my $intervaldef = shift;
   my $newvalues = [$dateobj->year(),
                    $dateobj->month(),
                    $dateobj->day(),
                    $dateobj->hour(),
                    $dateobj->minute(),
                    $dateobj->second()];
   if ($intervaldef->[2]) {
      my $tmp = (int($newvalues->[$intervaldef->[1]-1] / $intervaldef->[2]) * $intervaldef->[2]);
      $newvalues->[$intervaldef->[1]-1] = ($intervaldef->[1]-1 > 2 && $tmp) ? $tmp : 1 ;
   }
   my $tmp = DateTime->new( year   => $newvalues->[0],
                            month  => $intervaldef->[1] ? $newvalues->[1] : 1,
                            day    => ($intervaldef->[1] > 1) ? $newvalues->[2] : 1,
                            hour   => ($intervaldef->[1] > 2) ? $newvalues->[3] : 0,
                            minute => ($intervaldef->[1] > 3) ? $newvalues->[4] : 0,
                            second => ($intervaldef->[1] > 4) ? $newvalues->[5] : 0,
                            time_zone => "Europe/Berlin"
                       );
   return $tmp;
}

sub preZero {
   my $val = shift;
   $val = "0".$val if (length($val) < 2);
   return $val;
}

sub toDateObj { return DateTime->from_epoch( epoch => shift, time_zone => "Europe/Berlin" ); }

my @itoa64 = split(//,
   "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
sub _xdump ($) { print unpack("H*", shift) . "\n"; }
sub _to64($$) {
   my ($v, $n) = @_;
   my $s;
        while (--$n >= 0) {
                $s .= $itoa64[$v&0x3f];
                $v >>= 6;
        }
   return $s;
}

sub _base64 ($) {
   my ($data) = @_;
   my @a = unpack("C*", $data);
   my ($s, $l);
   $l = ($a[ 0]<<16)|($a[ 6]<<8)|$a[12]; $s .= _to64($l,4);
   $l = ($a[ 1]<<16)|($a[ 7]<<8)|$a[13]; $s .= _to64($l,4);
   $l = ($a[ 2]<<16)|($a[ 8]<<8)|$a[14]; $s .= _to64($l,4);
   $l = ($a[ 3]<<16)|($a[ 9]<<8)|$a[15]; $s .= _to64($l,4);
   $l = ($a[ 4]<<16)|($a[10]<<8)|$a[ 5]; $s .= _to64($l,4);
   $l =              $a[11]       ; $s .= _to64($l,2);
   return $s;
}

sub md5crypt($$) {
   my ($pw, $salt) = @_;
   my $magic = '$1$';

   $salt =~ s/^\$1\$//;
   $salt =~ s/\$.*$//;

   my $ctx = Digest::MD5->new;
   $ctx->add($pw);
   $ctx->add($magic);
   $ctx->add($salt);

   my $ctx1 = Digest::MD5->new;
   $ctx1->add($pw);
   $ctx1->add($salt);
   $ctx1->add($pw);

   my $final = $ctx1->digest;

   for (my $pl = length($pw); $pl > 0; $pl -= 16) {
      $ctx->add(substr($final, 0, $pl > 16 ? 16 : $pl));
   }

   my $zero = pack("C", 0x00);
   for (my $pl = length($pw); $pl ; $pl >>= 1) {
      if ($pl & 1) {
         $ctx->add(substr($zero, 0, 1));
      } else {
         $ctx->add(substr($pw, 0, 1));
      }
   }
   $final = $ctx->digest;

   for (my $i=0; $i<1000; $i++) {
      $ctx1->reset;
      if ($i & 1) {
         $ctx1->add($pw);
      } else {
         $ctx1->add($final);
      }
      if ($i % 3) {
         $ctx1->add($salt);
      }
      if ($i % 7) {
         $ctx1->add($pw);
      }
      if ($i & 1) {
         $ctx1->add($final);
      } else {
         $ctx1->add($pw);
      }
      $final = $ctx1->digest;
   }
   return $magic . $salt . '$' . _base64($final);
}

sub _salt () {
   my $magic = '$1$';
   my $salt = '';
   my $l = scalar @itoa64;
   for(my $i = 0; $i<8; $i++) {
      $salt .= $itoa64[int(rand($l))];
   }
   return $magic . $salt;
}

sub md5pw ($) {
   my $pw = shift;
   return md5crypt($pw, _salt());
}

sub normaliseLine {
   my $line = shift || '';
   my $quote = shift || 0;

   $line =~ s,\\,\\\\,g;
   $line =~ s,",\\",g;
   $line =~ s,',\\',g;
   $line =~ s,<,\&lt;,g;
   if ($quote) {
      $line = "'".$line."'";
   } else {
      $line =~ s,;,,g;
   }
   return $line;
}

sub getFileUploadJavascriptForIDs {
   my $url = shift;
   my $ids = shift;
   my $ret = '';
   $ret .= "<script>\n";
   $ret .= "   function Init () {\n";
   foreach my $id (@$ids) {
      $ret .= '      var el = document.getElementById("preview_'.$id.'");'."\n";
      $ret .= '      el.addEventListener("dragenter", function(event){event.stopPropagation();event.preventDefault();}, false);'."\n";
      $ret .= '      el.addEventListener("dragover", function(event){event.stopPropagation();event.preventDefault();}, false);'."\n";
      $ret .= '      el.addEventListener("drop", onDropImg'.$id.', false);'."\n";
   }
   $ret .= "   }\n";
   foreach my $id (@$ids) {
      $ret .= "   function onDropImg".$id."(event) {\n";
      $ret .= "     event.stopPropagation();\n";
      $ret .= "     event.preventDefault();\n";
      #	$ret .= "     alert('You just dropped ' + event.dataTransfer.files.length + ' file(s).');\n";
      $ret .= "     for(var i = 0 ; i < event.dataTransfer.files.length ; i++) {\n";
      $ret .= "        var file = event.dataTransfer.files.item(i);\n";
      $ret .= "        uploadUsingPOST(file, ".$id.", 'setimg');\n";
      $ret .= "     }\n";
      $ret .= "   }\n";
   }
   $ret .= "   function uploadUsingPOST(file, id, action) {\n";
   $ret .= "      var reader = new FileReader();\n";
   $ret .= "      reader.onloadend = (function(file, id, action) { return function(e) { new FileUpload(file, e.target.result, id, action); }; })(file, id, action);\n";
   $ret .= "      reader.readAsBinaryString(file);\n";
   $ret .= "   }\n";
   $ret .= "   function updateProgress(percentage, action, id, filename) {\n";
   $ret .= "      var replaceid = 'blah';\n";
   $ret .= "      if (action == 'setdoc') {\n";
   $ret .= "         replaceid = 'doc_' + id;\n";
   $ret .= "      } else if(action == 'setimg') {\n";
   $ret .= "         replaceid = 'preview_' + id;\n";
   $ret .= "      }\n";
   $ret .= "      document.getElementById(replaceid).innerHTML = 'Uploading ' + filename + ': ' + percentage.toString() + ' %';\n";
   $ret .= "   }\n";
   $ret .= "   function FileUpload(img, bin, id, action) {\n";
   $ret .= "      var xhr = new XMLHttpRequest();\n";
   $ret .= "      var self = this;\n";
   $ret .= "      if (typeof(img.fileName) != 'undefined') {\n";
   $ret .= "         xhr.upload.filename = img.fileName;\n";
   $ret .= "      } else if (typeof(img.name) != 'undefined') {\n";
   $ret .= "         xhr.upload.filename = img.name;\n";
   $ret .= "      } else {\n";
   $ret .= "         alert('Konnte Dateinamen nicht erkennen. Vorgang abgebrochen.');\n";
   $ret .= "         return;\n";
   $ret .= "      }\n";
   $ret .= "      xhr.upload.myid = id;\n";
   $ret .= "      xhr.upload.myaction = action;\n";
   $ret .= "      updateProgress(0, action, id, xhr.upload.filename);\n";
   $ret .= "      xhr.upload.addEventListener('progress', function(event) {\n";
   $ret .= "         if (event.lengthComputable) {\n";
   $ret .= "            var percentage = Math.round((event.loaded * 100) / event.total);\n";
   $ret .= "            updateProgress(percentage.toString(), event.target.myaction, event.target.myid, event.target.filename);\n";
   $ret .= "         }\n";
   $ret .= "      }, false);\n";
   $ret .= "      xhr.upload.addEventListener('load', function(event){\n";
   $ret .= "         updateProgress(100, event.target.myaction, event.target.myid, event.target.filename);\n";
   $ret .= "         document.location.href = '".$url."&status=done&name=' + event.target.filename;\n";
   $ret .= "      }, false);\n";
   $ret .= "      xhr.open('POST', '".$url."&status=upload&name=' + xhr.upload.filename);\n";
   $ret .= "      xhr.overrideMimeType('text/plain; charset=x-user-defined-binary');\n";
   $ret .= "      if(!XMLHttpRequest.prototype.sendAsBinary){\n";
   $ret .= "        XMLHttpRequest.prototype.sendAsBinary = function(datastr) {\n";
   $ret .= "          function byteValue(x) {\n";
   $ret .= '            return x.charCodeAt(0) & 0xff;'."\n";
   $ret .= "          }\n";
   $ret .= "          var ords = Array.prototype.map.call(datastr, byteValue);\n";
   $ret .= "          var ui8a = new Uint8Array(ords);\n";
   $ret .= "          this.send(ui8a.buffer);\n";
   $ret .= "        }\n";
   $ret .= "      }\n";
   $ret .= "      xhr.sendAsBinary(bin);\n";
   $ret .= "   }\n";
   return $ret;
}

package ADBGUI::htmlTable;
use strict;
use warnings;
use Encode;

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $params = shift;
   my $self = {
      table => {},
      notabletag => $params->{notabletag} ? 1 : 0
   };
   bless ($self, $class);
}

sub getHTML {
   my $self = shift;
   my $return = '';
   $return .= "<table".($self->{table}->{attr} ? " ".
      join(" ",
      map { $_."='".$self->{table}->{attr}->{$_}."'" } 
      grep { (($_ ne "maxrow") && ($_ ne "maxcol")) ? 1 : 0 }
      keys %{$self->{table}->{attr}}) : ''
   ).">\n" unless $self->{notabletag};
   for(my $rowid = 0; $rowid < $self->getTableAttr("maxrow"); $rowid++) {
      my $row = $self->{table}->{rows}->[$rowid];
      $return .= "  <tr>\n";
      for(my $columnid = 0; $columnid < $self->getTableAttr("maxcol"); $columnid++) {
         my $column = $row->{column}->[$columnid];
         next if ($column->{attr} && $column->{attr}->{skip});
         $return .= "    <td".($column->{attr} ? " ".
            join(" ", map { $_."='".$column->{attr}->{$_}."'" }
            keys %{$column->{attr}}) : '').">".
            ((!$column->{value} || ($column->{value} eq "")) ? "&nbsp;" : $column->{value})."</td>\n";
      }
      $return .= "  </tr>\n";
   }
   $return .= "</table>\n" unless $self->{notabletag};
   #$return =~ s,\<,&lt;,gi;
   return #"<pre>".
      encode("utf8", $return);
}

sub setTableAttr {
   my $self = shift;
   my $key = shift;
   my $value = shift;
   $self->{table}->{attr}->{$key} = $value;
}

sub getTableAttr {
   my $self = shift;
   my $key = shift;
   return $self->{table}->{attr}->{$key} ||= 0;
}

sub setCellValue {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   my $value = shift;
   $self->setTableAttr("maxrow", $rowid+1) if ($rowid >= $self->getTableAttr("maxrow"));
   $self->setTableAttr("maxcol", $columnid+1) if ($columnid >= $self->getTableAttr("maxcol"));
   $self->getCell($rowid, $columnid)->{value} .= $value;
}

sub overwriteCellValue {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   my $value = shift;
   $self->getCell($rowid, $columnid)->{value} = $value;
}

sub setCellAttr {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   my $key = shift;
   my $value = shift;
   $self->setTableAttr("maxrow", $rowid+1) if ($rowid >= $self->getTableAttr("maxrow"));
   $self->setTableAttr("maxcol", $columnid+1) if ($columnid >= $self->getTableAttr("maxcol"));
   $self->getCell($rowid, $columnid)->{attr}->{$key} = $value;
}

sub setAllCellAttrs {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   my $value = shift;
   $self->setTableAttr("maxrow", $rowid+1) if ($rowid >= $self->getTableAttr("maxrow"));
   $self->setTableAttr("maxcol", $columnid+1) if ($columnid >= $self->getTableAttr("maxcol"));
   $self->getCell($rowid, $columnid)->{attr} = $value;
}

sub getCell {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   return ($self->{table}->{rows}->[$rowid]->{column}->[$columnid] ||= {});
}

sub getCellAttr {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   return ($self->getCell($rowid, $columnid)->{attr} ||= {});
}

sub getAllCellAttrs {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   return ($self->getCell($rowid, $columnid)->{attr});
}

sub getCellValue {
   my $self = shift;
   my $rowid = shift;
   my $columnid = shift;
   return $self->getCell($rowid, $columnid)->{value};
}

sub setRowAttr {
   my $self = shift;
   my $rowid = shift;
   my $key = shift;
   my $value = shift;
   $self->setTableAttr("maxrow", $rowid+1) if ($rowid >= $self->getTableAttr("maxrow"));
   for(my $columnid = 0; $columnid < $self->getTableAttr("maxcol"); $columnid++) {
      $self->getCell($rowid, $columnid)->{attr}->{$key} = $value;
   }
}

sub setRowValue {
   my $self = shift;
   my $rowid = shift;
   my $value = shift;
   $self->setTableAttr("maxrow", $rowid+1) if ($rowid >= $self->getTableAttr("maxrow"));
   for(my $columnid = 0; $columnid < $self->getTableAttr("maxcol"); $columnid++) {
      $self->getCell($rowid, $columnid)->{value} .= $value;
   }
}

sub setColumnAttr {
   my $self = shift;
   my $columnid = shift;
   my $key = shift;
   my $value = shift;
   $self->setTableAttr("maxcol", $columnid+1) if ($columnid >= $self->getTableAttr("maxcol"));
   for(my $rowid = 0; $rowid < $self->getTableAttr("maxrow"); $rowid++) {
      $self->getCell($rowid, $columnid)->{attr}->{$key} = $value;
   }
}

sub setAllAttr {
   my $self = shift;
   my $key = shift;
   my $value = shift;
   for(my $rowid = 0; $rowid < $self->getTableAttr("maxrow"); $rowid++) {
      for(my $columnid = 0; $columnid < $self->getTableAttr("maxcol"); $columnid++) {
         $self->getCell($rowid, $columnid)->{attr}->{$key} = $value;
      }
   }
}

1;

