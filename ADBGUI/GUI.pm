package ADBGUI::GUI;

use strict;
use warnings;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw/$RUNNING $OK $TIMEOUT $PROTOKOLLERROR $PERMISSIONDENIED $RERROR $DONE
                    $ACTIONOK $NOSTATE $STARTUP $CONNECTED $GETDATA $SHOWTABLE $INSERTDATA
                    $OPEN $DELENTRY $SETFILTER $GETFITLER $GETGROUPED $GETTABLEINFO $ACTIVATE
                    $ASSIGN $FILTERRESET $DELENTRY $GETASSIGNFILES $SETASSIGNFILES/;
}

use IO::Socket::INET;
use CGI;

$CGI::DISABLE_UPLOADS = 1;          # Disable uploads
$CGI::POST_MAX        = 512 * 1024; # limit posts to 512K max
use GD;
use GD::Graph::pie3d;
use GD::Graph::colour;
use ADBGUI::BasicVariables;
use ADBGUI::Text;
use ADBGUI::Tools qw(:DEFAULT simplehashclone mergeColumnInfos getAffectedColumns hashKeysRightOrder Log);

$SIG{'PIPE'} = 'IGNORE'; # Wir erkennen auch ohne SigPipe wenn eine Verbindung kaputt ist.

# ReadWhile States
our $RUNNING          = 0;
our $OK               = 1;
our $TIMEOUT          = 2;
our $PROTOKOLLERROR   = 3;
our $PERMISSIONDENIED = 4;
our $RERROR           = 5;
our $DONE             = 6;
our $ACTIONOK         = 7;

# Handler States
our $NOSTATE        = 0;
our $STARTUP        = 1;
our $CONNECTED      = 2;
our $GETDATA        = 3;
our $SHOWTABLE      = 4;
our $INSERTDATA     = 5;
our $OPEN           = 6;
our $DELENTRY       = 7;
our $UNDELENTRY     = 8;
our $SETFILTER      = 9;
our $GETFITLER      = 10;
our $GETGROUPED     = 11;
our $GETTABLEINFO   = 12;
our $ACTIVATE       = 13;
our $ASSIGN         = 14;
our $FILTERRESET    = 15;
our $GETASSIGNFILES = 16;
our $SETASSIGNFILES = 17;

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $self  = {};
   bless ($self, $class);
   my $DB = shift;
   $self->{DB} =  (ref($DB) eq "ARRAY") ? $DB : [$DB];
   $self->{text} = shift;
   my $configfile = shift;

   # Debugmeldungen und und keine Funktionsausblendungen?
   #$self->{config}->{debug} = 1;

   # Fragen wir nochmal nach, bevor wir was loeschen?
   $self->{config}->{askbeforedelete} = 1;
   $self->{config}->{dbmanagerip} = '127.0.0.1';
   $self->{config}->{dbmanagerport} = undef;
   $self->{config}->{timeout} = 300;
   $self->{config}->{DEFAULTTABLESKIP} = 0;
   $self->{config}->{DEFAULTTABLELINES} = 20;
   $self->{config}->{STATPATH} = undef; # URLFilter: "/var/www/localhost/offline";

   $self->{config}->{DEFAULTTABLE} = undef;
   $self->{config}->{COLUMNFILTER} = undef;

   $self->{"q"} = new CGI;
   $self->readConfig($configfile);

   $self->{header} = "<html>\n<head>".
      "<title>".($self->{text}->{MAIN_TITLE} || "notitle")."</title>\n".
      "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />\n".
      "<meta http-equiv=\"pragma\" content=\"no-cache\"/>\n".
      "<link rel=\"stylesheet\" type=\"text/css\" href=\"".($self->{"q"}->url(-relative=>1)||"")."?job=getcss\" />\n".
      "</head>\n<body>\n". 
      "<div id=\"all_container\">\n<div id=\"page_fullframe\">\n".
      "<div id=\"fullframe_title\">".
      "<center><h1>".($self->{text}->{MAIN_TITLE} || "notitle")."</h1></center></div>\n".
      "<div id=\"fullframe_content\">\n";

   $self->{datedef} = [
      ["day", ".", "1", "31", $self->{text}->{DAY}, " ", ((gmtime(time-86400))[3]) ],
      ["month", ".", "1", "12", "", "-", ((gmtime(time-86400))[4])+1],
      ["year", "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;", "2000", "2040", "", "-", ((gmtime(time-86400))[5])+1900],
      ["hour", ":", "0", "23", $self->{text}->{TIME}, ":"],
      ["minute", ":", "0", "59", "", ":"   ],
      ["second", " ", "0", "59", " ", ""   ]
   ];

   # Initialisierung
   $self->{tableskip}  = $self->{"q"}->param("tableskip")  || $self->{config}->{DEFAULTTABLESKIP};
   $self->{tablelines} = $self->{"q"}->param("tablelines") || $self->{config}->{DEFAULTTABLELINES};
   $self->{buf} = '';
   $self->{target} = {};
   $self->{job} = $self->{"q"}->param('job') || $self->{config}->{DEFAULTJOB} || "defaultjob";
   
   $self->InstallBaseHandler();
   
   return $self;
}

sub getDBBackend {
   my $self = shift;
   my $table = shift;
   foreach my $dbbackend (@{$self->{DB}}) {
      return $dbbackend
         if (exists($dbbackend->{tables}->{$table}));
   }
   return undef;
}

sub getTableDefiniton {
   my $self = shift;
   my $table = shift;
   my $db = $self->getDBBackend($table);
   return $db->{tables}->{$table}
      if (defined($db) && exists($db->{tables}->{$table}));
   return undef;
}

sub checkOverride {
   my $self = shift;
   my $base = shift;
   my $table = shift;
   my $column = shift;
   return 1
      if ($base->{all} ||
         ($table &&
          $column &&
          $base->{$table} &&
          $base->{$table}->{$column}));
   return 0;
}

sub getViewStatus {
   my $self = shift;
   my $options = shift;
   my $moreparams = [@_];
   unless ($options->{table} && $options->{column} && $options->{action} && $options->{targetself} && (!@$moreparams)) {
      Log("getViewStatus: Missing parameters: action=".$options->{action}." table:".$options->{table}.":column:".$options->{column}.":targetself:".$options->{targetself}.":morex:".scalar(@$moreparams).": !", $ERROR);
      return undef;
   }
   my $tabledef = $self->getTableDefiniton($options->{table});
   my $columndef = mergeColumnInfos($self->getDBBackend($options->{table}), $tabledef->{columns}->{$options->{column}});
   my $return = undef;
   if ((!$self->checkOverride($options->{nonewonly}, $options->{table}, $options->{column})) && ($self->checkOverride($options->{donewonly}, $options->{table}, $options->{column}) || $columndef->{newonly})) {
      if ($options->{action} == $NEWACTION) {
         $return = ($self->checkOverride($options->{dowriteonly}, $options->{table}, $options->{column}) || $columndef->{writeonly}) ? "writeonly" : "";
      } elsif($options->{action} == $UPDATEACTION) {
         $return = "readonly";
      } else {
         $return = ($self->checkOverride($options->{dowriteonly}, $options->{table}, $options->{column}) || $columndef->{writeonly}) ? "readonly" : "writeonly";
      }
   } elsif (($options->{action} == $LISTACTION) &&
        (($self->checkOverride($options->{dowriteonly}, $options->{table}, $options->{column}) || $columndef->{writeonly}) &&
        (($self->checkOverride($options->{doreadonly},  $options->{table}, $options->{column}) || $columndef->{readonly})))) {
      $return = "writeonly";
   } else {   
      $return = ((!$self->checkOverride($options->{nohidden},    $options->{table}, $options->{column})) && ($self->checkOverride($options->{dohidden},    $options->{table}, $options->{column}) || $columndef->{hidden}))    ? "hidden"    :
                ((!$self->checkOverride($options->{noreadonly},  $options->{table}, $options->{column})) && ($self->checkOverride($options->{doreadonly},  $options->{table}, $options->{column}) || $columndef->{readonly}))  ? "readonly"  :
                ((!$self->checkOverride($options->{nowriteonly}, $options->{table}, $options->{column})) && ($self->checkOverride($options->{dowriteonly}, $options->{table}, $options->{column}) || $columndef->{writeonly})) ? "writeonly" :
                "";
   }
   return $return;
}

sub InstallBaseHandler {
   my $self = shift;

   $self->AddHandler("getcss", sub {
      #my $self = shift;
      #my $targetself = shift;
      #my $line = shift;
      #my $stadium = shift || 0;
      #$_ = $line->{data};
      print "Content-Type: text/css\r\n\r\n";
      if (open(CSS, "<", "url.css")) {
	      print <CSS>;
      }
      close CSS;
      return $DONE;
   }, {noStyle => 1});

   $self->AddHandler($self->{config}->{DEFAULTJOB} || "defaultjob", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};

      my $autret;
      return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
   
      print "<br>";
      print "<center>".$self->{text}->{T_WELCOME};
      print "<br><br>";
      $self->printTableButtons($targetself, "show");
      print "<br>";
      print $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => 'changepasspre',
      }, 'Passwort &auml;ndern');
      print "<br>";
      print $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => "logout"
      }, $self->{text}->{B_LOGOUT});
   });

   $self->AddHandler("headlinegetstatimg", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      my $autret = undef;
      
      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         $self->sendLine("GETTABLEINFO ".$targetself->{table});
         $targetself->{state} = $GETTABLEINFO;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETTABLEINFO) {
         my $var = "curInfo";
         return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETTABLEINFO", $var)) != $ACTIONOK);
         $self->sendLine("GETFILTER ".$targetself->{table});
         $targetself->{state} = $GETFITLER;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETFITLER) {
         return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETFILTER", "curFilter")) != $ACTIONOK);
         my $tabledef = $self->getTableDefiniton($targetself->{table});
         my $filterinfo = scalar(keys(%{$targetself->{curFilter}})) ? " - ".join("<br> - ", map { ($tabledef->{columns}->{$_}->{label}||$_)."='".$targetself->{curFilter}->{$_}."'" } keys %{$targetself->{curFilter}}) : '';
         my $column = "timestamp";
         my $curcolumn = mergeColumnInfos($self->getDBBackend($targetself->{table}), $tabledef->{columns}->{$column});
         my @tmp = getInfoLineForColumn($targetself->{curInfo}, $curcolumn, $column);
         print "<img src='".$self->getGraphURL($targetself->{sessionid}, $targetself->{table}, $self->{"q"}->param("column"), $self->{"q"}->param("calwndown"), 0)."'><br><br>";
         print "<b>Filter:</b><br> ".$filterinfo."<br><br>" if $filterinfo;
         print "<b>Zeitraum:</b><br>\n".join(" - \n", map { ($_->{label}?$_->{label}.": ":'').$_->{value} } @tmp)."</span>" if scalar(@tmp);
         print "<br><br><form method='post'>\n";
         print "<input type='text' name='calwndown' value='".($self->{"q"}->param("calwndown")||'')."'>";
         print $self->HashButton({
            sessionid => $targetself->{sessionid},
            job => 'headlinegetstatimg',
            table => $targetself->{table},
            column => $self->{"q"}->param("column")
         }, "Anzahl der angezeigten Segmente &auml;ndern (min 3, max. 40)", { noform => 1 });
         print "</form>";
         return $DONE;
      }
   });

   $self->AddHandler("getstatimg", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{"data"};

      unless (open(A, "<ADBGUI/fehler.gif")) {
         print $self->{"q"}->header();
         print "ERROR READING ERROR IMAGE\n";
         exit(0);
      }
      my $buf = '';
      my $fehler = '';
      while(sysread(A, $buf, 512)) {
         $fehler .= $buf;
      }
      my $width = $self->{"q"}->param("width") || 220;
      my $height = $self->{"q"}->param("height") || 130;
      
      unless ($self->{"q"}->param("table") && $self->{"q"}->param("column")) {
         syswrite(STDOUT, "Fehler: Fehler3\nContent-Type: image/gif\n\n".$fehler);
         return $DONE;
      }
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{"config"}->{DEFAULTTABLE} unless exists($self->{"DB"}->{"tables"}->{$targetself->{"table"}});
         
      my $autret = undef;
      if ($targetself->{"state"} == $NOSTATE) {
         if (($autret = $self->authenticate($line, $targetself, $stadium, 1)) != $ACTIONOK) {
            #syswrite(STDOUT, "Fehler: Fehler1\nContent-Type: image/gif\n\n".$fehler) unless ($autret == $RUNNING);
            return $autret;
         }
         $self->sendLine("GETGROUPED ".$targetself->{table}." ".$self->{"q"}->param("column"));
         $targetself->{state} = $GETGROUPED;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETGROUPED) {
         if (($autret = $self->retrieveGrouped($line, $targetself, 1)) != $ACTIONOK) {
            syswrite(STDOUT, "Fehler: Fehler2\nContent-Type: image/gif\n\n".$fehler) unless ($autret == $RUNNING);
            return $autret;
         }
         my $ok = 0;
         foreach (values(%{$targetself->{curGrouped}})) {
            if ($_) {      
               $ok = 1;
               last;
            }
         }
         unless ($ok) {
            syswrite(STDOUT, "Fehler: Fehler4a\nContent-Type: image/gif\n\n".$fehler) unless ($autret == $RUNNING);
            return $DONE;
         }
         $ok = 0;
         foreach (keys(%{$targetself->{curGrouped}})) {
            if ($_) { 
               $ok = 1;
               last;
            }
         }
         unless ($ok) {
            syswrite(STDOUT, "Fehler: Fehler4b\nContent-Type: image/gif\n\n".$fehler) unless ($autret == $RUNNING);
            return $DONE;
         }

         #unless (keys(%{$targetself->{curGrouped}})) {
         #   syswrite(STDOUT, "Fehler: Fehler5\nContent-Type: image/gif\n\n".$fehler) unless ($autret == $RUNNING);
         #   return $DONE;
         #}
         my $tabledef = $self->getTableDefiniton($targetself->{table});

         my $columndef = mergeColumnInfos($self->getDBBackend($targetself->{table}), $tabledef->{columns}->{$self->{"q"}->param("column")});
         my $graph = new GD::Graph::pie3d( $width, $height );
         #my $filterinfo = scalar(keys(%{$targetself->{curFilter}})) ? " - ".join(",", map { ($tabledef->{columns}->{$_}->{label}||$_)."='".$targetself->{curFilter}->{$_}."'" } keys %{$targetself->{curFilter}}) : '';
         $graph->set(
            x_label           => 'X-Label',
            y_label           => 'Y-Label',
            title             => ($tabledef->{label} || $targetself->{table})." - ".($columndef->{label} || $self->{"q"}->param("column")) # .$filterinfo
         );
         my $graphdata = $targetself->{curGrouped};
         # TODO/FIXME/XXX: mapids sollte fuer den URLFilter auch in der ShowTables
         #                 massgeblich sein, und nicht da nochmal ein hardcoded
         #                 mapping.
         if (exists($columndef->{mapids}) && ref($columndef->{mapids}) eq "HASH") {
            my $graphdata2 = simplehashclone($graphdata);
            $graphdata = {};
            grep {
               if ($columndef->{mapids}->{$_}) {
                  $graphdata->{ $columndef->{mapids}->{$_} } = $graphdata2->{$_};
               } else {
                  $graphdata->{$_} = $graphdata2->{$_};
               }
            } keys %$graphdata2;
         }

         my $calwndown = $self->{"q"}->param("calwndown") || $columndef->{calwndown};
         $calwndown -= 2;
         $calwndown = 40 if ($calwndown > 40);
         $calwndown = 1  if ($calwndown < 1);
         if ($calwndown) {
            my $graphdata2 = simplehashclone($graphdata);
            $graphdata = {};
            #die("Debugxxx:".join("\n", map { ":".$graphdata2->{$_}."<:>".$_.":" } ((sort { $graphdata2->{$b} <=> $graphdata2->{$a} } keys %$graphdata2))));
            grep { $graphdata->{$_} = $graphdata2->{$_}; delete $graphdata2->{$_} } ((sort { $graphdata2->{$b} <=> $graphdata2->{$a} } keys %$graphdata2)[0..$calwndown]);

            my $sum = 0;
            grep { $sum += $graphdata2->{$_} } keys %$graphdata2;
            $graphdata2 = undef;
            $graphdata->{"Sonstige"} = $sum if $sum;
         }
         unless ($columndef->{noshowpercentage}) {
            my $sum = 0;
            my $graphdata3 = {};
            grep { $sum += $graphdata->{$_} } keys %$graphdata;
            #grep { $graphdata3->{$_} = $graphdata->{$_} } keys %$graphdata;
            grep { $graphdata3->{$_." (".((int(((1000/$sum)*$graphdata->{$_}))/10))."%)" } = $graphdata->{$_} if $graphdata->{$_} } keys %$graphdata;
            $graphdata = $graphdata3;
         }
         $graph->set_legend(keys(%$graphdata)) unless $columndef->{nolegend};
         #die("KEys sind".join("\n", map { ":".$_.":" } keys(%$graphdata)));

         $graph->set( legendclr => [ "black" ], textclr => [ "black" ] );
         $graph->set( dclrs => [ GD::Graph::colour::colour_list( scalar keys(%$graphdata) ) ] );

         $graph->set_title_font(['verdena', 'arial', gdMediumBoldFont], 24);
         $graph->set_value_font(gdLargeFont);
         $graph->set_legend_font(['verdana', 'arial', gdMediumBoldFont], 24);
         my $tmp = [];
         for (my $i=0; $i<=(scalar(keys(%$graphdata))); $i++) { $tmp->[$i] = '' };
         my $format = $graph->export_format;
         print "Content-Type: image/gif\n\n".$graph->plot([$tmp, [values(%$graphdata)]])->$format()
      }
      return $DONE;
   }, {noStyle => 1});

   $self->AddHandler("setfilter", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      my $autret = undef;

      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         $self->sendLine("SETFILTER ".$targetself->{table}." BEGIN");
         $self->sendFilterColumns($targetself, $targetself->{table});
         $self->sendLine("SETFILTER ".$targetself->{table}." END");
         $targetself->{state} = $SETFILTER;
         return $RUNNING;
      } elsif ($targetself->{state} == $SETFILTER) {
         return $autret if (($autret = $self->setFilter($line, $targetself)) != $ACTIONOK);
         $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      }
      return $DONE;
   });

   $self->AddHandler("filterreset", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      my $autret = undef;

      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         $self->sendLine("FILTERRESET");
         $targetself->{state} = $FILTERRESET;
         return $RUNNING;
      } elsif ($targetself->{state} == $FILTERRESET) {
         return $autret if (($autret = $self->setFilterReset($line, $targetself)) != $ACTIONOK);
         $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      }
      return $DONE;
   });

   $self->AddHandler("logout", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};

      my $autret;
      return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
      $self->sendLine("LOGOUT");
      delete $targetself->{sessionid};
      if (my $newjob = $self->getHandler($self->{config}->{DEFAULTJOB} || "defaultjob")) {
         $self->AddHandler($self->{job}, $newjob->{handler});
      } else {
         print "Relogin impossible. No defaultjob.\n";
      }
      return $DONE;
   });

   $self->AddHandler("showfile", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         print $self->{"q"}->header();
         # ToDo: Wir sollten den Pfadnamen ordentlich ueberpruefen...
         my $filename = $self->{"q"}->param("filename");
         if (($filename =~ m,\.\.,) || ($filename =~ m,^\/,) || (!($filename =~ /^[A-Za-z0-9\/\.]+$/))) {
            print "<font color='red'><b>ERROR:</b> ".$self->{text}->{INVALID_FILENAME}."</font><br>\n";
            return $DONE;
         }
         unless ($self->{config}->{STATPATH}) {
            print "<font color='red'><b>ERROR:</b> ".$self->{text}->{NO_STATPATH}."</font><br>\n";
            return $DONE;
         }
         $filename = $self->{config}->{STATPATH}."/".$self->{"q"}->param("filename");
         unless ((-f $filename) && (open(STATFILE, "<".$filename))) {
            print "<html>\n<head>";
            print "<title>".$self->{text}->{MAIN_TITLE}."</title>\n";
            print "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />\n";
            print "<meta http-equiv=\"pragma\" content=\"no-cache\"/>\n";
            print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/url.css\" />\n";
            print "</head>\n<body>\n";
            print "<div id=\"all_container\">\n<div id=\"page_fullframe\">\n";
            print "<div id=\"fullframe_title\"><center><h1>".$self->{text}->{MAIN_TITLE}."</h1></center></div>\n";
            print "<div id=\"fullframe_content\">\n";
            print "<font color='red'><b>ERROR: </b>".$self->{"q"}->param("filename").": ".$self->{text}->{AUSW_UNAVAIL}."</font>\n";
            if (my $newjob = $self->getHandler($self->{config}->{DEFAULTJOB} || "defaultjob")) {
               $self->AddHandler($self->{job}, $newjob->{handler});
            }
            return $DONE;
         }
         my $url = $self->{"q"}->url(-relative=>1);
         my $sessionid = $targetself->{sessionid};
         while(<STATFILE>) {
            s,\%url\%,$url,g;
            s,\%sessionid\%,$sessionid,g;
            if (/\<\/body\>/) {
               print "<center>";
               print $self->HashButton( {
                  sessionid => $targetself->{sessionid},
                  job => $self->{config}->{DEFAULTJOB} || "defaultjob",
                  table => $targetself->{table}
               }, $self->{text}->{B_ACTION});
               print "</center>";
            }
            print;
         }
      }
      return $DONE;
   }, {noStyle => 1});

   $self->AddHandler("printshow", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      my $autret;

      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         print 'Content-Type: application/force-download'."\n";
         print 'Content-Disposition: attachment; filename="'.($self->getTableDefiniton($targetself->{table})->{label}||$targetself->{table}).'.html"'."\n\n";
         print $self->{header};
         if ($self->{"q"}->param("stable")) {
            $self->sendLine("SETFILTER ".$targetself->{table}." BEGIN");
            $self->sendLine($self->{"q"}->param("stable").$TSEP.$UNIQIDCOLUMNNAME.": ".$self->{"q"}->param("filterid"))
               if ($self->{"q"}->param("stable") && $self->{"q"}->param("filterid"));
            $self->sendLine("SETFILTER ".$targetself->{table}." END");
            $targetself->{state} = $SETFILTER;
         } else {
            $self->sendLine("GETTABLEINFO ".$targetself->{table});
            $targetself->{state} = $GETTABLEINFO;
         }
         return $RUNNING;
      } elsif ($targetself->{state} == $SETFILTER) {
         return $autret if (($autret = $self->setFilter($line, $targetself)) != $ACTIONOK);
         $self->sendLine("GETTABLEINFO ".$targetself->{table});
         $targetself->{state} = $GETTABLEINFO;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETTABLEINFO) {
         my $var = "curInfo";
         return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETTABLEINFO", $var)) != $ACTIONOK);
         $self->sendLine("GETFILTER ".$targetself->{table});
         $targetself->{state} = $GETFITLER;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETFITLER) {
         my $var = "curFilter";
         return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETFILTER", $var)) != $ACTIONOK);
         my $tmp = $self->getTableDefiniton($targetself->{table});
         my $sortcolumn = ''; #$targetself->{table}.".".$UNIQIDCOLUMNNAME;
         $sortcolumn = $self->{"q"}->param("sortby") if $self->{"q"}->param("sortby");#$tmp->{columns}->{$self->{"q"}->param("sortby")}));
         $self->{tableskip} = 0; $self->{tablelines} = 2000;
         print "<font size='+2'><b>".($tmp->{label}||$targetself->{table})."</b></font><br>\n<br>\n";
         $self->sendLine("GET ".$targetself->{table}."  ".$self->{tableskip}." ".$self->{tablelines}." ".$sortcolumn);
         $targetself->{state} = $SHOWTABLE;
         return $RUNNING;
      } elsif ($targetself->{state} == $SHOWTABLE) {
         return $autret if (($autret = $self->showTable($line, $targetself, $stadium, 1)) != $ACTIONOK);
         return $DONE unless ($self->{"q"}->param("stable"));
         $self->sendLine("SETFILTER ".$targetself->{table}." BEGIN");
         $self->sendLine("SETFILTER ".$targetself->{table}." END");
         $targetself->{state} = $FILTERRESET;
         return $RUNNING;
      } elsif ($targetself->{state} == $FILTERRESET) {
         return $autret if (($autret = $self->setFilter($line, $targetself)) != $ACTIONOK);
      }
      return $DONE;
   }, {noStyle => 1});

   $self->AddHandler("show", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      my $autret;
      return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
      $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      return $DONE;
   });

   $self->AddHandler("undelpre", 
   $self->AddHandler("delpre", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         print "<h2>".(($self->{job} eq "undelpre") ? $self->{text}->{T_UNDELETE} : $self->{text}->{T_DELETE})."</h2>\n".(($self->{job} eq "undelpre") ? $self->{text}->{T_UNDELETE_DESC} : $self->{text}->{T_DELETE_DESC})."<br><br>";
         print $self->HashButton( {
            sessionid => $targetself->{sessionid},
            job => ($self->{job} eq "undelpre") ? 'undelpost' : 'delpost',
            table => $targetself->{table},
            $UNIQIDCOLUMNNAME => $self->{"q"}->param($UNIQIDCOLUMNNAME)||''
         }, ($self->{job} eq "undelpre") ? $self->{text}->{T_UNDEL} : $self->{text}->{T_DEL}, { link => 1 } );
         print "<br><br>";
         print $self->HashButton( {
            sessionid => $targetself->{sessionid},
            job => 'show',
            table => $targetself->{table},
         }, ($self->{job} eq "undelpre") ? $self->{text}->{T_UNDELNO} : $self->{text}->{T_DELNO}, { link => 1 } );
         print "<br><br>Details:<hr>";
         $targetself->{hidebuttons} = 1;
         $targetself->{filterid} = $self->{"q"}->param($UNIQIDCOLUMNNAME)||'';
         $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      }
      return $DONE;   
   }));

   $self->AddHandler("updatepost", 
   $self->AddHandler("addpost", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         unless (defined($targetself->{table}) && defined($self->getTableDefiniton($targetself->{table})->{columns})) {
            #...damit kein "Use of uninitialized value in concatenation (.) or string..." kommt.
            print $self->{text}->{UNKNOWN_TABLE}." :".$targetself->{table}.":\n";
            return $DONE ;  
         }
         my $tabledef = $self->getTableDefiniton($targetself->{table})->{columns};
         foreach my $column (keys(%$tabledef)) {
            # FIXME/ToDo/XXX: Syntaxcheck gehoert eigentlich in den DBManager und nicht ins GUI...
            # my $tmp = $self->Syntax_Check($column, $targetself->{table}, $self->{"q"}->param($column));
            #if (defined($tmp) && ($tmp ne "1")) {
            #   print "<font color='red'><b>ERROR:</b> '".$column."'".$self->{text}->{WRONG_FORMAT}.": ".$tmp."</font><br>\n";
            #   return $DONE;
            #} else {
               my $curcolumn = mergeColumnInfos($self->getDBBackend($targetself->{table}), $tabledef->{$column});
               #print "Sytanxcheck:".$self->{"q"}->param($column).":".$tabledef->{$column}->{syntaxcheck}.":" if $tabledef->{$column}->{syntaxcheck};
               if ($curcolumn->{syntaxcheck} && $self->{"q"}->param($column) && (!($self->{"q"}->param($column) =~ (/$curcolumn->{syntaxcheck}/)))) {
                   print "<font color='red'><b>ERROR:</b> '".($curcolumn->{label}."('".$column."')"||"'".$column."'")."'".$self->{text}->{WRONG_SYNTAX}.": '".$curcolumn->{syntaxcheck}."'</font><br>\n";
                   return $DONE;
               }
               unless (defined($self->{"q"}->param($column))) {
                  unless ((!$curcolumn->{notnull}) ||
                     (($curcolumn->{type} eq "boolean") ||
                        ($curcolumn->{type} eq $DELETEDCOLUMNNAME) ||
                        ($curcolumn->{type} eq "date") ||
                        # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
                        ($curcolumn->{type} eq "datetime") ||
                          ($curcolumn->{type} eq $UNIQIDCOLUMNNAME) ||
                          ($curcolumn->{readonly})))
                  {
                     print $column;
                     print "(".$curcolumn->{label}.")" if $curcolumn->{label};
                     print $self->{text}->{IS_MISSING}."\n";
                     return $DONE;
                  }
               }
            #}
         }
         $targetself->{state} = $INSERTDATA;
         my $cmd = '';
         if  ($self->{"q"}->param($UNIQIDCOLUMNNAME)) {
            $cmd = "UPDATE";
            $self->sendLine($cmd." ".$targetself->{table}." ".$self->{"q"}->param($UNIQIDCOLUMNNAME)." BEGIN");
         } else {
            $cmd = "NEW";
            $self->sendLine($cmd." ".$targetself->{table}." BEGIN");      
         }
         foreach my $column (keys(%$tabledef)) {
            if ($tabledef->{$column}->{type} eq "virtual") {
               next;
            } elsif ($tabledef->{$column}->{type} eq "boolean") {
               my $tmp = $self->{"q"}->param($column) ? "1" : "0";
               $self->sendLine($targetself->{table}.$TSEP.$column.": ".$tmp);
            } elsif (($tabledef->{$column}->{type} eq "date") ||
                     # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
                     ($tabledef->{$column}->{type} eq "datetime")) {
               $self->sendLine($targetself->{table}.$TSEP.$column.": ".$self->getStringForDate($column, $_));
            } elsif (($tabledef->{$column}->{type} eq $DELETEDCOLUMNNAME) || ($tabledef->{$column}->{type} eq 'boolean')) {
               $self->sendLine($targetself->{table}.$TSEP.$column.": ".((grep { $_ && (!/^false$/i) } ($self->{"q"}->param($column))) ?'1':'0'));
            } else {
               my $tmp = $self->{"q"}->param($column);
               # TODO/FIXME: Im Moment unterst�tzen wir nur einzeilige Eingaben!
               $tmp =~ s/[\n\r]+/ /g;
               $self->sendLine($targetself->{table}.$TSEP.$column.": ".$tmp);
            }
         }
         if ($self->{"q"}->param($UNIQIDCOLUMNNAME)) {
            $self->sendLine($cmd." ".$targetself->{table}." ".$self->{"q"}->param($UNIQIDCOLUMNNAME)." END");
         } else {
            $self->sendLine($cmd." ".$targetself->{table}." END");      
         }
         return $RUNNING;
      } elsif ($targetself->{state} == $INSERTDATA) {
         if (/^(NEW|UPDATE)\s+\S+\s+(\S+)(\s(.*))?$/) {
            my $cmd = $1;
            my $action = $2;
            my $error = $4;
            if ($action eq "OK") {
               print $self->{text}->{DATA}." ";
               $cmd eq "NEW" ?
                  print $self->{text}->{INSERTED} :
                  print $self->{text}->{REFRESHED};
               print ".\n";
            } else {
               print "<font color='#FF0000'><b>".$self->{text}->{ERROR_DURING};
               $cmd eq "NEW" ?
                  print $self->{text}->{INSERT} :
                  print $self->{text}->{REFRESH};
               print " ".$self->{text}->{OF_DATA}.":</b> ".$error."</font>\n";
            }
         } else {
            print "PROTOKOLL ERROR 331.\n";
            return $PROTOKOLLERROR;
         }
         print "<br><br>";
         $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      }
      return $DONE;
   }));

   $self->AddHandler("undelpost",
   $self->AddHandler("delpost", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         unless (defined($targetself->{table}) && defined($self->getDBBackend($targetself->{table}))) {
            #...damit kein "Use of uninitialized value in concatenation (.) or string..." kommt.
            print $self->{text}->{UNKNOWN_TABLE}." :".$targetself->{table}.":\n";
            return $DONE ;  
         }
         unless (defined($self->{"q"}->param($UNIQIDCOLUMNNAME))) {
            print $self->{text}->{ERR_NO_ID}."\n";
            return $DONE;
         }
         $targetself->{state} = ($self->{job} eq "undelpost") ? $UNDELENTRY : $DELENTRY;
         $self->sendLine((($self->{job} eq "undelpost") ? "UNDEL" : "DEL")." ".$targetself->{table}." ".$self->{"q"}->param($UNIQIDCOLUMNNAME));
         return $RUNNING;
      } elsif (($targetself->{state} == $DELENTRY) ||
               ($targetself->{state} == $UNDELENTRY)) {
         if (/^((UN)?DEL) (\S+) (\S+)(\s(.*))?$/) {
            my $cmd = $1;
            my $uniqid = $3;
            my $action = $4;
            my $error = $5 || '';
            if ($action eq "OK") {
               print "".(($self->{job} eq "undelpost") ? $self->{text}->{ENTRY_UNDELETED} : $self->{text}->{ENTRY_DELETED})."\n";
            } else {
               print "<font color='#FF0000'><b>ERROR:</b> ".$error."</font>\n";
            }
         } else {
            print "PROTKOLL ERROR 244.\n";
            return $DONE;
         }
         print "<br><br>";
         $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
      }
      return $DONE;
   }));

   $self->AddHandler("search", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      my $autret = undef;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      my $tag = "GETFILTER";
      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         print "<h2>".$self->{text}->{T_SEARCH}."</h2>\n<em>".$self->{text}->{T_SEARCH_DESC}."</em><br><br>\n";
         $targetself->{tableQueue} = [];
         my $db = $self->getDBBackend($targetself->{table});
         #foreach (keys(%{$db->{tables}})) {
         #   my $tmp = $self->getTableDefiniton($targetself->{table})->{columns}->{$_."_".$UNIQIDCOLUMNNAME};
         #   push(@{$targetself->{tableQueue}}, $_) if (defined($tmp) and !(defined($tmp->{nopop})) );
         #}
         grep {
            my $column = $_;
            grep {
               my $searchas = $self->getTableDefiniton($targetself->{table})->{columns}->{$column}->{searchas};
               my $useas = $self->getTableDefiniton($targetself->{table})->{columns}->{$column}->{useas};
               push(@{$targetself->{tableQueue}}, $_) if (($_."_".$UNIQIDCOLUMNNAME eq $searchas) || ((!$searchas) && ($_."_".$UNIQIDCOLUMNNAME eq $column)) || ($_."_".$UNIQIDCOLUMNNAME eq $useas));
            } (keys(%{$db->{tables}}))
         } keys %{$db->{tables}->{$targetself->{table}}->{columns}};
         if (scalar(@{$targetself->{tableQueue}})) {
            my $tmp = pop(@{$targetself->{tableQueue}});
            $self->sendLine("GET ".$tmp);
            $targetself->{state} = $GETDATA;
            return $RUNNING;
         } else {
            $self->sendLine($tag." ".$targetself->{table});
            $targetself->{state} = $GETFITLER;
            return $RUNNING;
         }
      } elsif ($targetself->{state} == $GETDATA) {
         return $autret if (($autret = $self->retrieveTables($line, $targetself, $stadium, $targetself->{tableQueue})) != $ACTIONOK);
         $self->sendLine($tag." ".$targetself->{table});
         $targetself->{state} = $GETFITLER;
         return $RUNNING;
      } elsif ($targetself->{state} == $GETFITLER) {
         my $var = "curFilter";
         return $autret if (($autret = $self->retrieveBasic($line, $targetself, $tag, $var)) != $ACTIONOK);
         #print "ZZZ:".$var.":".join(",", map { $_.":".$targetself->{$var}->{$_} } keys %{$targetself->{$var}}).":<br>\n";
         print "<FORM method='post' action='".$self->{"q"}->url(-relative=>1)."'>\n";
         print $self->printSearchFormFor($targetself->{table}, $self->{text}->{B_USE_FILTER}, $targetself->{sessionid}, $targetself->{tableCache}, $targetself->{$var});
         print "</form>\n";
      }
      return $DONE;
   });

   $self->AddHandler("addpre", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      my $autret = undef;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});

      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         print "<h2>".$self->{text}->{T_ADD}."</h2>\n<em>".$self->{text}->{T_ADD_DESC}."</em><br><br>\n";
         $targetself->{tableQueue} = [];
         my $db = $self->getDBBackend($targetself->{table});
         foreach (keys(%{$db->{tables}})) {
            if (defined($db->{tables}->{$targetself->{table}}->{columns}->{$_."_".$UNIQIDCOLUMNNAME})) {
               push(@{$targetself->{tableQueue}}, $_);
            }
         }
         if (scalar(@{$targetself->{tableQueue}})) {
            my $curtable = pop(@{$targetself->{tableQueue}});
            my $sortcolumn = $db->{tables}->{$curtable}->{crossShowInSelect} || '';
            $self->sendLine("GET ".$curtable."    ".$sortcolumn);
            $targetself->{state} = $GETDATA;
            return $RUNNING;
         } else {
            $self->sendLine("GET ".$targetself->{table}."  ".$self->{tableskip}." ".$self->{tablelines});
            $targetself->{state} = $GETDATA;
            return $RUNNING;
         }
      } elsif ($targetself->{state} == $GETDATA) {
         return $autret if (($autret = $self->retrieveTables($line, $targetself, $stadium, $targetself->{tableQueue})) != $ACTIONOK);
         print $self->printFormFor($targetself->{table}, $self->{text}->{FORM_ADD},"addpost", $targetself->{sessionid}, undef, undef, undef, $targetself->{tableCache}, $targetself, 1);
      }
      return $DONE;
   });

   $self->AddHandler("changepasspre", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};

      my $table = $self->{"q"}->param("table");
      $table = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if ((!$targetself->{sessionid}) && (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK));
         print "<h2>".$self->{text}->{T_CHANGEPASS}."</h2>\n<em>".$self->{text}->{T_CHANGEPASS_DESC}."</em><br><br>\n";
         print "<FORM method='POST' action='".$self->{"q"}->url(-relative=>1)."'>\n";
         print "<table border='0'>";
         print "<tr><td>Password:</td><td><INPUT type='password' name='passnew' autocomplete='off'></td></tr>";
         print "<tr><td>Bestaetignung:</td><td><INPUT type='password' name='passnew2' autocomplete='off'></td></tr>";
         print "</table>";
         print $self->HashButton( {
            sessionid => $targetself->{sessionid},
            job => "changepasspost"
         }, $self->{text}->{FORM_CHANGE}, { noform => 1 } );
         print "</FORM>";
      }
      return $DONE;
   });

   $self->AddHandler("changepasspost", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};

      if ($targetself->{state} == $NOSTATE) {
         my $autret;
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         unless ($self->{"q"}->param("passnew")) {
            print "<font color='#FF0000'><b>ERROR:</b> You have to enter a password!</font>";
            if (my $newjob = $self->getHandler("changepasspre")) {
               $self->AddHandler($self->{job}, $newjob->{handler});
            }
            return $DONE;
         }
         unless ($self->{"q"}->param("passnew2") eq $self->{"q"}->param("passnew")) {
            print "<font color='#FF0000'><b>ERROR:</b> Your passwords differ. Please try again!</font>";
            if (my $newjob = $self->getHandler("changepasspre")) {
               $self->AddHandler($self->{job}, $newjob->{handler});
            }
            return $DONE;
         }
         $self->sendLine("PASSWD ".$self->{"q"}->param("passnew"));
         $targetself->{state} = $INSERTDATA;
         return $RUNNING;
      } elsif ($targetself->{state} == $INSERTDATA) {
         if (/^(PASSWD)\s+(\S+)(\s(.*))?$/) {
            my $cmd = $1;
            my $action = $2;
            my $error = $4;
            if ($action eq "OK") {
               print $self->{text}->{PASSCHANGED}."<br><br>\n";
               if (my $newjob = $self->getHandler($self->{config}->{DEFAULTJOB} || "defaultjob")) {
                  $self->AddHandler($self->{job}, $newjob->{handler});
               }
               return $DONE;
            } else {
               print "<font color='#FF0000'><b>".$self->{text}->{ERROR_DURING}." ".
                  (($cmd eq "NEW") ? $self->{text}->{INSERT} : $self->{text}->{REFRESH}).
                  " ".$self->{text}->{OF_DATA}.":</b> ".$error."</font>\n";
            }
         } else {
            print "PROTOKOLL ERROR 1301.\n";
            return $PROTOKOLLERROR;
         }
      }
      return $DONE;
   });

   $self->AddHandler("assigncsvfile", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      $targetself->{table} = $self->{"q"}->param("table");
      $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($targetself->{table});
      $targetself->{filename} = $self->{"q"}->param("filename") || '';

      my $autret;
      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         $self->sendLine("ASSIGNFILE ".$targetself->{table}." ".$targetself->{filename});
         $targetself->{state} = $SETASSIGNFILES;
         return $RUNNING;
      } elsif ($targetself->{state} == $SETASSIGNFILES) {
         if (/^ASSIGNFILE\s+\S+\s+OK$/) {
            #print "Selected file ".$targetself->{filename}."\n";
            $self->AddHandler($self->{job}, sub { my $self = shift; return $self->showTableHandler(@_); });
         } else {
            print "File ".$targetself->{filename}." cannot be assigend!\n";
         }
      }
      return $DONE;
   });

   $self->AddHandler("updatepre", sub {
      my $self = shift;
      my $targetself = shift;
      my $line = shift;
      my $stadium = shift || 0;
      $_ = $line->{data};
      my $autret = undef;

      my $table = $self->{"q"}->param("table");
      $table = $self->{config}->{DEFAULTTABLE} unless $self->getDBBackend($table);
      if ($targetself->{state} == $NOSTATE) {
         return $autret if (($autret = $self->authenticate($line, $targetself, $stadium)) != $ACTIONOK);
         $self->sendLine("FILTERRESET");
         $targetself->{state} = $FILTERRESET;
         return $RUNNING;
      } elsif ($targetself->{state} == $FILTERRESET) {
         return $autret if (($autret = $self->setFilterReset($line, $targetself)) != $ACTIONOK);
         print "<h2>".$self->{text}->{T_EDIT}."</h2>\n<em>".$self->{text}->{T_EDIT_DESC}."</em><br><br>\n";
         unless ($self->{"q"}->param($UNIQIDCOLUMNNAME)) {
            print "<font color='#FF0000'><b>ERROR:</b> $self->{text}->{ERR_NO_ID}</font><br><br>\n";
            return $DONE;
         }
         my $db = $self->getDBBackend($table);
         $targetself->{tableQueue} = [];
         foreach (keys(%{$db})) {
            if (defined($db->{$table}->{columns}->{$_."_".$UNIQIDCOLUMNNAME})) {
               push(@{$targetself->{tableQueue}}, $_);
            }
         }
         if (scalar(@{$targetself->{tableQueue}})) {
            my $curtable = pop(@{$targetself->{tableQueue}});
            my $sortcolumn = $curtable.$TSEP.$db->{tables}->{$curtable}->{crossShowInSelect} || '';
            $self->sendLine("GET ".$curtable."    ".$sortcolumn);
            $targetself->{state} = $GETDATA;
            return $RUNNING;
         } else {
            $self->sendLine("GET ".$table." ".$self->{"q"}->param($UNIQIDCOLUMNNAME));
            $targetself->{state} = $SHOWTABLE;
            return $RUNNING;
         }
      } elsif ($targetself->{state} == $GETDATA) {
         return $autret if (($autret = $self->retrieveTables($line, $targetself, $stadium, $targetself->{tableQueue})) != $ACTIONOK);
         $self->sendLine("GET ".$table." ".$self->{"q"}->param($UNIQIDCOLUMNNAME));
         $targetself->{state} = $SHOWTABLE;
         return $RUNNING;
      } elsif ($targetself->{state} == $SHOWTABLE) {
         if (/^GET (\S+) (\S+)(\s(\S+))?(\s(\S+))?(\s*[.*])?$/) {
            my $table = $1;
            my $action = $2;
            my $lines = $4;
            my $filtered = $6;
            $targetself->{filtered} = $filtered ? 1 : 0;
            my $error = $5.$7;
            if ($action eq "BEGIN") {
               return $RUNNING;
            } elsif ($action eq "FAILED") {
               print "<font color='#FF0000'><b>ERROR:</b> ".$error."</font>\n";
            } elsif ($action eq "NEXT") {
               #print "<font color='#FF0000'><b>ERROR:</b> $self->{text}->{ERR_LINES_EXPECTED}</font>\n";
               return $RUNNING;
            } elsif ($action eq "END") {
               unless ($self->{"q"}->param($UNIQIDCOLUMNNAME) eq $targetself->{mydefaults}->{$table.$TSEP.$UNIQIDCOLUMNNAME}) {
                  print "<font color='#FF0000'><b>ERROR:</b> Query returned wrong ID.</font><br>\n";
                  return $DONE;
               }
               print $self->printFormFor($table, $self->{text}->{FORM_CHANGE}, "updatepost", $targetself->{sessionid}, undef, $targetself->{mydefaults}, $self->{"q"}->param($UNIQIDCOLUMNNAME), $targetself->{tableCache}, $targetself);
               delete $targetself->{mydefaults};
            } else {
               print "PROTOKOLL ERROR 4.<br>\n";
               return $PROTOKOLLERROR;
            }
         } elsif (/^([^:]+):\s(.*)$/) {
            my $key = $1;
            my $value = $2;
            $targetself->{mydefaults}->{$key} = $value;
            return $RUNNING;
         } else {
            print "PROTOKOLL ERROR 5.<br>\n";
            return $PROTOKOLLERROR;
         }
      }
      return $DONE;
   });
}

sub AddHandler {
   my $self = shift;
   my $name = shift;
   my $handler = shift;
   my $options = shift || {};
   
   unless ($name) {
      Log("No name!", $ERROR);
      return undef;
   }

   my $new = bless($options);
   $new->{handler} = $handler;

   if (exists($self->{target}->{$name}) &&
              $self->{target}->{$name}) {
      $self->{target}->{$name} = [$self->{target}->{$name}]
         if (ref($self->{target}->{$name}) ne "ARRAY");
      if ($options->{postRun}) {
         push(@{$self->{target}->{$name}}, $new);
      } elsif ($options->{deleteAll}) {
         $self->{target}->{$name} = $new;
      } else {
         unshift(@{$self->{target}->{$name}}, $new);
      }
   } else {
      $self->{target}->{$name} = $new;
   }
   return $handler;
}

sub getHandler {
   my $self = shift;
   my $name = shift;
   my $delete = shift;

   if (exists($self->{target}->{$name})) {
      if (ref($self->{target}->{$name}) eq "ARRAY") {
         return $delete ?
            pop(@{$self->{target}->{$name}}) :
                  $self->{target}->{$name}->[scalar(@{$self->{target}->{$name}}-1)];
      } else {
         return $delete ? 
            delete $self->{target}->{$name} :
                   $self->{target}->{$name};
      }
   } else {
      return undef;
   }
}

sub readConfig {
   my $self = shift;
   my $configfile = shift;

   unless (open(CFG, $configfile)) {
      print $self->{header};
      print "<font color='red'><b>ERROR:</b> ".$self->{text}->{MISSING_CONFIG}.":".$configfile."</font><br>\n";
      exit(0);
   }

   while (<CFG>) {
      chomp;
      s,^([^\#]*?)\#.*$,$1,;
      next if /^\s*$/;
      if (/^\s*(\S+)\s+([^\n\r]*)/) {
         Log("gui.pl: GuiInit: FOUND KEY:".$1.":".$2.":", $DEBUG);
         my $key = lc($1);
         my $value = $2;
         if ($key eq lc('ip')) {
            $self->{config}->{dbmanagerip} = $value;
         } elsif ($key eq lc('port')) {
            $self->{config}->{dbmanagerport} = $value;
         } elsif ($key eq lc('timeout')) {
            $self->{config}->{timeout} = $value;
         } elsif ($key eq lc('default')) {
            $self->{config}->{DEFAULTJOB} = $value;
         } elsif ($key eq lc('skip')) {
            $self->{config}->{DEFAULTTABLESKIP} = $value;
         } elsif ($key eq lc('lines')) {
            $self->{config}->{DEFAULTTABLELINES} = $value;
         } elsif ($key eq lc('statpath')) {
            $self->{config}->{STATPATH} = $value;
         } elsif ($key eq lc('defaulttable')) {
            $self->{config}->{DEFAULTTABLE} = $value;
         } elsif ($key eq lc('noheaderline')) {
            $self->{config}->{NOHEADERLINE} = $value;
         } else {
            $self->{config}->{$key} = $value;
         }
      } else {
         print $self->{"q"}->header();
         print "<font color='red'><b>ERROR:</b> ".$self->{text}->{INVALID_LOGLINE}." '".$_."'</font><br>\n";
         exit(0);
      }
   }
   close(CFG);
}

sub myLocalTime {
   my $time = shift;
   my @time = localtime($time);
   my @monate = qw( Januar Februar März April Mai Juni Juli August September Oktober November Dezember );
   return $time[3]." ".$monate[$time[4]]." ".($time[5]+1900);
}

sub getSelectionOfDynDBFiles {
   my $self = shift;
   my $targetself = shift;
   my $options = shift;
   my $ret = '';
   my $id = 0;
   if ($options->{db}->{type} =~ /^csv$/i) {
      foreach my $file (@{$options->{files}}) {
         next unless $file;
         $ret .= "  <option ";
         if ($options->{active} eq $file) {
            $ret .= "selected ";
            ${$options->{foundactive}}++ if
               (exists($options->{foundactive}) &&
                       $options->{foundactive});
         }
         $ret .= "value='".$file."'>";
         if ($options->{mtime}->[$id]) {
            $ret .= "".($targetself->{laststartttime} ? 
               myLocalTime($targetself->{laststartttime}) : myLocalTime(0))." - ".
               myLocalTime($options->{mtime}->[$id])." (".$file.")";
            $targetself->{laststartttime} = $options->{mtime}->[$id];
         } else {
            $ret .= $file;
         }
         $ret .= "</option>\n";
         $id++;
      }
      $ret .= "</select>\n";
   }
   return $id ? $ret : undef;
}

sub showTableHandler {
   my $self = shift;
   my $targetself = shift;
   my $line = shift;
   my $stadium = shift || 0;
   $_ = $line->{data};
   $targetself->{table} = $self->{"q"}->param("table");
   my $db = $self->getDBBackend($targetself->{table});
   my $curtabledef = $self->getTableDefiniton($targetself->{table});
   $targetself->{table} = $self->{config}->{DEFAULTTABLE} unless $db;
   my $autret;

   unless ($targetself->{selectiondone}) {
      if ($db->{type} =~ /^csv$/i) {
         unless ($targetself->{assignfiledone}) {
            if ($targetself->{state} == $NOSTATE) {
               $self->sendLine("GETASSIGNFILES ".$targetself->{table});
               $targetself->{state} = $GETASSIGNFILES;
               return $RUNNING;
            } elsif ($targetself->{state} == $GETASSIGNFILES) {
               return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETASSIGNFILES", "assignfiles")) != $ACTIONOK);
               my $foundactive = 0;
               if (exists($targetself->{assignfiles}->{filename}) &&
                     (ref($targetself->{assignfiles}->{filename}) eq "ARRAY")) {
                  foreach my $file (@{$targetself->{assignfiles}->{filename}}) {
                     $foundactive++
                        if ($targetself->{assignfiles}->{active} eq $file)
                  }
               }
               if ($foundactive == 0) {
                  $targetself->{filename} = undef;
                  if (ref($targetself->{assignfiles}->{filename}) eq "ARRAY") {
                     $targetself->{filename} = $targetself->{assignfiles}->{filename}->[0];
                  } elsif ($targetself->{assignfiles}->{filename}) {
                     $targetself->{filename} = $targetself->{assignfiles}->{filename};
                  }
                  if (defined($targetself->{filename})) {
                     #print "Selecting ".$targetself->{filename}."<br><br>\n";
                     $self->sendLine("ASSIGNFILE ".$targetself->{table}." ".$targetself->{filename});
                     $targetself->{state} = $SETASSIGNFILES;
                     return $RUNNING;
                  }
               }
               $targetself->{state} = $NOSTATE;
            } elsif ($targetself->{state} == $SETASSIGNFILES) {
               unless (/^ASSIGNFILE\s+\S+\s+OK$/) {
                  print "File ".$targetself->{filename}." cannot be assigend!\n";
               }
               $targetself->{state} = $NOSTATE;
            }
            $targetself->{assignfiledone}++;
         }

         if ($curtabledef->{doGetFilterForSelectionBlock}) {
            if ($targetself->{state} == $NOSTATE) {
               $self->sendLine("GETFILTER ".$targetself->{table});
               $targetself->{state} = $GETFITLER;
               return $RUNNING;
            } elsif ($targetself->{state} == $GETFITLER) {
               return $autret if (($autret = $self->retrieveBasic($line, $targetself, "GETFILTER", "curFilter")) != $ACTIONOK);
               $targetself->{state} = $NOSTATE;
            }
         }

         $targetself->{assignfiles}->{filename} =
            [$targetself->{assignfiles}->{filename}]
     if (ref($targetself->{assignfiles}->{filename}) ne "ARRAY");
         $targetself->{assignfiles}->{mtime} =
            [$targetself->{assignfiles}->{mtime}]
     if (ref($targetself->{assignfiles}->{mtime}) ne "ARRAY");
         if (my $ret = $self->getSelectionOfDynDBFiles(
            $targetself, {
               files  => $targetself->{assignfiles}->{filename},
               mtime => $targetself->{assignfiles}->{mtime},
               active => $targetself->{assignfiles}->{active},
               table  => $targetself->{table},
               db     => $db,
               parent => $self,
               filter => $targetself->{curFilter}
            })) {
            print "<FORM method='POST' name='myform' action='".$self->{"q"}->url(-relative=>1)."'>\n";
            print "<select name='filename' id='filename'>\n";
            print $ret;
            print $self->HashButton( {
               sessionid => $targetself->{sessionid},
               job => "assigncsvfile",
               table => $targetself->{table},
               $UNIQIDCOLUMNNAME => $self->{"q"}->param($UNIQIDCOLUMNNAME)
            }, "Setzen", { noform => 1 } );
            print "</form>";
         } else {
            print "Keine Logdateien vorhanden.\n";
            return $DONE;
         }
      }

      $targetself->{selectiondone}++;
   }

   my $tag = "GETTABLEINFO";
   if ($targetself->{state} == $NOSTATE) {
      unless ($targetself->{sessionid}) {
         print "SESSION NOT FOUND!\n";
         return $DONE;
      }
      if($self->{"q"}->param("stable") && (!$self->{"q"}->param("astable"))) {
         $self->sendLine("FILTERRESET");
         $targetself->{astate} = $FILTERRESET;
         $targetself->{state} = $ASSIGN;
         return $RUNNING;
      }
      $self->sendLine($tag." ".$targetself->{table});
      $targetself->{state} = $GETTABLEINFO;
      return $RUNNING;
   } elsif ($targetself->{state} == $GETTABLEINFO) {
      my $var = "curInfo";
      return $autret if (($autret = $self->retrieveBasic($line, $targetself, $tag, $var)) != $ACTIONOK);
      my $tmp = $self->getTableDefiniton($targetself->{table});
      print "<h2>".$self->{text}->{TABLE}." ".($tmp->{label} || $targetself->{table})."</h2>\n";
      print "<em>".$tmp->{description}."</em><br><br>\n" if $tmp->{description};
      my $sortcolumn = ''; #$targetself->{table}.".".$UNIQIDCOLUMNNAME;   
      $sortcolumn = $self->{"q"}->param("sortby") if $self->{"q"}->param("sortby");# (exists($tmp->{columns}->{$self->{"q"}->param("sortby")}));
      $self->sendLine("GET ".$targetself->{table}." ".($targetself->{filterid}||'')." ".$self->{tableskip}." ".$self->{tablelines}." ".$sortcolumn);
      $targetself->{state} = $SHOWTABLE;
      return $RUNNING;
   } elsif ($targetself->{state} == $SHOWTABLE) {
      return $autret if (($autret = $self->showTable($line, $targetself, $stadium)) != $ACTIONOK);
   } elsif ($targetself->{state} == $ASSIGN) {
      return $autret if (($autret = $self->showAssignTable($line, $targetself, $stadium)) != $ACTIONOK);
   }
   return $DONE;
};

sub printSelectBoxFor {
   my $self = shift;
   my $tableCache = shift;
   my $sourcetable = shift;
   my $column = shift;
   my $table = shift;
   my $filterCache = shift;
   my $all = shift;
   my $last = undef;
   my $tmp = '';
   $tmp .= "<select name='".($all?'search':'').$column."'>\n";
   $tmp .= "  <option value=''>*</option>\n" if ($all);
   $tmp .= "  <option value='0'>-</option>\n";
   if (exists($tableCache->{$table}) && (ref($tableCache->{$table}) eq "ARRAY") && scalar(@{$tableCache->{$table}})) {
      foreach my $linename (@{$tableCache->{$table}}) {
         next if ((!$all) && scalar(grep { $linename->{$table.$TSEP.$UNIQIDCOLUMNNAME} eq $_ } @{$self->getTableDefiniton($table)->{hiddenids}}));
         next if (defined($last) && ($linename->{$table.$TSEP.$UNIQIDCOLUMNNAME} eq $last));
         # Hm... war mal das hier: my $value = $self->getValuesForColumn($column, $table, $linename );
         my $value = $self->getValuesForColumn($table."_".$UNIQIDCOLUMNNAME, $table, $linename );
         $tmp .= "  <option value='".$linename->{$table.$TSEP.$UNIQIDCOLUMNNAME}."'";
         $tmp .= " selected" if (exists($filterCache->{$sourcetable.$TSEP.$table."_".$UNIQIDCOLUMNNAME}) &&
                                defined($filterCache->{$sourcetable.$TSEP.$table."_".$UNIQIDCOLUMNNAME}) &&
                                        $filterCache->{$sourcetable.$TSEP.$table."_".$UNIQIDCOLUMNNAME} &&
                                       ($filterCache->{$sourcetable.$TSEP.$table."_".$UNIQIDCOLUMNNAME} eq $linename->{$table.$TSEP.$UNIQIDCOLUMNNAME}))
                               #|| ($self->{"q"}->param($column) && ($self->{"q"}->param($column) eq $linename->{$table.$TSEP.$UNIQIDCOLUMNNAME})))
         ;
         $tmp .= ">".($value||"UNDEF");
         $tmp .= "</option>\n";
         $last = $linename->{$table.$TSEP.$UNIQIDCOLUMNNAME};
      }
   }
   $tmp .= "</select>";
   return $tmp;
}

sub showAssignTable {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   my $stadium = shift || 0;
   $_ = $line->{data};

   my $selecttable = $self->{"q"}->param("stable");
   my $choosetable = $self->{"q"}->param("table");
   my $filterid = $self->{"q"}->param("filterid");

   my $db = undef;
   $targetself->{tablename} = $selecttable."_".$choosetable if $db = $self->getDBBackend($selecttable."_".$choosetable);
   $targetself->{tablename} = $choosetable."_".$selecttable if $db = $self->getDBBackend($choosetable."_".$selecttable);

   unless ($targetself->{tablename}) {
      Log("There is no mapping table for tables ".$selecttable." and ".$choosetable." !!!!!!", $ERROR);
      print "<font color='red'><b>ERROR:</b> There is no table to make mappings between ".$selecttable." and ".$choosetable."<br>\n";
      return $DONE;
   }

   if (($targetself->{astate} == $SETFILTER) ||
       ($targetself->{astate} == $FILTERRESET) ||
       ($targetself->{astate} == $INSERTDATA) ||
       ($targetself->{astate} == $DELENTRY)) {
      # States Antworten ueberpruefen
      if (($targetself->{astate} == $SETFILTER) ||
          ($targetself->{astate} == $FILTERRESET)) {
         my $autret;
         return $autret if (($targetself->{astate} == $SETFILTER) && (($autret = $self->setFilter($line, $targetself)) != $ACTIONOK));
         return $autret if (($targetself->{astate} == $FILTERRESET) && (($autret = $self->setFilterReset($line, $targetself)) != $ACTIONOK));
         if ($self->{"q"}->param("add")) {
            $targetself->{to_add} = [$self->{"q"}->param("add")];
         }
         if ($self->{"q"}->param("addsec") && $db->{tables}->{$targetself->{tablename}}->{boolcolumn}) {
            $targetself->{to_add_sec} = [$self->{"q"}->param("addsec")];
         }
         if ($targetself->{to_add} && $targetself->{to_add_sec}) {
            if (my $tmp2 = scalar(grep { my $tmp = $_; grep { $tmp eq $_ } @{$targetself->{to_add_sec}} } @{$targetself->{to_add}})) {
               print "<font color='#FF0000'><b>ERROR:</b>".($self->{text}->{ENTRIES_SEL_DOUBLE}||"You selected ".$tmp2." entries double!")."</font>\n";
               return $DONE;
            }
         }
         if ($self->{"q"}->param("delete")) {
            $targetself->{to_delete} = [$self->{"q"}->param("delete")];
         }
      } elsif ($targetself->{astate} == $INSERTDATA) {
         if (/^(NEW|UPDATE) \S+ (\S+)(\s(.*))?$/) {
            my $cmd = $1;
            my $action = $2;
            my $error = $4;
            if ($action eq "OK") {
            } else {
               print "<font color='#FF0000'><b>".$self->{text}->{ERROR_DURING}." ";
               $cmd eq "NEW" ?
                  print $self->{text}->{INSERT} :
                  print $self->{text}->{REFRESH};
               print " ".$self->{text}->{OF_DATA}.":</b> ".$error."</font>\n";
               return $DONE;
            }
         } else {
            print "PROTOKOLL ERROR 301.\n";
            return $PROTOKOLLERROR;
         }
         #$targetself->{astate} = $NOSTATE;
      } elsif($targetself->{astate} == $DELENTRY) {
         if (/^DEL (\S+) (\S+)(\s(.*))?$/) {
            my $uniqid = $1;
            my $action = $2;
            my $error = $4 || '';
            if ($action eq "OK") {
               #print $self->{text}->{ENTRY_DELETED}."<br><br>\n";
            } else {
               print "<font color='#FF0000'><b>ERROR:</b> ".$error."</font>\n";
               return $DONE;
            }
         } else {
            print "PROTKOLL ERROR 245.\n";
            return $DONE;
         }
      }

      # CMDs absetzen
      if ((my $tmp = pop(@{$targetself->{to_add_sec}})) || (my $tmp2 = pop(@{$targetself->{to_add}})) || (my $tmp3 = pop(@{$targetself->{to_delete}}))) {
         my $ourid = $tmp||$tmp2||$tmp3;
         my $bool = $tmp2 ? 1 : 0;
         if (($ourid eq "___ALL___") && ($db->{tables}->{$selecttable}->{nmset})){
            $self->sendLine("UPDATE ".$selecttable." ".$filterid." BEGIN");
            $self->sendLine($selecttable.$TSEP.$db->{tables}->{$selecttable}->{nmset}.": ".$bool);
            $self->sendLine("UPDATE ".$selecttable." ".$filterid." END");
         } elsif ($tmp3) {
            if ($targetself->{tablename} eq $choosetable) {
               $self->sendLine("UPDATE ".$choosetable." ".$tmp3." BEGIN");
               $self->sendLine($choosetable.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME.": 0");
               $self->sendLine("UPDATE ".$choosetable." ".$tmp3." END");
            } else {
               $self->sendLine("DEL ".$targetself->{tablename}." ".$tmp3);
               $targetself->{astate} = $DELENTRY;
               return $RUNNING;
            }
         } else {
            if ($targetself->{tablename} eq $choosetable) {
               $self->sendLine("UPDATE ".$choosetable." ".$ourid." BEGIN");
               $self->sendLine($choosetable.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME.": ".$filterid);
               $self->sendLine("UPDATE ".$choosetable." ".$ourid." END");
            } else {
               $self->sendLine("NEW ".$targetself->{tablename}." BEGIN");
               $self->sendLine($targetself->{tablename}.$TSEP.$choosetable."_".$UNIQIDCOLUMNNAME.": ".$ourid);
               $self->sendLine($targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME.": ".$filterid);
               $self->sendLine($targetself->{tablename}.$TSEP.$db->{tables}->{$targetself->{tablename}}->{boolcolumn}.": ".$bool)
                  if $db->{tables}->{$targetself->{tablename}}->{boolcolumn};
               $self->sendLine("NEW ".$targetself->{tablename}." END");
            }
         }
         $targetself->{astate} = $INSERTDATA;
         return $RUNNING;
      }

      # Nix mehr zu tun? Dann tun wa mal was anzeigen. =)

      $targetself->{tableQueue} = [];
      push(@{$targetself->{tableQueue}}, $selecttable);
      my $sortby = $choosetable.$TSEP.$UNIQIDCOLUMNNAME;
      # ToDo: Man sollte vieleicht ueberpruefen ob diese Spalte, die da von angegeben wird, ueberhaupt im Select drin ist.
      # Das aber bitte ueberall wo sortby verwendet wird!
      $sortby = $self->{"q"}->param("sortby") if $self->{"q"}->param("sortby");
      $self->sendLine("GET ".$choosetable."    ".$sortby." 1");
      $targetself->{astate} = $GETDATA;
      return $RUNNING;
   } elsif ($targetself->{astate} == $GETDATA) {
      my $autret;
      return $autret if (($autret = $self->retrieveTables($line, $targetself, $stadium, $targetself->{tableQueue})) != $ACTIONOK);
      my $label = $db->{tables}->{$selecttable}->{label}||$selecttable;
      my $tmp = $db->{tables}->{$targetself->{tablename}};
      print "<h2>".$self->{text}->{TABLE}." ".($tmp->{label} || $targetself->{table})."</h2>\n";
      print "<em>".$tmp->{description}."</em><br><br>\n" if $tmp->{description};
      print "<br><table border=0><tr><td>";
      print "<FORM method='POST' action='".$self->{"q"}->url(-relative=>1)."'>";
      print $label." ";
      print $self->printSelectBoxFor($targetself->{tableCache}, $targetself->{tablename}, 'filterid', $selecttable);
      print $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => $self->{"q"}->param("job")||'',
         table => $targetself->{table},
         sortby => $self->{"q"}->param("sortby")||'',
         stable => $selecttable||''
      }, "Change", { noform => 1 } );
      $label = $db->{tables}->{$targetself->{table}}->{label}||$targetself->{table};
      print "</FORM></td><td>";
      #print $self->HashButton( {
      #   sessionid => $targetself->{sessionid},
      #   job => 'setfilter',
      #   table => $targetself->{tablename}
      #}, "Tableview");
      #print "</td><td>";
      print $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => 'updatepre',
         table => $selecttable||'',
         id => $self->{"q"}->param("filterid")||''
      }, "Edit", { link => 1 } );
      print "</td></tr></table><br>";

      if ($targetself->{filtered}) {
         print "<em>!!! ".$self->{text}->{FILTER_ACTIVE}." ";
         print $self->HashButton( {
         sessionid => $targetself->{sessionid},
            job => 'setfilter',
            table => $choosetable||'',
            sortby => $self->{"q"}->param("sortby")||'',
            stable => $selecttable||''
         }, $self->{text}->{FILTER_RESET}, { link => 1 } );
         print "</em><br><br>\n";
      }

      #print "<br>MYTABLES:".join(",",keys(%{$targetself->{tableCache}})).":<br>\n";
      my $fset = undef;
      unless ($fset = getEntryWithID($targetself->{tableCache}, $selecttable, $filterid)) {
         print "<font color='red'><b>ERROR:</b> ".($self->{text}->{NOT_EXISTING_FILTER_COLUMN}||"You specified a not existing entry as filtercolumn!")."</font>\n";
         return $DONE;
      }

      #print "Test123:<br>";
      #print join(",", $self->{"q"}->param("add"));
      #print "<br><br>\n";
      #print "filtering for:<br>".$self->getLineForTable($selecttable, $fset)."<br><br>\n";

      print $self->{text}->{ORDERBY}."<br>";
      my $curtabledef = $db->{tables}->{$choosetable};
      print join(", ", map {
         my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$_});
         my $label = $curcolumn->{label} || $_;
         my $tmp = "_".$UNIQIDCOLUMNNAME;
         if (($_ =~ /^(.*)$tmp$/) && (exists($db->{tables}->{$1}))) {
            my $curtable = $1;
            "[ ".join(",", map { $self->giveMeLink(($db->{tables}->{$curtable}->{columns}->{$_}->{label}||$_), $curtable.$TSEP.$_, $choosetable, $selecttable, $targetself->{sessionid}, $self->{"q"}->param("job"), $filterid); } @{getAffectedColumns($db, $db->{tables}->{$curtable}->{columns}, 1)})." ]"
         } else {
            $self->giveMeLink($label, $choosetable.$TSEP.$_, $choosetable, $selecttable, $targetself->{sessionid}, $self->{"q"}->param("job"), $filterid);
         }
      } grep { my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$_});
               (!(($curcolumn->{hidden}) || ($curcolumn->{writeonly}))) } hashKeysRightOrder($curtabledef->{columns}));

      print "<br><br>";
      my $curcolumndef = [hashKeysRightOrder($db->{tables}->{$choosetable}->{columns})];

      my @plus = ();
      my @minus = ();

      #my $last = undef;
      #my $lastid = undef;
      my $printed = {};
      grep {
         #$_->{username} .= $_->{$UNIQIDCOLUMNNAME}.":".$last.":".$lastminus.":";
         #$last->{username} .= $last->{$UNIQIDCOLUMNNAME}.":";
         #Log("PPP:".$targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME.":".$selecttable.$TSEP.$UNIQIDCOLUMNNAME.":".join(",", keys %$_).":", $DEBUG)
         if (($_->{$targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME} || $_->{$selecttable.$TSEP.$UNIQIDCOLUMNNAME}) eq $filterid) {
            push(@minus, $_);
            $printed->{$_->{$choosetable.$TSEP.$UNIQIDCOLUMNNAME}}++;
            my $tmp = $_;
            @plus = grep { $_->{$choosetable.$TSEP.$UNIQIDCOLUMNNAME} ne $tmp->{$choosetable.$TSEP.$UNIQIDCOLUMNNAME} } @plus;
         } else {
            push(@plus, $_) if ((($targetself->{tablename} ne $choosetable) || (!($_->{$targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME}))) && (!($printed->{$_->{$choosetable.$TSEP.$UNIQIDCOLUMNNAME}}++)));
         }
         # users_tunnels_tunnels_iD
         #my $tmp = $targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME;
         #print "X:".$_->{$UNIQIDCOLUMNNAME}.":<br>\n";
         #print "Y:".$lastid.":".$last->{$UNIQIDCOLUMNNAME}.":".$targetself->{tablename}.$TSEP.$selecttable."_".$UNIQIDCOLUMNNAME.":<br>\n";
      } (@{$targetself->{tableCache}->{$choosetable}});
      @minus = sort { $b->{$targetself->{tablename}.$TSEP.$db->{tables}->{$targetself->{tablename}}->{boolcolumn}} <=>
                      $a->{$targetself->{tablename}.$TSEP.$db->{tables}->{$targetself->{tablename}}->{boolcolumn}} } @minus
         if ($db->{tables}->{$targetself->{tablename}}->{boolcolumn});

      #unless (custom_Assign_Handler($targetself->{tablename}, $choosetable, $selecttable, $fset)) {
         print "<FORM method='POST' action='".$self->{"q"}->url(-relative=>1)."'>";
         if (($db->{tables}->{$targetself->{tablename}}->{boolcolumn}) && ($db->{tables}->{$targetself->{tablename}}->{boolsingle})) {
            my @owners = map { $self->getLineForTable($choosetable, $_) } grep { $_->{$targetself->{tablename}.$TSEP.$db->{tables}->{$targetself->{tablename}}->{boolcolumn}} } @minus;
            print "<br>Owner: ";
            if (!scalar(@owners)) {
               $self->printMultipleSelectTable($choosetable, \@plus, "add", $choosetable.$TSEP.$UNIQIDCOLUMNNAME,
                                     $db->{tables}->{$targetself->{tablename}}->{boolcolumn}, undef,
                                     $db->{tables}->{$targetself->{tablename}}->{boolsingle})
           } else {
               # ToDo: Das ist was von MAN... sollte eigentlich auch da hin... aber nicht nur der Text,
               #       sondern auch die ganze Owner-Logik...
               print join(" // ", map { "<b>".$_."</b>" } @owners)."\n<br><font size='1'>To change the owner, first remove the owner from ".$self->{text}->{ASSIGNED}." list. Its the user with the [X] in front.</font>\n";
            }
            print "<br><br>";
         }
         print "<table><tr><td colspan=2>";
         print $self->{text}->{ASSIGNED}."</td><td>".$self->{text}->{UNASSIGNED}."</td>";
         print "<td>".$self->{text}->{UNUNASSIGNED}."</td>" if (($db->{tables}->{$targetself->{tablename}}->{boolcolumn}) && (!($db->{tables}->{$targetself->{tablename}}->{boolsingle})));
         print "</tr><tr><td>";
         my $isall = (($db->{tables}->{$selecttable}->{nmset}) && ($db->{tables}->{$targetself->{tablename}}->{usenmset})) ? ($fset->{$selecttable.$TSEP.$db->{tables}->{$selecttable}->{nmset}}) ? 2 : 1 : 0;
         $self->printMultipleSelectTable($choosetable, \@minus, "delete", $targetself->{tablename}.$TSEP.$UNIQIDCOLUMNNAME, $db->{tables}->{$targetself->{tablename}}->{boolcolumn}, $targetself->{tablename}, undef, ($isall == 2 ? 1 : 0) );
         print "</td><td>";
         print $self->HashButton( {
            sessionid => $targetself->{sessionid},
            job       => $self->{"q"}->param("job"),
            table     => $choosetable,
            filterid  => $filterid,
            sortby    => $self->{"q"}->param("sortby")||'',
            stable    => $selecttable,
         }, "<->", { noform => 1 } );
         print "<br>";
         unless (($db->{tables}->{$targetself->{tablename}}->{boolcolumn}) && ($db->{tables}->{$targetself->{tablename}}->{boolsingle})) {
            print "</td><td>";
            $self->printMultipleSelectTable($choosetable, \@plus, "add", $choosetable.$TSEP.$UNIQIDCOLUMNNAME, $db->{tables}->{$targetself->{tablename}}->{boolcolumn}, undef, undef, ($isall == 1 ? 1 : 0));
        }
        if ($db->{tables}->{$targetself->{tablename}}->{boolcolumn}) {
           print "</td><td valign='top'>";
           $self->printMultipleSelectTable($choosetable, \@plus, "addsec", $choosetable.$TSEP.$UNIQIDCOLUMNNAME, 1);
        }
        print "</td></tr></table>";
        print "</form>";
        print "<br>";
      #}
      print "<table><tr>";
      $self->Table_Footer($choosetable, $targetself);
      print "</tr></table>";
   }
   return $DONE;
};


sub replacer {
   my $self = shift;
   my $toreplace = shift;
   my $curset = shift;
   foreach my $column (keys(%$curset)) {
      next unless defined($curset->{$column});
      #print "REPLACING ".$column." -> ".$curset->{$column}."\n";
      $toreplace =~ s,\%${column}\%,$curset->{$column},g;
   }
   my $curtime = time();
   $curtime = ((localtime($curtime))[3]).".".(((localtime($curtime))[4])+1).".".(((localtime($curtime))[4])+1900);   
   $toreplace =~ s/%time%/$curtime/g;
   return $toreplace;
}

sub Table_Footer {
   my $self = shift;
   my $table = shift;
   my $targetself = shift;
   
   $self->printTableButtons($targetself, "show");
   return;
}

sub Post_Column_Handler {
   my $self = shift;
   return;
}

sub Post_Column_Description {
   my $self = shift;
   my $curtabledef = shift;
   my $curcolumn = shift;
   my $table = shift;
   my $label = shift;
   my $targetself = shift;
   my $mycolumn = shift;
   my $newformat = shift;
   return;
}

sub printMultipleSelectTable {
   my $self = shift;
   my $table = shift;
   my $cache = shift;
   my $name = shift;
   my $idcolumn = shift;
   my $boolcolumn = shift;
   my $tablename = shift;
   my $boolsingle = shift;
   my $allcolumn = shift;
   my $last = '';
   my $lastline = undef;
   print '<select name="'.$name.'"';
   print ' size="6" multiple="multiple"' unless ($boolsingle);
   print '>';
   print '<option value="___ALL___">'.(($tablename && $boolcolumn)?"[".$self->{text}->{ACTIVE_OPERATOR}."] ":'').$self->{text}->{WHITELIST}.'</option>' if $allcolumn;
   my $db = $self->getDBBackend($table);
   grep {
      if (exists($db->{tables}->{$table}->{groupselectcolumn})) {
         my $tmp = '';
         my $found = 0;
         foreach my $curtable (keys %{$db->{tables}}) {
            if ($curtable.$TSEP.$UNIQIDCOLUMNNAME eq $db->{tables}->{$table}->{groupselectcolumn}) {
               $tmp = $self->getValuesForColumn($db->{tables}->{$table}->{groupselectcolumn}, $table, $_ );
               $found++;
            }
         }
         $tmp = $_->{$table.$TSEP.$db->{tables}->{$table}->{groupselectcolumn}} unless $found;
         print '<option value="">[&nbsp;'.$tmp.'&nbsp;]</option>'
            unless ($lastline && ($lastline->{$table.$TSEP.$db->{tables}->{$table}->{groupselectcolumn}} eq
                                    $_->{$table.$TSEP.$db->{tables}->{$table}->{groupselectcolumn}}));
      }
      my $tmp = '<option value="'.$_->{$idcolumn}.'">';
      my $tmp2 = '';
      #$tmp2 .= join(",",keys(%$cache)); 
      if ($tablename && $boolcolumn) {
         $tmp2 .= $_->{$tablename.$TSEP.$boolcolumn} #||$_->{$boolcolumn}
          ? "[".$self->{text}->{ACTIVE_OPERATOR}."] " : "[".$self->{text}->{INACTIVE_OPERATOR}."] "
      }
      $tmp2 .= $self->getLineForTable($table, $_, 1);
      $tmp2 = substr($tmp2, 0, 60)."..." if (length($tmp2) > 9999);
      $tmp .= $tmp2;
      $tmp .= '</option>';
      $tmp .= "<br><br>\n";
      print $tmp if ($last ne $tmp);
      $last = $tmp;
      $lastline = $_;
   } @$cache;
   unless (scalar(@$cache) || ($allcolumn)) {
      print '<option value="">* empty *</option>';
   }
   print '</select>';
}

sub getEntryWithID {
   my $cache = shift;
   my $table = shift;
   my $filterid = shift;

   foreach (@{$cache->{$table}}) {
      if ($filterid eq $_->{$table.$TSEP.$UNIQIDCOLUMNNAME}) {
         return $_;
      }
   }
   return undef;
}

sub getLineForTable {
   my $self = shift;
   my $table = shift;
   my $line = shift;
   my $small = shift;

   my $curtabledef = $self->getTableDefiniton($table);
   my $db = $self->getDBBackend($table);
   my $curcolumndef = [hashKeysRightOrder($curtabledef->{columns})];
   return $self->getValuesForColumn($table."_".$UNIQIDCOLUMNNAME, $table, $line ) if ($small);
   return join(", ", map {
      my $tmp = "_".$UNIQIDCOLUMNNAME;
      my $a = ($_ =~ /^(.*)$tmp$/) && (exists($db->{tables}->{$1}));
      ($a?"[ ":"").$self->getValuesForColumn( $_, $table, $line).($a?" ]":"")
   } grep {
       my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$_});
       (!(($curcolumn->{hidden}) || ($curcolumn->{writeonly})))
   } @$curcolumndef);
}

sub giveMeLink {
   my $self = shift;
   my $label = shift;
   my $sortby = shift;
   my $choosetable = shift;
   my $selecttable = shift;
   my $sessionid = shift;
   my $job = shift;
   my $filterid = shift;
   return "<a class=\"dia\" href=\"".$self->{"q"}->url(-relative=>1)."?sessionid=".$sessionid.
   "&job=".$job."&table=".$choosetable."&stable=".$selecttable."&filterid=".$filterid."&sortby=".$sortby."\"><b>".$label."</b></a>"
}

sub sendFilterColumns {
   my $self = shift;
   my $targetself = shift;
   my $table = shift;
   my $curtabledef = $self->getTableDefiniton($table);
   my $db = $self->getDBBackend($table);

   foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
      my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$column});
      next if $curcolumn->{secret};
      $self->sendLine($table.$TSEP.$column."_selected: ".$self->{"q"}->param($column."_selected")) if ($self->{"q"}->param($column."_selected") ne "");
      if (($curcolumn->{type} eq "date")||
          # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
          ($curcolumn->{type} eq "datetime")) {
         my $values = $self->parseDateDefintion($column, $self->{q});
         if (defined($values->[2]) && $values->[2]) {
            $self->sendLine($table.$TSEP.$column."_begin: " .$values->[0]) if (defined($values->[0]) && $values->[0]);
            $self->sendLine($table.$TSEP.$column."_end: "   .$values->[1]) if (defined($values->[1]) && $values->[1]);
            $self->sendLine($table.$TSEP.$column."_active: ".$values->[2]) if (defined($values->[2]));
         }
      } else {
         $self->sendLine($table.$TSEP.$column.": ".$self->{"q"}->param("search".$column)) if ($self->{"q"}->param("search".$column) ne "");
      }
   }
}

sub parseDateDefintion {
   my $self = shift;
   my $column = shift;
   my $q = shift;
   my $begin = '';
   my $end = '';
   my $beginok = 0;
   my $endok = 0;
   my $i = 0;
   foreach (@{$self->{datedef}}) {
      my $tmp = $q->param("search".$column."_begin_".$_->[0]) || "";
      $tmp = ($_->[6] || $_->[3]) unless ($tmp || ($tmp eq '0'));
      $tmp = "0".$tmp if (length($tmp) == 1);
      $tmp .= ($_->[5]);

      my $tmp2 = $q->param("search".$column."_end_".$_->[0]) || "";
      $tmp2 = ($_->[6] || $_->[3]) unless ($tmp2 || ($tmp2 eq '0'));
      $tmp2 = "0".$tmp2 if (length($tmp2) == 1);
      $tmp2 .= ($_->[5]);

      if ($i > 2) {
         $begin .= $tmp;
         $end .= $tmp2;
      } else {
         $begin = $tmp.$begin;
         $end = $tmp2.$end;
      }
      $beginok++ if $q->param("search".$column."_begin_".$_->[0]);
      $endok++ if $q->param("search".$column."_end_".$_->[0]);
      $i++;
   }
   return [$beginok ? $begin : undef,
           $endok ? $end : undef,
           $q->param("search".$column."_active") ? 1 : 0];
}

sub getStringForDate {
   my $self = shift;
   my $column = shift;
   $_ = shift;
   my $i = 0;
   my $result = '';
   return $self->{"q"}->param($column) if $self->{"q"}->param($column);
   foreach (@{$self->{datedef}}) {
      my $tmp = ($self->{"q"}->param($column.$_->[0]) || $_->[6] || $_->[2]).($_->[5]);
      if ($i > 2) {
         $result .= $tmp;
      } else {
         $result = $tmp.$result;
      }
      $i++;
   }
   #print "CONVERTED:".$result."\n";
   return $result;
}

sub run {
   my $self = shift;
   $self->{noStyle} = 0;

   my $targetself = $self->getHandler($self->{job}, 1);

   $targetself->{state} = $NOSTATE;

   if ($targetself->{noStyle}) {
      $self->{noStyle}++;
   } else {
      print $self->{"q"}->header();
      print $self->{header};
   }

   unless ($targetself->{handler}) {
      print "Unknown Job :".$self->{job}.":.\n";
      $self->destructor();
   }

   my $stat = $targetself->{handler}($self, $targetself, {}, $STARTUP);

   if ($stat && ($stat == $DONE)) {
      while (1) {
         if ($targetself = $self->getHandler($self->{job}, 1)) {
            $stat = $targetself->{handler}($self, $targetself, {}, $STARTUP);
            last if ($stat != $DONE);
         } else {
            $self->destructor();
         }
      }
   }

   unless ($self->{fd} = IO::Socket::INET->new(
      PeerAddr => $self->{config}->{dbmanagerip},
      PeerPort => $self->{config}->{dbmanagerport},
      Proto    => 'tcp')) {
      print "Error connecting to :".$self->{config}->{dbmanagerip}.":".$self->{config}->{dbmanagerport}.":!\n";
      $self->destructor();
   }

   # Connect-Event uebergeben wir direkt.
   $stat = $targetself->{handler}($self, $targetself, {}, $CONNECTED);

   if ($stat && ($stat == $DONE)) {
      while (1) {
         if ($targetself = $self->getHandler($self->{job}, 1)) {
            $stat = $targetself->{handler}($self, $targetself, {}, $STARTUP);
            next if ($stat == $DONE);
            $stat = $targetself->{handler}($self, $targetself, {}, $CONNECTED);
            last if ($stat != $DONE);
         } else {
            $self->destructor();
         }
      }
   }

   while (1) {

      $self->ProcessServer($targetself, $self->{config}->{timeout})
         or Log("Error runnig ProcessServer !", $ERROR);

      my $next = undef;
      while (1) {
         $next = $self->getHandler($self->{job}, 1);
         last unless ($targetself->{handler} = $next->{handler});
         last unless (ref($targetself->{handler}) eq "CODE");
         $targetself->{state} = $NOSTATE;
         my $ret = $targetself->{handler}($self, $targetself, {});
         #print "RETURN:".$ret.":\n";
         last if ((!defined($ret)) || (($ret ne $DONE) && ($ret ne $OK)));
      }
      last unless (ref($targetself->{handler}) eq "CODE");
   }

   Log("Program finished clean.", $DEBUG);
   $self->destructor();
}

sub destructor {
   my $self = shift;
   my $handler = $self->getHandler($self->{job});

   unless ($self->{noStyle}) {
      print "</div></div></div>\n";
      print "<a href='http://www.adbgui.org/' target='_blank'>".$self->{text}->{FOOT_NOTE}."</a>\n";
      print "</body>\n</html>";
   }
   exit(0);
}

sub showTable {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   my $stadium = shift || 0;
   my $dstjob = shift;
   my $hideactions = shift || 0;
   my $tablesk = 0;
   $_ = $line->{data};

   if ($targetself->{table} && $self->{"q"}->param("table") && ($self->{"q"}->param("table") eq $targetself->{table})) {
      $tablesk = $self->{tableskip};
   }

   if (/^GET (\S+) (\S+)(\s(\S+))?(\s(\S+))?(\s*[.*])?$/) {
      my $table = $1;
      my $action = $2;
      my $lines = $4;
      my $filtered = $6;
      $targetself->{filtered} = $filtered ? 1 : 0;
      my $error = '';
      $error .= $5 if $5;
      $error .= $7 if $7;
      unless ($table eq $targetself->{table}) {
         Log("Got Info for ".$table." but I am looking for ".$targetself->{table}, $ERROR);
         return $DONE ;
      }
      my $db = $self->getDBBackend($targetself->{table});
      if (($action eq "NEXT") || ($action eq "END") && defined($targetself->{tmpcolumn}) && (scalar(keys(%{$targetself->{tmpcolumn}})))) {
         my $curtabledef = $self->getTableDefiniton($targetself->{table});
         my $curcolumndef = [hashKeysRightOrder($curtabledef->{columns})];
         unless ($targetself->{count}) {
            #my $ctmp = custom_Column_Description($curtabledef, undef, $table, undef, $targetself, undef, $hidebuttons);
            #print $ctmp if $ctmp;
            print "<TH valign='top'";
            print " colspan='2'" unless ($targetself->{hidebuttons});
            print "></TH>";
            foreach (@$curcolumndef) {
               my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$_});
               my $label = $curcolumn->{label} || $_;
               next if ($curcolumn->{hidden} || $curcolumn->{writeonly});
               if (defined($curtabledef->{columns}->{$_})) {
                  #ToDo: Ist ans Ende gewandert... brauchten wir das evtl. hier vorne?!
                  #next if (custom_Column_Description($curtabledef, $curcolumn, $table, $label, $targetself, $_, $hidebuttons));
                  if (exists($targetself->{tmpcolumn}->{$table.$TSEP.$_})) {
                     print "<TH valign=\"top\">";
                     print $self->makeColumn($_, $label, $curcolumn, $targetself, $table, $self->{config}->{NOHEADERLINE}, undef, undef);
                     print "</TH>\n"
                  }
                  my $ctmp = $self->Post_Column_Description($curtabledef, $curcolumn, $table, $label, $targetself, $_, 1);
                  print $ctmp if $ctmp;
               }
            }
            print "</TR><TR>";
         }
         $targetself->{count}++;
         print "<TD align=\"center\" valign='top'>&nbsp;".((++$targetself->{row_nr}) + ($targetself->{hidebuttons}?0:$tablesk))."&nbsp;</TD>"; # unless ($targetself->{hidebuttons});
         if ((!$targetself->{hidebuttons}) || $self->{config}->{debug}) {
            print "<TD valign='top'>";
            if ((!$targetself->{last}) || ($targetself->{last} ne $targetself->{tmpcolumn}->{$targetself->{table}.$TSEP.$UNIQIDCOLUMNNAME})) {
               print "<TABLE border='0'><TR>";
               print $self->Buttons($targetself, $dstjob, $targetself->{table}, $targetself->{tmpcolumn});
               print "</TR></TABLE>";
            }
            print "</TD>\n";
         }
         print $self->Post_Column_Handler($targetself, $table, $targetself->{tmpcolumn}, undef);
         foreach (@$curcolumndef) {
            if (exists($curtabledef->{columns}->{$_}) && (exists($targetself->{tmpcolumn}->{$table.$TSEP.$_}))) {
               my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$_});
               unless (($curcolumn->{hidden}) || ($curcolumn->{writeonly})) {
                  print "<TD valign='center'>";
                  print "<nobr>" if (($curcolumn->{nobr}) && (!$targetself->{hidebuttons}));
                  print $self->Column_Handler($targetself, $table, $targetself->{tmpcolumn}, $_);
                  print "</nobr>" if (($curcolumn->{nobr}) && (!$targetself->{hidebuttons}));
                  print "</TD>\n";
               }
            }
            print $self->Post_Column_Handler($targetself, $table, $targetself->{tmpcolumn}, $_);
         };
         $targetself->{last} = $targetself->{tmpcolumn}->{$targetself->{table}.$TSEP.$UNIQIDCOLUMNNAME};
         $targetself->{tmpcolumn} = {};
      }
      if ($action eq "BEGIN") {
         $targetself->{tmpcolumn} = {};
         $targetself->{count} = 0;
         $targetself->{row_nr} = 0;

         if (($targetself->{filtered}) && (!$targetself->{hidebuttons})) {
            print "<em>!!! ".$self->{text}->{FILTER_ACTIVE}." ";
            print $self->HashButton( {
               sessionid => $targetself->{sessionid},
               job => 'setfilter',
               table => $self->{"q"}->param("table")||'',
               sortby => $self->{"q"}->param("sortby")||'',
               stable => $self->{"q"}->param("stable")||''
            }, $self->{text}->{FILTER_RESET}, { link => 1 } );
            print "</em><br><br>\n";
         }

         print "<b>".$self->{text}->{FOUND_ENTRIES}.":</b> ".$lines if $lines;
         print "<table border=1 cellpadding=0 cellspacing=0><tr>\n";

      } elsif ($action eq "NEXT") {
        $targetself->{count}++;
        print "</TR><TR>";
      } elsif ($action eq "END") {
         print "<td> $self->{text}->{NO_ENTRIES} \n</td>" unless $targetself->{count};
         print "</tr></table>\n";
         $targetself->{count} = undef;
         print "<table border='0' cellspacing='0' cellpadding='0'><tr>\n";
         unless ($targetself->{hidebuttons}) {
            print "<td>\n";
            #printButton($targetself->{table}, "addpre", $targetself->{sessionid}, $self->{text}->{B_ADD}, undef, undef, undef, undef, $dstjob)
            print $self->Buttons($targetself, $dstjob, $targetself->{table}, $targetself->{tmpcolumn}, 1);
            #print $self->HashButton( {
            #   sessionid => $targetself->{sessionid},
            #   job => 'addpre',
            #   table => $targetself->{table}||''
            #}, $self->{text}->{B_ADD}, { link => 1 }) if (((!$tmpb) && (!$db->{tables}->{$targetself->{table}}->{readonly}) && (!$db->{tables}->{$targetself->{table}}->{editonly})) || $self->{config}->{debug});
         }
         unless ($targetself->{hidebuttons}) {
            # BEGIN: Seite: [1] 2 [3] .. [99]
            if ($lines && $self->{tablelines} && ($lines > $self->{tablelines})) {
               # BEGIN: Seite: <<
               print "</td><td>&nbsp;".$self->{text}->{SITE}.":&nbsp;";
               unless (($tablesk-$self->{tablelines}) < 0) {
                  print "</td><td>";
                  #printButton($targetself->{table}, "show", $targetself->{sessionid}, "<", undef, ($tablesk-$self->{tablelines}), undef, undef, $dstjob );
                  print $self->HashButton( {
                     sessionid => $targetself->{sessionid},
                     job => 'show',
                     table => $targetself->{table}||'',
                     sortby => $self->{"q"}->param("sortby")||'',
                     tableskip => ($tablesk-$self->{tablelines})
                  }, "<", { link => 1 });
               }
               # END: Seite: <<
               my $buttonalt = 0;
               for (my $i=0; $i<=int(($lines-1)/$self->{tablelines}); $i++) {
                  if ($i == int($tablesk/$self->{tablelines})) {
                     print "</td><td>";
                     print "&nbsp;".($i+1)."&nbsp;";             
                  } elsif (($i == 0) || ($i == int(($lines-1)/$self->{tablelines}))) {
                     print "</td><td>";
                     #printButton($targetself->{table}, "show", $targetself->{sessionid}, ($i+1), undef, ($i*$self->{tablelines}), undef, undef, $dstjob);
                     print $self->HashButton( {
                        sessionid => $targetself->{sessionid},
                        job => 'show',
                        table => $targetself->{table}||'',
                        sortby => $self->{"q"}->param("sortby")||'',
                        tableskip => ($i*$self->{tablelines})
                     }, ($i+1), { link => 1 });
                  } else {
                     if (($i >= (int($tablesk/$self->{tablelines})-1)) && ($i <= (int($tablesk/$self->{tablelines})+1))) {
                       $buttonalt = 0;
                        print "</td><td>";
                        #printButton($targetself->{table}, "show", $targetself->{sessionid}, ($i+1), undef, ($i*$self->{tablelines}), undef, undef, $dstjob );
                        print $self->HashButton( {
                           sessionid => $targetself->{sessionid},
                           job => 'show',
                           sortby => $self->{"q"}->param("sortby")||'',
                           table => $targetself->{table}||'',
                           tableskip => ($i*$self->{tablelines})
                        }, ($i+1), { link => 1 });
                     } else {
                        unless ($buttonalt) {
                           print "</td><td>";
                           $buttonalt = 1;
                           print "..";
                       }
                     }
                  }
               }
               # BEGIN: Seite: >>
               unless (($tablesk+$self->{tablelines}) >= $lines) {
                  print "</td><td>";
                  #printButton($targetself->{table}, "show", $targetself->{sessionid}, ">", undef, ($tablesk+$self->{tablelines}), undef, undef, $dstjob);
                  print $self->HashButton( {
                     sessionid => $targetself->{sessionid},
                     job => 'show',
                     table => $targetself->{table},
                     sortby => $self->{"q"}->param("sortby")||'',
                     tableskip => ($tablesk+$self->{tablelines})
                  }, ">", { link => 1 });
               }
               # END: Seite: >>
            }
            # END: Seite: [1] 2 [3] .. [99]
         }
         #print "</td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>";
         #unless ($targetself->{hidebuttons} || $hideactions) {
         #   print "<form method='post'>\n";
         #   print "<input type='text' name='tablelines' value='".($self->{"q"}->param("tablelines")||'')."'>";
         #   #print $self->HashButton( {
         #   #   sessionid => $targetself->{sessionid},
         #   #   job => 'show',
         #   #   table => $targetself->{table},
         #   #   sortby => $self->{"q"}->param("sortby")||''
         #   #}, "Anzahl der Zeilen &auml;ndern", { noform => 1 });
         #   print "</form>";
         #} 
         print "</td></tr></table><br>\n";
         unless ($targetself->{hidebuttons} || $hideactions) {
            print "<table border='0'><tr>";
            $self->Table_Footer($table, $targetself);
            print "</tr></table>";
         }    
         $targetself->{tmpcolumn} = undef;
         return $ACTIONOK;
      } elsif ($action eq "FAILED") {
         print "<font color='#FF0000'><b>ERROR:</b> ".$error."</font>\n";
         return $DONE;
      } else {
         print "PROTOKOLL ERROR 6.<br>\n";
         return $PROTOKOLLERROR;
      }
      return $RUNNING;
   } elsif (/^([^:]+):\s(.*)$/) {
      my $key = $1;
      my $value = $2;
      $value =~ s/##/#/g;
      $value =~ s/#13/<br>\n/g;
      $value =~ s/#10/\r/g;
      my $found = 0;
      my $db = $self->getDBBackend($targetself->{table});
      my $tabledef = $db->{tables}->{$targetself->{table}}->{columns};
      my $mycolumn = [grep { $targetself->{table}."_".$_ eq $key } keys %$tabledef];
      if (scalar(@$mycolumn)) {
         if ($tabledef->{$mycolumn->[0]}->{type} eq "boolean") {
            $value = $value ? "<center>X</center>" : "";
         } elsif (($tabledef->{$mycolumn->[0]}->{type} eq "date")||
                  # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
                  ($tabledef->{$mycolumn->[0]}->{type} eq "datetime")) {
            $value = gmtime($value) if ($value && ($value =~ /^\d+$/));
         }
      }
      $targetself->{tmpcolumn}->{$key} = $value;
      return $RUNNING;
   } else {
      print "PROTOKOLL ERROR 7.<br>\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub Buttons {
   my $self = shift;
   my $targetself = shift;
   my $dstjob = shift;
   my $table = shift;
   my $row = shift;
   my $addbutton = shift || 0;
   my $ret = '';

   my $tabledef = $self->getTableDefiniton($targetself->{table});
   if ($addbutton) {
      $ret .= $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => 'addpre',
         table => $targetself->{table}||''
      }, ($self->{text}->{I_ADD} ? '<img align="middle" src="'.$self->{text}->{I_ADD}.'">' : '').$self->{text}->{B_ADD}, { link => 1 })
         if ($self->{self}->{debug} || ((($targetself->{rights} & $MODIFY) || 
              ($targetself->{rights} & $ADMIN)) &&
              (!$tabledef->{readonly}) &&
              (!$tabledef->{editonly})));
      $ret .= " " if $ret;
      $ret .= $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => 'search',
         table => $targetself->{table}||''
      }, $self->{text}->{T_SEARCH}, { link => 1 });
   } else {
      if ($row->{$targetself->{table}.$TSEP.$DELETEDCOLUMNNAME}) {
         if ((!$tabledef->{readonly}) &&
             (!$tabledef->{editonly})) {
            $ret .= "<TD valign='top'>";
            $ret .= $self->HashButton( {
               sessionid => $targetself->{sessionid},
               job => $self->{config}->{noaskbeforeundelete} ? "undelpost" : "undelpre",
               table => $targetself->{table},
               $UNIQIDCOLUMNNAME => $row->{$targetself->{table}.$TSEP.$UNIQIDCOLUMNNAME}||''
            }, $self->{text}->{B_UNDEL}, { link => 1 });
            $ret .= "</TD>";
         }
      } else {
         if (!$tabledef->{readonly}) {
            if (!$tabledef->{editonly}) {
               $ret .= "<TD valign='top'>";
               $ret .= $self->HashButton( {
                  sessionid => $targetself->{sessionid},
                  job => $self->{config}->{noaskbeforedelete} ? "delpost" : "delpre",
                  table => $targetself->{table},
                  $UNIQIDCOLUMNNAME => $row->{$targetself->{table}.$TSEP.$UNIQIDCOLUMNNAME}||''
               }, $self->{text}->{B_DEL}, { link => 1 });
               $ret .= "</TD>";
            }         
            $ret .= "<TD valign='top'>";
            $ret .= $self->HashButton( {
               sessionid => $targetself->{sessionid},
               job => "updatepre",
               table => $targetself->{table},
               $UNIQIDCOLUMNNAME => $row->{$targetself->{table}.$TSEP.$UNIQIDCOLUMNNAME}||''
            }, $self->{text}->{B_EDIT}, { link => 1 });
            $ret .= "</TD>";
         }
      }
   }
   return $ret;
}

sub Column_Handler {
   my $self = shift;
   my $targetself = shift;
   my $table = shift;
   my $row = shift;
   my $curcolumn = shift;
   my $ret = '';
   
   my $columnvalue = $self->getValuesForColumn($curcolumn, $table, $row);
   my $db = $self->getDBBackend($table);
   if (($table eq $LOG) && ($curcolumn eq $TABLE)) {
      my $tmp = $db->{tables}->{$columnvalue}->{label} if exists($db->{tables}->{$columnvalue});
      $tmp = $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => "setfilter",
         table => $columnvalue||''
      }, $tmp, { link => 1 } ) unless $targetself->{hidebuttons};
      $ret .= $tmp;
      return $ret;
   }
   if ((!$targetself->{last}) || ($targetself->{last} ne $row->{$table.$TSEP.$UNIQIDCOLUMNNAME})) {
      #print "A:".$_.":".join(",", keys %{$targetself->{tmpcolumn}}).":<br>\n";
      my $tmp = $self->getValuesForColumn($curcolumn, $table, $row, ((exists($targetself->{model})) && ($targetself->{model} eq "qooxdoo")) ? '' : '&nbsp;') || '';
      $table =~ /^([^_]+)_([^_]+)$/;
      my $tableOne = $1;
      my $tableTwo = $2;
      # TODO:FIXME:XXX: Das beist sich mit Qooxdoo... Darum einfach auskommentiert... Muss wieder geradegezogen werden!
      #if ((!$targetself->{hidebuttons}) && ($tableOne) && (exists($db->{tables}->{$tableOne})) && (exists($db->{tables}->{$tableTwo})) && (((/$tableOne/) && (!$db->{tables}->{$table}->{boolsingle})) || (/$tableTwo/))) {
      #   $ret .= $self->HashButton( {
      #      sessionid => $targetself->{sessionid},
      #      job => $self->{"q"}->param("job")||'',
      #      table => (/$tableOne/) ? $tableTwo : $tableOne,
      #      filterid => $row->{$table.$TSEP.$_}||'',
      #      sortby => $self->{"q"}->param("sortby")||'',
      #      stable => (/$tableOne/) ? $tableOne : $tableTwo,
      #   }, $tmp, { link => 1 } );
      #} else {
         $ret .= $tmp;
      #}
   }
   return $ret;
}

sub makeColumn {
   my $self = shift;
   my $column = shift;
   my $label = shift;
   my $curcolumn = shift;
   my $targetself = shift;
   my $table = shift;
   my $noHeadLine = shift || 0;
   my $pre = shift;
   my $subline = shift;
   my $ret = '';

   my $db = $self->getDBBackend($table);
   my $tmp = "_".$UNIQIDCOLUMNNAME;
   if (($column =~ /^(.*)$tmp$/) && (defined($db->{tables}->{$1}))) { # &&
       #($targetself->{tmpcolumn}->{$1."_".$UNIQIDCOLUMNNAME})) {
      unless ($noHeadLine) {
         $ret .= "<A title='".$curcolumn->{description}."'>" if $curcolumn->{description};
         $ret .= "<B>";
         $ret .= $label;
         $ret .= "</B>";
         $ret .= "</A>" if $curcolumn->{description};
         $ret .= "<br>";
      }
      my $curtable = $1;
      $ret .= "<nobr>".join(" | </nobr><nobr>", map {
         my $curcolumn = mergeColumnInfos($db, $db->{tables}->{$curtable}->{columns}->{$_});
         my $value = $curcolumn->{label}||$_;
         my $curcol = ($pre||$curtable).$TSEP.( $curcolumn->{dbtype} ? $_ : $curcolumn->{useForSort} ? $curcolumn->{useForSort} : $UNIQIDCOLUMNNAME);
         $curcol .= "_" if ($self->{"q"}->param("sortby") && ($self->{"q"}->param("sortby") eq $curcol));
         $targetself->{hidebuttons} ? $value : $self->HashButton( {
             sessionid => $targetself->{sessionid},
             job => 'show',
             table => $targetself->{table},
             sortby => $curcol },
         $value, { link => 1 });
      } @{getAffectedColumns($db, $db->{tables}->{$curtable}->{columns}, 1, undef, undef, 1)})."</nobr>";
      $ret .= "<br>";
   } else {
      my $curcolumn = mergeColumnInfos($db, $db->{tables}->{$targetself->{table}}->{columns}->{$column});
      $ret .= "<span class=\"dia\">" if $subline;
      my $curcol = $targetself->{table}.$TSEP.( $curcolumn->{dbtype} ? $column : $curcolumn->{useForSort} ? $curcolumn->{useForSort} : $UNIQIDCOLUMNNAME);
      #print "XXX:".ref($self).":\n";
      $curcol .= "_" if (defined($self->{"q"}->param("sortby")) && defined($curcol) && ($self->{"q"}->param("sortby") eq $curcol));
      $label = "<b>".$label."</b>" unless $subline;
      unless ($targetself->{hidebuttons}) {
         $ret .= "<a ";
         $ret .= "title='".$curcolumn->{description}."' " if $curcolumn->{description};
         $ret .= "href=\"".$self->{"q"}->url(-relative=>1).
            "?sessionid=".$targetself->{sessionid}.
            "&job=show&table=".$targetself->{table}.
            "&sortby=".$curcol."\">";
      }
      $ret .= $targetself->{hidebuttons} ? $label : $self->HashButton( {
            sessionid => $targetself->{sessionid},
            job => 'show',
            table => $targetself->{table},
            sortby => $curcol },
         $label, { link => 1 });
      $ret .= "</span>" if $subline;
   }
   my @tmp = getInfoLineForColumn($targetself->{curInfo}, $curcolumn, $column);
   $ret .= "<br><span class=\"dia\">".join(" - <br>\n", map { ($_->{label}?$_->{label}.": ":'').$_->{value} } @tmp)."</span>" if scalar(@tmp);
   if ( $curcolumn->{graph} ) {
      $ret .= "<br>" unless ($subline);
      $ret .= $self->printGraphLink($targetself->{sessionid}, $table, $column, undef, $targetself->{hidebuttons});
   }
   return $ret;
}

sub getInfoLineForColumn {
   my $tableInfo = shift;
   my $curcolumn = shift;
   my $column = shift;
   my @tmp = ();
   if (ref($tableInfo) eq "HASH") {
      foreach my $info (keys %$tableInfo) {
         #print ":XXXII:".$info.":".$curcolumn->{info}.":".$curcolumn->{description}.":<br>\n";
         next unless ($curcolumn->{info} && (grep { $info =~ /$_/i; } split (/,|\s/, $curcolumn->{info})));
         if ($info =~ /^(.+)\_$column$/i) {
            my $value = $tableInfo->{$info};
       my $name = undef;
       my $label = $1;
       if (lc($1) eq "sum") {
               $label = "Summe";
            }
            if ($curcolumn->{type} eq "datavolume") {
               $value = (int($tableInfo->{$info}/1024/102.4)/10)." MB"
            } elsif (($curcolumn->{type} eq "date")|
                     # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
                     ($curcolumn->{type} eq "datetime")) {
               if (lc($1) eq "min") {
                  $label = "";
               } elsif (lc($1) eq "max") {
                  $label = "";
               }
            }
            push(@tmp, {name => $1, label => $label, value => $value} ) if $value;
         }
      }
   }
   return @tmp;
}

sub printGraphLink {
   my $self = shift;
   my $sessionid = shift;
   my $table = shift;
   my $column = shift;
   my $label = shift || $self->{text}->{GRAPH};
   my $hidebuttons = shift;
   return "<span class=\"dia\"> (<a class=\"dia\" href=\"".
         $self->getGraphURL($sessionid, $table, $column, undef, 1).
         "\">".$label."</a>)</span>" unless $hidebuttons;
}

sub getGraphURL {
   my $self = shift;
   my $sessionid = shift;
   my $table = shift;
   my $column = shift;
   my $calwndown = shift;
   my $html = shift;
   return $self->{"q"}->url(-relative=>1).
          "?sessionid=".$sessionid.
          "&job=".($html?'headline':'')."getstatimg&table=".$table.
          "&column=".$column.
          "&calwndown=".$calwndown.
          "&width=660&height=390";
}

sub getValuesForColumn {
   my $self = shift;
   my $column = shift;
   my $table = shift;
   my $row = shift; 
   my $db = $self->getDBBackend($table);
   # TODO:FIXME:XXX: $pre ist rausgeflogen, unn�tig. �berall gerade ziehen!!!
   # my $pre = shift;
   my $emptyfiller = shift || '';
   my $tmpx = "_".$UNIQIDCOLUMNNAME;
   my $return = $emptyfiller;
   my $curtable = undef;
   my $prefix = "";
   if (($db->{tables}->{$table}->{columns}->{$column}) && 
       ($db->{tables}->{$table}->{columns}->{$column}->{linkto})) {
      $curtable = $db->{tables}->{$table}->{columns}->{$column}->{linkto};
   } elsif ($self->{config}->{oldlinklogic} && ($column =~ /^(.*)$tmpx$/) && (exists($db->{tables}->{$1}))) {
      $curtable = $1;
   }
   if ($curtable) {
      my $found = 0;
      my $tmp = join($COLUMNCONJUNCTION, grep { $found++ if $_; $_ } map {
         my $curcolumn2 = $_;
         my $curtable2 = undef;
         if (($db->{tables}->{$curtable}->{columns}->{$curcolumn2}) && 
             ($db->{tables}->{$curtable}->{columns}->{$curcolumn2}->{linkto})) {
            $curtable2 = $db->{tables}->{$curtable}->{columns}->{$curcolumn2}->{linkto};
         } elsif ($self->{config}->{oldlinklogic} && ($curcolumn2 =~ /^(.*)$tmpx$/) && (exists($db->{tables}->{$1}))) {
            $curtable2 = $1;
         }
         if ($curtable2) {
            join(",", map { $self->getValueRightFormat($curtable2, $_, $row->{$curcolumn2."_".$curtable2.$TSEP.$_}) || '' } @{getAffectedColumns($db, $db->{tables}->{$curtable2}->{columns}, 1)})
         } else {
            #$table.":".$curtable.":".$curcolumn2.":".#join(",", keys %$row).":".
            $self->getValueRightFormat($curtable, $curcolumn2, $row->{$column."_".$curtable.$TSEP.$curcolumn2})
         }
      } @{getAffectedColumns($db, $db->{tables}->{$curtable}->{columns}, 1, undef, undef, 1)});
      if ($found) {
         $return = $tmp;
      } else {
         if ($db->{tables}->{$curtable}->{crossShowInSelect}) {
            $tmp = $self->getValueRightFormat($table, $column, $row->{$curtable.$TSEP.$db->{tables}->{$curtable}->{crossShowInSelect}});
            $return = $row->{$table.$TSEP.$column};
            $return .= " (".$tmp.")" if $tmp;
         } else {
            $return = $self->getValueRightFormat($table, $column, $row->{$table.$TSEP.$column});
         }
      }
   } else {
      $return = $self->getValueRightFormat($table, $column, $row->{$table.$TSEP.$column})
   }
   my $search = $self->{"q"}->param("searchfield");
   $return =~ s/($search)/\<font color="red"\>$1\<\/font\>/ig if ($search);
   return $return;
}

sub getValueForTable {
   my $self = shift;
   my $table = shift;
   my $dbline = shift;
   my $db = $self->getDBBackend($table);
   return join($COLUMNCONJUNCTION, map { 
      $self->getValueRightFormat($table, $_, $dbline->{$table.$TSEP.$_}) || "-"
   } @{getAffectedColumns($db, $db->{tables}->{$table}->{columns}, 1)})
}

sub getValueRightFormat {
   my $self = shift;
   my $table = shift;
   my $column = shift;
   my $value = shift;
   my $db = $self->getDBBackend($table);
   return $value unless exists($db->{tables}->{$table}->{columns}->{$column});
   my $curcolumndef = mergeColumnInfos($db, $db->{tables}->{$table}->{columns}->{$column});
   if (($curcolumndef->{type} eq "boolean") && ($curcolumndef->{booleanlabel})) {
      return $curcolumndef->{booleanlabel}->[$value || 0] || undef
   } elsif ($curcolumndef->{type} eq "date") {
      if ($value && ($value =~ m,^(\d+)\-(\d+)\-(\d+),)) {
         $value = $3.".".$2.".".$1;
      }
   } else {
      return $value
   }
}

sub setFilter {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   $_ = $line->{data};
   
   if (/^(SETFILTER)\s+(\S+)\s+(\S+)(\s(.*))?$/) {
      my $cmd = $1;
      my $table = $2;
      my $action = $3;
      my $error = $5;
      if ($action eq "OK") {
         #print "<em>!!! ".$self->{text}->{FILTER_ACTIVE}."</em><br>\n";
         return $ACTIONOK;
      } elsif($action eq "FAILED") {
         print "<font color='#FF0000'>ERROR: <b>".$error."</b></font>\n";
      } else {
         print "PROTOKOLL ERROR 210.\n";
         return $PROTOKOLLERROR;
      }
   } else {
      print "PROTOKOLL ERROR 10.\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub setFilterReset {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   $_ = $line->{data};

   if (/^(FILTERRESET)\s+(\S+)(\s(.*))?$/) {
      my $action = $2;
      my $error = $4;
      if ($action eq "OK") {
         #print "<em>!!! ".$self->{text}->{FILTER_ACTIVE}."</em><br>\n";
         return $ACTIONOK;
      } elsif($action eq "FAILED") {
         print "<font color='#FF0000'>ERROR: <b>".$error."</b></font>\n";
      } else {
         print "PROTOKOLL ERROR 210.\n";
         return $PROTOKOLLERROR;
      }
   } else {
      print "PROTOKOLL ERROR 10.\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub printLoginFormular {
   my $self = shift;
   my $job = shift;
   $job = "" unless $job;
   my $tuser = shift;
   my $pass = shift;
   print "<br><FORM method='POST'";
   my $url = $self->{"q"}->url(-relative=>1);
   print ($url ? " action='".$self->{"q"}->url(-relative=>1)."'" : '');
   print ">\n";
   print "<center><table><tr>\n";
   print "<td align=right><b>".$self->{text}->{USERNAME}.":</b></td>\n";
   print "<td align=left>\n";
   print "<input size=10 maxlength=30 name='user'";
   print " value=".$tuser if $tuser;
   print " type='text'>\n";
   print "<input name='job' type='hidden' value='".$job."'>\n" if $job;
   print "</td></tr>\n";
   print "<tr><td align=right><b>".$self->{text}->{PASSWORD}.":</b></td>\n";
   print "<td align=left><input size=10 maxlength=80 name='pass'";
   print " value=".$pass if $pass;
   print " type='password'></td></tr>\n";
   print "<tr><td align=right></td><td align=left><input type='submit' value='Login'></td></tr></table>\n";
   print "</form><br></center>\n";
}

sub HashButton {
   my $self = shift;
   my $hash = shift || {};
   my $label = shift || "GO";
   my $options = shift || {};
   my $ret = '';
   if ($options->{link}) {
      $ret .= "<A HREF='".$self->{"q"}->url(-relative=>1);
      $ret .= "?".join("&", map {
         my $object = $_;
         (ref($hash->{$object}) eq "ARRAY") ?
            join("&", map { $object."=".$_ } @{$hash->{$object}}) :
            $object."=".$hash->{$object}
         } grep {
            $_ && $hash->{$_}
         } keys %$hash) if scalar(keys %$hash);
      $ret .= "'>";
      $ret .= $label;
      $ret .= "</A>";
   } else {
      $ret .= "<FORM method='".($options->{method}||'POST')."' action='".$self->{"q"}->url(-relative=>1)."'>" unless $options->{noform};
      $ret .= "<INPUT type='submit' value='".$label."'>";
      foreach my $object (keys %$hash) {
         foreach my $value (((ref($hash->{$object}) eq "ARRAY")) ? @{$hash->{$object}} : ($hash->{$object})) {
            $ret .= "<INPUT type='hidden' name='".$object."' value='".$hash->{$object}."'>";
         }
      }
      $ret .= "</FORM>" unless ($options->{noform} || $options->{noformclose});
   }
   return $ret;
}

sub printSearchFormFor {
   my $self = shift;
   # Dieses Forumlar uebergibt per "search<coulumn>" fuer die Table "$table"
   # die Suchparameter. Es wird der Job "setfilter" angegeben; dieser Job muss
   # also diese Werte erkennen und ggf. an den DBManager weitergeben.
   my $table = shift;
   my $submitValue = shift;
   my $sessionid = shift;
   my $tableCache = shift;
   my $filterCache = shift;
   #my $targetself = shift;
   my $ret = '';
   $ret .= "<table>";
   my $curtabledef = $self->getTableDefiniton($table);
   my $db = $self->getDBBackend($table);
   my $j = 0;
   my $k = 0;
   for (my $i = 0; $i<=2; $i++) {
      $j =0;
      foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
         my $curcolumn = mergeColumnInfos($db, $curtabledef->{columns}->{$column});
         next if $curcolumn->{secret};
         next if (($curcolumn->{hidden} && ($curcolumn->{type} ne $DELETEDCOLUMNNAME)) && (!$curcolumn->{showInSearch}));
         my $label = $curcolumn->{label} || $column;
         my $curTable = [];
         my $tmp = '';
         $ret .= "<input name='".$column."' value='".$tmp."' type='hidden'>"
            if (($tmp = $self->{"q"}->param($column)) || (defined($tmp) && $tmp ne ''));
         if (($curTable = [grep { (((!$curcolumn->{searchas}) && (($column eq $_."_".$UNIQIDCOLUMNNAME) || (defined($curcolumn->{useas}) && $curcolumn->{useas} && ($curcolumn->{useas} eq $_."_".$UNIQIDCOLUMNNAME)))) || (defined($curcolumn->{useas}) && $curcolumn->{useas} && ($curcolumn->{searchas} eq $_."_".$UNIQIDCOLUMNNAME))) } keys(%{$db->{tables}})]) && scalar(@$curTable) && !(defined($curcolumn->{nopop})) ) {
            next unless ($i == 1);
            $ret .= writeSeperator($k, $self) if ($j++ == 0); $k++;
            $ret .= $self->printLabelHeader($curcolumn, $label, $column, 1, $filterCache->{$table.$TSEP.$column."_selected"});
            if (scalar(@$curTable) != 1) {
               # Dass hier KANN nicht passieren. Niemals. Unm�glich.
               Log("WHAT??? How can I get here :".scalar(@$curTable).": uniq table matches?!", $ERROR);
               die;
            }
            unless (defined($db->{tables}->{$curTable->[0]}) &&
               (ref($db->{tables}->{$curTable->[0]}) eq "HASH")) {
               Log("WHAT??? How can I get here the not existing table:".$curTable->[0].": ?!", $ERROR);
               die;
            }
            $ret .= $self->printSelectBoxFor($tableCache, $table, $column, $curTable->[0], $filterCache, # $curcolumn->{searchas}?$curTable->[0].$TSEP.($curcolumn->{searchcolumn}||$db->{tables}->{$curTable->[0]}->{crossShowInSelect}):'', 
                                                                            1);
            $ret .= "</td></tr>\n";
         } elsif (($curcolumn->{type} eq "boolean") || ($curcolumn->{type} eq $DELETEDCOLUMNNAME)) {
            next unless ($i == 2);
            $ret .= writeSeperator($k, $self) if ($j++ == 0); $k++;
            $ret .= $self->printLabelHeader($curcolumn, $label, $column, 1, $filterCache->{$table.$TSEP.$column."_selected"});
            $ret .= "<select name='search".$column."'>\n";
            my @arry = (["*" => ""], ["ja" => "1"], ["nein" => "0"]);
            foreach my $key (@arry) {
               $ret .= "  <option value='".$key->[1]."'";
               my $tmp = $filterCache->{$table.$TSEP.$column} || '';
               $ret .= " selected" if ($tmp eq $key->[1]);
               $ret .= ">".$key->[0]."</option>\n";
            }
            $ret .= "</select>\n";
            $ret .= "</tr></td>\n";
         } elsif (($curcolumn->{type} eq "date")||
                  # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
                  ($curcolumn->{type} eq "datetime")) {
            next unless ($i == 0);
            $ret .= writeSeperator($k, $self) if ($j++ == 0); $k++;
            $ret .= $self->printLabelHeader($curcolumn, $label, $column, 1, $filterCache->{$table.$TSEP.$column."_selected"});
            #$ret .= "<input type='text' name='search".$column."'";
            #$ret .= " value='".$filterCache->{$column}."'" if $filterCache->{$column};
            #$ret .= ">\n";
            $ret .= "<table border=0><tr><td>$self->{text}->{ACTIVE}";
            $ret .= "<input type='checkbox' name='search".$column."_active'";
            $ret .= " value='1'";
            $ret .= " checked" if ($filterCache->{$table.$TSEP.$column."_active"});
            $ret .= ">";
            $ret .= "</td><td>";
            $ret .= "$self->{text}->{FROM}</td><td>";
            $ret .= $self->printDateQuestion("search".$column."_begin_", $self->getDatePredefFor($column, $filterCache->{$table.$TSEP.$column."_begin"}));
            $ret .= "</td></tr><tr><td></td><td>";
            $ret .= "$self->{text}->{TO}</td><td>"; 
            $ret .= $self->printDateQuestion("search".$column."_end_", $self->getDatePredefFor($column, $filterCache->{$table.$TSEP.$column."_end"}, 1));
            $ret .= "</td></tr></table></td></tr>\n";
         } elsif ($curcolumn->{type} eq "virtual") {
         } else { #if (!$curcolumn->{readonly} || defined($curcolumn->{nopop})) {
            next unless ($i == 0);
            #print "XXX:".$table.$TSEP.$column.":".join(",", map { $_."=".$filterCache->{$_} } keys %{$filterCache})."<br>\n";
            $ret .= writeSeperator($k, $self) if ($j++ == 0); $k++;
            $ret .= $self->printLabelHeader($curcolumn, $label, $column, 1, $filterCache->{$table.$TSEP.$column}); #."_selected"});
            $ret .= "<input type='text' size='".($curcolumn->{size}||50)."' name='search".$column."'";
            $ret .= " value='".$filterCache->{$table.$TSEP.$column}."'" if $filterCache->{$table.$TSEP.$column};
            $ret .= "></td></tr>\n";
         }
      }
      $ret .= "</table>" if ($j || ($i == 2));
   }
   $ret .= "<input name='sessionid' type='hidden' value='".$sessionid."'>\n";
   $ret .= "<input name='table' type='hidden' value='".$table."'>\n";
   $ret .= "<INPUT type='hidden' name='tablelines' value='".$self->{tablelines}."'>\n" if defined($self->{tablelines});
   $ret .= "<input name='job' type='hidden' value='setfilter'>\n";
   $ret .= "<input name='dstjob' type='hidden' value='".$self->{"q"}->{dstjob}."'>\n" if $self->{"q"}->{dstjob};
   $ret .= "<input type='submit' value='".$submitValue."'></td></tr>\n";
   return $ret;
}

sub writeSeperator {
   my $i = shift;
   my $self = shift;
   my $ret = '';
   $ret .= "<hr>\n" if ($i != 0);
   $ret .= "<table><tr><td><b>$self->{text}->{CRITERION}</b></td>".
   #<td><b>Darstellen</b></td>
   "<td><b>Filter</b></td></tr>";
}

sub printDateQuestion {
   my $self = shift;
   my $name = shift;
   my $predef = shift || [];
   my $datedef = shift || $self->{datedef};
   my $tmp = '';

   my $i = 0;
   foreach (@$datedef) {
      #my $k = 0;
      #if ($i <= 2) { $k = $i+3; } else { $k = scalar(@{$self->{datedef}})-$i-1 }
      #print "VALUE FOR ".$_->[0]." IS ".$k.":".$predef->[$k];

      $tmp .= $_->[4]."<select name='".$name.$_->[0]."'>\n";
      for(my $j = $_->[2]; ($j <= $_->[3]); $j++) {
         $tmp .= "  <option value='".$j."'";
         $tmp .= " selected" if (exists($predef->[$i]) && ($predef->[$i] == $j));
         $tmp .= ">".$j."</option>\n";
      }
      $tmp .= "</select>".$_->[1]."\n";
      $i++;
   }
   return $tmp;
}

sub getDatePredefFor {
   my $self = shift;
   my $column = shift;
   my $searchvar = shift;
   my $high = shift || 0;
   my $tmp = '';
   my $ret = undef;
   if ($searchvar) {
      my $i = 0;
      foreach (@{$self->{datedef}}) {
         my $ttmp = '';
         $ttmp .= '(\d*)';
         $ttmp .= '\\'.$_->[5] if ($_->[5] ne '');
         if ($i > 2) {
            $tmp .= $ttmp;
         } else {
            $tmp = $ttmp.$tmp;
         }
         $i++;
      }
      Log("Searching for begin date in ".(defined($searchvar) ? $searchvar : 'UNDEFINED')." with regex :".(defined($tmp) ? $tmp : 'UNDEFINED').":".(defined($ret) ? $ret : 'UNDEFINED').":", $DEBUG);
   }
   $ret = $searchvar =~ /^$tmp$/ if ($searchvar);
   my @predef = ();
   my $i = -1;
   while (++$i < @{$self->{datedef}}) {
      my $k = 0;
      if ($i <= 2) { $k = 2 - $i } else { $k = $i; }
      #print "MEi:".$i.":".$k.":".substr($searchvar, $-[$i+1], $+[$i+1] - $-[$i+1]).":\n";
      unless ($ret && (($predef[$k] = substr($searchvar, $-[$i+1], $+[$i+1] - $-[$i+1])) ne '')) {
         $predef[$k] = $self->{datedef}->[$k]->[6];
         $predef[$k] = $high ? $self->{datedef}->[$k]->[3] : $self->{datedef}->[$k]->[2] unless $predef[$k];
         #$predef[$k] = 7 unless $predef[$k]; 
         #print "setting ".$self->{datedef}->[$k]->[0]." to ".$predef[$k]." with ".$k."<br>";
      }
   }
   return [@predef];
}

sub printLabelHeader {
   my $self = shift;
   my $curcolumn = shift;
   my $label = shift;
   my $column = shift;
   my $selectable = shift;
   my $selected = shift;
   my $tmp = '';
   $tmp .= "<tr><td valign=top>";
   $tmp .=  "<A title='".$curcolumn->{description}."'>" if $curcolumn->{description};
   $tmp .=  $label;
   $tmp .=  "</A>" if $curcolumn->{description};
   $tmp .=  "</td><td align=left valign=top>\n";
   #if ($selectable) {
   #   $tmp .=  "<input type='checkbox' name='".$column."_selected'";
   #   $tmp .=  " value='1'";
   #   $tmp .=  " checked" if ($selected);
   #   $tmp .=  ">";
   #}
   #$tmp .=  "</td><td>\n";
   return $tmp;
}

sub getDefaultValue {
   my $self = shift;
   my $options = shift;
   my $moreparams = [@_];
   if (@$moreparams) {
      Log("You have to migrate the use of getDefaultValue (now hash is used for parameters)", $ERROR);
      return undef;
   }
   unless ($options->{table} && $options->{column} && $options->{targetself}) {
      Log("getDefaultValue: Missing parameters: table:".$options->{table}.":column:".$options->{column}.":targetself:".$options->{targetself}.":more:".scalar($moreparams).": !", $ERROR);
      return undef;
   }   
   my $curtabledef = $self->getTableDefiniton($options->{table});
   my $db = $self->getDBBackend($options->{table});
   my $columndef = mergeColumnInfos($db, $curtabledef->{columns}->{$options->{column}});
   my $default = '';
   $default = $options->{mydefaults}->{$options->{table}.$TSEP.$options->{column}} if
            ($options->{mydefaults} &&
      exists($options->{mydefaults}->{$options->{table}.$TSEP.$options->{column}}) &&
     defined($options->{mydefaults}->{$options->{table}.$TSEP.$options->{column}}));
   # TODO:XXX:FIXME: WAS IST DAS: $default = $columndef->{$self->{config}->{DEFAULTJOB}} if (($default eq '') && ($columndef->{$self->{config}->{DEFAULTJOB}} ne ''));
   $default = $columndef->{defaultfunc}($options->{targetself}) if (($default eq '') && 
      (exists($columndef->{defaultfunc})) &&
         (ref($columndef->{defaultfunc}) eq "CODE"));
   return $default;
}

sub doFormularColumn {
   my $self = shift;
   my $options = shift;
   my $moreparams = [@_];
   my $return = '';
   if (@$moreparams) {
      Log("You have to migrate the use of doFormularColumn (now hash is used for parameters)", $ERROR);
      return undef;
   }
   unless ($options->{table} && $options->{column} && $options->{targetself}) {
      Log("doFormularColumn: Missing parameters: table:".$options->{table}.":column:".$options->{column}.":targetself:".$options->{targetself}.":more:".scalar($moreparams).": !", $ERROR);
      return undef;
   }   
   my $curtabledef = $self->getTableDefiniton($options->{table});
   my $db = $self->getDBBackend($options->{table});
   my $columndef = mergeColumnInfos($db, $curtabledef->{columns}->{$options->{column}});
   my $default = $self->getDefaultValue($options);

   my $curTable = undef;
   if ((($columndef->{hidden} && (($columndef->{type} ne $DELETEDCOLUMNNAME) || ((!$default) || ($default eq "false"))))
      || $columndef->{readonly} || $options->{value}) || 
        ($columndef->{type} eq "virtual")) {
      # TODO:FIXME:XXX: Die Parameter, die bestimmen obs angezeigt wird oder nicht, sollte ein ADBGUI::xxx FUnktion realiseren!
      my $tmp = $options->{value} || $default;
      if ($columndef->{type} ne "virtual") {
         $return .= "<input name='".$options->{column}."'";
         $return .= " value='".$tmp."'" if ($tmp || ($tmp ne ''));
         $return .= " type='hidden'>";
      }
      if ((!$options->{hidden}) || ($columndef->{type} eq "virtual")) {
         my $label = $columndef->{label} || $options->{column};
         $return .= $self->printLabelHeader($columndef, $label, $options->{column});
         $return .= $default;
         $return .= #$column.":".$tmp.
               " ".$columndef->{unit} if $columndef->{unit};
         $return .= "</td></tr>\n";
      }
   } elsif (($curTable = [grep { $options->{column} eq $_."_".$UNIQIDCOLUMNNAME } keys(%{$db->{tables}})]) && scalar(@$curTable)) {
      my $label = $columndef->{label} || $options->{column};
      $return .= $self->printLabelHeader($columndef, $label, $options->{column});
      $return .= $self->printSelectBoxFor($options->{targetself}->{tableCache}, $options->{table}, $options->{column}, $curTable->[0], $options->{mydefaults});
      $return .= "</td></tr>\n";
   } elsif ($curtabledef->{columns}->{$options->{column}}->{type} eq "boolean") {
      my $labelx = $columndef->{label} || $options->{column};
      $return .= $self->printLabelHeader($columndef, $labelx, $options->{column});
      $return .= "<input type='checkbox' name='".$options->{column}."'";
      $return .= " value='1'";
      $return .= " checked" if ($default && ($default ne "false"));
      $return .= ">";
      $return .= " ".$columndef->{unit} if ($columndef->{unit});
      $return .= "\n</td></tr>\n";
   } elsif (($curtabledef->{columns}->{$options->{column}}->{type} eq "date")||
            # TODO:XXX:FIXME: datetime ist im GUI.pm noch nicht ordentlich behandelt, faellt derzeit auf date zurueck!
            ($curtabledef->{columns}->{$options->{column}}->{type} eq "datetime")) {
      my $labely = $columndef->{label} || $options->{column};
      $return .= $self->printLabelHeader($columndef, $labely, $options->{column});
      $return .= $self->printDateQuestion($options->{column}, $self->getDatePredefFor($options->{column}, $default, $columndef->{endday}));
      $return .= " ".$columndef->{unit} if ($columndef->{unit});
      $return .= "</td></tr>\n";
   } elsif ($curtabledef->{columns}->{$options->{column}}->{type} eq $DELETEDCOLUMNNAME) {
      if ($default && ($default ne "false")) {
         my $labelx = $columndef->{label} || $options->{column};
         $return .= $self->printLabelHeader($columndef, $labelx, $options->{column});
         $return .= "<input type='checkbox' name='".$options->{column}."'";
         $return .= " value='1'";
         $return .= " checked" if ($default && ($default ne "false"));
         $return .= ">";
         $return .= " ".$columndef->{unit} if ($columndef->{unit});
         $return .= "\n</td></tr>\n";
      }
   } else {
      my $labelz = $columndef->{label} || $options->{column};
      $return .= $self->printLabelHeader($columndef, $labelz, $options->{column});
      if ($columndef->{lines}) {
         $return .= '<textarea name="'.$options->{column}.'" wrap="off" cols="'.($columndef->{size}||50).'" rows="'.($columndef->{lines}||10).'">';
         $return .= $default if ($default || ($default ne ''));
         $return .= '</textarea>';
      } else {
         $return .= "<input name='".$options->{column}."'";
         $return .= " value='".$default."'" if ($default || ($default ne ''));
         $return .= " type='".$columndef->{type}."' size=".($columndef->{size}||50).">";
      }
      $return .= " ".$columndef->{unit} if ($columndef->{unit});
      $return .= "</td></tr>\n";
   }
   return $options->{html} ? $return : $default;
}

sub printFormFor {
   my $self = shift;
   my $table = shift;
   my $submitValue = shift;
   my $job = shift;
   my $sessionid = shift;
   my $center = shift || 0;
   my $mydefaults = shift || undef;
   my $id = shift;
   my $tableCache = shift;
   my $targetself = shift;
   my $hidden = shift || 0;
   my $ret = '';
   $ret .= "<FORM method='POST' action='".$self->{"q"}->url(-relative=>1)."'>\n";
   $ret .= "<center>" if $center;
   $ret .= "<table>\n";
   my $curtabledef = $self->getTableDefiniton($table);
   foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
      $ret .= $self->doFormularColumn({
         targetself => $targetself,
         column     => $column,
         mydefaults => $mydefaults,
         hidden     => $hidden,
         table      => $table,
         html       => 1,
         value      => $self->{"q"}->param($column)
      });
   }
   $ret .= "<tr><td colspan=2><input name='job' type='hidden' value='".$job."'>\n";
   $ret .= "</td></tr></table>\n";
   $ret .= "<input name='sessionid' type='hidden' value='".$sessionid."'>\n";
   $ret .= "<input name='".$UNIQIDCOLUMNNAME."' type='hidden' value='".$id."'>\n" if defined($id);
   $ret .= "<input type='hidden' name='dstjob' value='".$self->{"q"}->param("dstjob")."'>" if $self->{"q"}->param("dstjob");
   $ret .= "<input type='hidden' name='searchtext' value='".$self->{"q"}->param("searchtext")."'>" if defined($self->{"q"}->param("searchtext"));
   $ret .= "<input type='hidden' name='searchfield' value='".$self->{"q"}->param("searchfield")."'>" if defined($self->{"q"}->param("searchfield"));
   $ret .= "<input type='hidden' name='tableorder' value='".$self->{"q"}->param("tableorder")."'>" if defined($self->{"q"}->param("tableorder"));
   $ret .= "<input name='table' type='hidden' value='".$table."'>\n";
   $ret .= "<table><tr><td valign=top><input type='submit' value='".$submitValue."'></form></td><td valign=top>";
   $ret .= $self->HashButton( {
      sessionid => $targetself->{sessionid},
      job => 'show',
      table => $table||''
   }, $self->{text}->{B_RETURN});
   $ret .= "</td></tr></table>\n";
   $ret .= "</center>" if $center;
   return $ret;
}

sub printTableButtons {
   my $self = shift;
   my $targetself = shift;
   my $job = shift || $self->{"q"}->param("job");
   print "<form method='post'>\n";
   print "<input type='hidden' name='job' value='".$job."'>\n";
   print "<input type='hidden' name='sessionid' value='".$targetself->{sessionid}."'>\n";
   print "<select name='table'>\n";
   foreach my $db (@{$self->{DB}}) {
      print "DB:".$db."\n";
      foreach my $table (hashKeysRightOrder($db->{tables})) {
         next if $db->{tables}->{$table}->{hidden};
         my $label = $db->{tables}->{$table}->{label} || $table;
         print "<option value='".$table."'";
         my $tmp = $self->{"q"}->param("table") || $self->{config}->{DEFAULTTABLE};
         print " selected" if ($tmp eq $table);
         print ">".$label."</option>\n";
      }
   }
   print "</select>";
   print "<input type='submit' value='";
   if ($job) {
      print $self->{text}->{CHANGE};
   } else {
      print $self->{text}->{REFRESH};
   }
   print "'>";
   print "</form>";
   if ($self->{"q"}->param("job") ne $self->{config}->{DEFAULTJOB}) {
      print "<br><br>";
      print $self->HashButton( {
         sessionid => $targetself->{sessionid},
         job => $self->{config}->{DEFAULTJOB} || "defaultjob",
      }, $self->{text}->{B_START}, { link => 1 } )."<br>";
   }
}

sub retrieveBasic {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   my $tag = shift;
   my $writeto = shift;
   my $okisok = shift;
   $_ = $line->{data};

   if (/^$tag\s+?(\S*)\s+?(\S+)(\s+?(.*))?$/) {
      my $table = $1;
      my $action = $2;
      my $error = $3;
      if ($action eq "BEGIN") {
         $targetself->{count} = 0;
         $targetself->{curTable} = {};
         return $RUNNING;
      } elsif ($action eq "FAILED") {
         print "<font color='#FF0000'><b>ERROR: </b>".$tag.": ".($error ? $error : "general retrieve failed")."</font>\n";
      } elsif ($action eq "END") {
         $targetself->{$writeto} = $targetself->{curTable};
         delete $targetself->{curTable};
         return $ACTIONOK;
      } else {
         print "PROTOKOLL ERROR retrieveBasic1.<br>\n";
         return $PROTOKOLLERROR;
      }
   } elsif (/^([^:]+):\s(.*)$/) {
      my $key = $1;
      my $value = $2;
      if (exists($targetself->{curTable}->{$key})) {
         $targetself->{curTable}->{$key} = [$targetself->{curTable}->{$key}] unless (ref($targetself->{curTable}->{$key}) eq "ARRAY");
         push(@{$targetself->{curTable}->{$key}}, $value); 
      } else {
         $targetself->{curTable}->{$key} = $value;
      }
      return $RUNNING;
   } else {
      print "PROTOKOLL ERROR retrieveBasic2: ".$tag.": '".$_."'\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub retrieveGrouped {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   $_ = $line->{data};

   if (/^GETGROUPED\s+(\S+)\s+(\S+)\s+(.*?)(\s+(\d+))?$/) {
      my $table = $1;
      my $column = $2;
      my $action = $3;
      my $lines = $4; # Derzeit unbelegt!
      if (($action eq "NEXT") || ($action eq "END")) {
         my $curtabledef = $self->getTableDefiniton($table);
         my $found = 0;
         $targetself->{curGrouped}->{$targetself->{curTable}->{$column}} = $targetself->{curTable}->{"COUNT(*)"} || $targetself->{curTable}->{"count"} unless $found;
   
      }
      if ($action eq "BEGIN") {
         $targetself->{count} = 0;
         $targetself->{curTable} = {};
         return $RUNNING;
      } elsif ($action eq "NEXT") {
         $targetself->{curTable} = {};
         return $RUNNING;
      } elsif ($action =~ /^FAILED/) {
         syswrite(STDOUT, "<font color='#FF0000'><b>ERROR:</b>GETGROUPED ".$self->{text}->{ERR_RETRIEVE}."</font>\n");
      } elsif ($action eq "END") {
         return $ACTIONOK;
      } else {
         print "PROTOKOLL ERROR 11.<br>\n";
         return $PROTOKOLLERROR;
      }
   } elsif (/^([^:]+):\s(.*)$/) {
      my $key = $1;
      my $value = $2;
      $targetself->{curTable}->{$key} = $value;
      return $RUNNING;
   } else {
      print "PROTOKOLL ERROR 13.<br>\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub retrieveTables {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   my $stadium = shift || 0;
   my $tablestodo = shift;
   $_ = $line->{data};

   if (/^GET (\S+) (\S+)(\s(\S+))?(\s(\S+))?(\s*[.*])?$/) {
      my $table = $1;
      my $action = $2;
      my $lines = $4;
      my $filtered = $6;
      $targetself->{tableCacheInfo}->{$table}->{lines} = $lines;
      $targetself->{tableCacheInfo}->{$table}->{filtered} = $filtered;
      $targetself->{filtered} = $filtered ? 1 : 0;
      my $error = $5.$7;
      push(@{$targetself->{userlist}}, [$targetself->{curUsername}, $targetself->{curID}, $targetself->{curareamanager},
           $targetself->{curadmin}]) if (($action eq "NEXT") || ($action eq "END"));
      if ($action eq "BEGIN") {
         $targetself->{count} = 0;
         $targetself->{curTable} = {};
         $targetself->{tableCache}->{$table} = [];
         return $RUNNING;
      } elsif ($action eq "FAILED") {
            print "<font color='#FF0000'><b>ERROR:</b> ".$error."</font>\n";
      } elsif ($action eq "NEXT") {
         push(@{$targetself->{tableCache}->{$table}}, $targetself->{curTable});
         $targetself->{curTable} = {};
         return $RUNNING;
      } elsif ($action eq "END") {
         push(@{$targetself->{tableCache}->{$table}}, $targetself->{curTable})
            if scalar(keys(%{$targetself->{curTable}}));
         unless (my $curTable = pop(@$tablestodo)) {
            return $ACTIONOK;
         } else {
            $self->sendLine("GET ".$curTable);
            return $RUNNING;
         }
      } else {
         print "PROTOKOLL ERROR 8.<br>\n";
         return $PROTOKOLLERROR;
      }
   } elsif (/^([^:]+):\s(.*)$/) {
      my $key = $1;
      my $value = $2;
      $value =~ s/##/#/g;
      $value =~ s/#13/<br>\n/g;
      $value =~ s/#10/\r/g;
      $targetself->{curTable}->{$key} = $value;
      return $RUNNING;
   } else {
      print "PROTOKOLL ERROR 9.<br>\n";
      return $PROTOKOLLERROR;
   }
   return $DONE;
}

sub authenticate {
   my $self = shift;
   my $line = shift;
   my $targetself = shift;
   my $stadium = shift || 0;
   my $dontprint = shift || 0;
   my $sessionid = shift;
   $sessionid = $self->{"q"}->param('sessionid') unless defined($sessionid);
   my $user = shift || $self->{"q"}->param('user');
   my $pass = shift || $self->{"q"}->param('pass');
   my $supassword = shift || undef;
   $_ = $line->{data};
   if ($stadium == $STARTUP) {
      if ($sessionid || (defined($user) && ($user ne ''))) {
         return $RUNNING;
      } else {
         ((print $self->{"q"}->header.$self->{header}) && ($targetself->{noStyle} = undef)) if ($targetself->{noStyle} && (!$dontprint));
         $self->printLoginFormular("", $user) unless $dontprint;
      }
   } elsif ($stadium == $CONNECTED) {
      if ($sessionid) {
         $self->sendLine("SESSION ".$sessionid);
         return $RUNNING;
      } elsif (defined($user)) {
         $self->sendLine("AUTH ".$user." ".$pass.($supassword ? " ".$supassword : ''));
         return $RUNNING;
      } else {
         ((print $self->{"q"}->header.$self->{header}) && ($targetself->{noStyle} = undef)) if ($targetself->{noStyle} && (!$dontprint));
         $self->printLoginFormular("", $user) unless $dontprint;
      }
   } elsif ($targetself->{sessionid}) {
      return $ACTIONOK;
   } elsif (/^AUTH\s(\S+)(\s+(\d*))?(\s+(\d*))?$/) {
      my $type = $1;
      $targetself->{sessionid} = $3;
      $targetself->{rights} = $5;
      if (($type eq "OK") && $targetself->{sessionid}) {
         $targetself->{user} = $user;
         if ($self->{config}->{debug} && (!$dontprint)) {
            $targetself->{noStyle} = undef;
         }
         return $ACTIONOK;
      } else {
         print "<br><center>" unless $dontprint;
         print $self->{text}->{AUTH_FAILED} unless $dontprint;
         print "</center>\n" unless $dontprint;
         # Wenn die Session fehlschl�gt, sind wir irgendwo bereits
         # in den Tiefen des Scripts, und haben somit m�glicherweise
         # einen Job, der Zusatzparameter hat. Damit da dann nicht
         # irgendwas passiert, setzen wir das auf den default job um,
         # wenn sich der User neu einloggt.
         ((print $self->{"q"}->header.$self->{header}) && ($targetself->{noStyle} = undef)) if ($targetself->{noStyle} && (!$dontprint));
         $self->printLoginFormular("", $user) unless $dontprint;
      }
   } elsif (/^SESSION\s+(\S+)(\s+(\S+))(\s+(\d+))$/) {
      my $stype = $1;
      $targetself->{user} = $3;
      if (($stype eq "OK") && $targetself->{user}) {
         $targetself->{rights} = $5;
         $targetself->{sessionid} = $sessionid;
         return $ACTIONOK;
      } else {
         print "<br><center>" unless $dontprint;
         print $self->{text}->{SESSION_RESTORE}.$targetself->{sessionid}."\n" unless $dontprint;
         print "</center>\n" unless $dontprint;
         # Wenn die Session fehlschl�gt, sind wir irgendwo bereits
         # in den Tiefen des Scripts, und haben somit m�glicherweise
         # einen Job, der Zusatzparameter hat. Damit da dann nicht
         # irgendwas passiert, setzen wir das auf den default job um,
         # wenn sich der User neu einloggt.
         ((print $self->{"q"}->header.$self->{header}) && ($targetself->{noStyle} = undef)) if ($targetself->{noStyle} && (!$dontprint));
         $self->printLoginFormular("", $user) unless $dontprint;
      }
   } else {
      ((print $self->{"q"}->header.$self->{header}) && ($targetself->{noStyle} = undef)) if ($targetself->{noStyle} && (!$dontprint));
      $self->printLoginFormular("", $user) unless $dontprint;
   }
   return $DONE;
};

sub ProcessServer {
   my $self = shift;
   my $targetself = shift;
   my $timeout = shift;

   Log("Beginning Loop!", $DEBUG);

   READWHILE: while (1) {
      my $line = $self->readLn($timeout, $targetself->{noLF});
      if ($line->{event} == $ERROR) {
         return $line->{event};
      } elsif ($line->{event} == $TIMEOUT) {
         return $line->{event};
      }

      ##############      
      # Was sagt uns die eingehende Zeile?
      ##############

      Log("I`VE READ:".$line->{data}, $DEBUG);
      my $ret = $targetself->{handler}($self, $targetself, $line);
      return $ret if ($ret != $RUNNING);
   }
}   

sub sendLine {
   my $self = shift;
   my $msg = shift;
   my $out = shift || $self->{fd};
   unless ($out) {
      $out = \*STDOUT;
   }

   unless (syswrite($out, $msg."\n")) {
      die("sendLine: Unable to write to ".$out."!\n");
   }
   Log("Sent:".$msg, $DEBUG) unless $self->{self}->{debug};
}

# Diese Funktion erzeugt Debugmeldungen
sub debug {
   my $self = shift;
   my $msg = shift;
   my $severity = shift;
   my $line = '';
   if ($severity == $ERROR) {
       $line  .= "-> ERROR: ";
   } elsif ($severity == $DEBUG) {
       return unless $self->{config}->{debug};
       $line .= "DEBUG:";
   } else {
       $line  .= "* ";
   }
   $self->sendLine($line.$msg, \*STDERR, 1);
}

# Liest mithilfe von select eine Zeile, ohne der Gefahr unendlich zu blocken.
sub readLn {
   my $self = shift;
   my $line = {};
   my $timeout = shift;
   my $regexes = shift;

   my $i = 0;
   # Wir lesen so lange...
   while (1) {
      # ... bis wir eine Zeile zusammen haben.
      $i++;
      if (scalar(my @lines = split(/\n/, $self->{buf}, 2))>1) {
         $line->{data} = $lines[0];
         $self->{buf} = $lines[1];
         $line->{event} = $OK;
         return $line;
      } elsif(SearchNoCRLFLine($regexes, $self->{buf})) {
         $line->{data} = $self->{buf};
         $self->{buf} = '';
         $line->{event} = $OK;
         $line->{noLF} = 1;
         return $line;
      } else {
         # Wenn wir im Buffer noch keine zusammen haben...
         my $rin = my $win = my $ein = '';
         vec($rin,fileno($self->{fd}),1) = 1;
         # ... dann lesen wir, und warten max, bis zu $timeout sekunden.
         my $input;
         if (select(my $rout = $rin, undef, undef, $timeout)) {
            my $read = sysread($self->{fd}, $input, 512);
            # Das folgende ist selbsterkl\xe4rend:
            if (!defined($read)) {
               Log("Program died or other error at read!", $ERROR);
               $line->{event} = $RERROR;
               return $line;
            }
            if ($read <= 0) {
               Log("SELECT(2) lies: Nothing to read! Child and/or connection died?!", $ERROR);
               $line->{event} = $RERROR;
               exit(0);
               return $line;
            }
            $self->{buf} .= $input;
         } else {
            $line->{event} = $TIMEOUT;
            Log("Nothing to read within timeout of ".$timeout." Seconds.", $ERROR);
            return $line;
         }
      }
   }
}

sub SearchNoCRLFLine {
   my $regexes = shift;
   my $buf = shift;
   # Die Regexen m\xfcssen ein Pointer auf einen Array sein.
   # Es darf kein "\n" drin sein: Die Zeile muss vorher sperat raus,
   # bevor wir eine Zeilen ohne \n rauszuschicken k\xf6nnen !!!
   if (defined($regexes) && (ref($regexes) eq "ARRAY") && (!($buf =~ /\n/))) {
      foreach my $regex (@$regexes) {
         return 1 if ($buf =~ /$regex/);
      }
   } else {
      return 0;
   }
}

1;
