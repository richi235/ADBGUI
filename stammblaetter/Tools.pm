 package stammblaetter::Tools;

use strict;
use warnings;
use Carp qw(cluck confess);
use ADBGUI::Qooxdoo;
use POE;
use Encode;

my $MAXCMDREFRESH = 1;

BEGIN {
   use Exporter;
   our @ISA = qw/Exporter/;
   #our @EXPORT = qw//;
   our @EXPORT_OK = qw/showHTMLDocumentAsPDF/;
}

sub showHTMLDocumentAsPDF {
   my $self = shift;
   my $options = shift;

   $poe_kernel->yield(sendToQX => "destroy ".$options->{winname});
   $poe_kernel->yield(sendToQX => "createwin ".$options->{winname}." ".($qxwidth)." ".($qxheight)." ".CGI::escape($options->{wintitle})." ".CGI::escape($options->{winicon}));
   $poe_kernel->yield(sendToQX => "createiframe ".$options->{winname}."_iframe"." ".CGI::escape("about:blank"));
   $poe_kernel->yield(sendToQX => "addobject ".$options->{winname}." ".$options->{winname}."_iframe");
   $poe_kernel->yield(sendToQX => "open ".$options->{winname});
   $poe_kernel->yield(sendToQX => "maximize ".$options->{winname}." 1");

   my $conf = "/tmp/html2ps.conf";
   open(CONF, ">", $conf);
   print CONF '@html2ps {
      option {
         scaledoc: 0.9;
         scaleimage: 0.20;
      }
      titlepage {
         margin-top: 0cm;
      }
   }
   @page {
      scaledoc: 0.1;
      margin-left: 1.5cm;
      margin-right: 1.5cm;
      margin-top: 0cm;
      margin-bottom: 0cm;
      scaleimage: 1%;
   }';
   close CONF;
   system('bash -c "cp '.$conf.' \$HOME/.html2psrc"');

   $self->{dbm}->onRunCmd({
      curSession => $options->{curSession},
      command => ["-c", '/usr/bin/html2ps -U -s 0.1 -f '.$conf.' | /usr/bin/ps2pdf -'],
      qxself => $self,
      poll => 1,
      timeout => 10,
      id => $options->{id},
      winname => $options->{winname},
      htmlout => $options->{htmlout},
      self => $self,
      maxupdatesperinterval => $MAXCMDREFRESH,
      #curset => $daten->[0]->[0],
      #filter => POE::Filter::Line->new(),
      onCmdStart => sub {
         my $heap = shift;
         die if shift;
         $heap->{changes} = 0;
         $heap->{buf} = "";
         $heap->{log} = [];
         $heap->{start} = time();
         push(@{$heap->{log}}, "Programm started.");
         $heap->{cmd}->put($heap->{options}->{htmlout});
      },
      onCmdPoll => sub {
         my $heap = shift;
         die if shift;
         $heap->{cmd}->shutdown_stdin()
            unless $heap->{cmd}->get_driver_out_octets();
         $heap->{options}->{sendRefresh}($heap);
      },
      onCmdRead => sub {
         my $heap = shift;
         my $in = shift;
         my $stderr = shift;
         die if shift;
         if ($stderr) {
            $in =~ s,\n,<br>,g;
            $heap->{error} .= $in."<br>";
         } else {
            $heap->{buf} .= $in;
         }
         $heap->{options}->{sendRefresh}($heap)
            if (exists($heap->{options}->{sendRefresh}) &&
               defined($heap->{options}->{sendRefresh}) &&
                        $heap->{options}->{sendRefresh}  &&
                  (ref($heap->{options}->{sendRefresh}) eq "CODE") &&
                     (!($heap->{changes}++ >= ($heap->{options}->{maxupdatesperinterval} || $MAXCMDREFRESH))));
      },
      onCmdClose => sub {
         my $heap = shift;
         die if shift;
         if (
            $heap->{options}->{curSession}->{cached} = $heap->{buf}
            ) {
            $heap->{options}->{curSession}->{cachedcontenttype} = "application/pdf";
            $heap->{options}->{qxself}->sendToQXForSession($heap->{options}->{sessionid}, "destroy ".$heap->{options}->{winname}."_iframe");
            $heap->{options}->{qxself}->sendToQXForSession($heap->{options}->{sessionid}, "createiframe ".$heap->{options}->{winname}."_iframex ".CGI::escape("/ajax?nocache=".rand(999999999999)."&job=getcached&sessionid=".$heap->{options}->{curSession}->{sessionid}));
            $heap->{options}->{qxself}->sendToQXForSession($heap->{options}->{sessionid}, "addobject ".$heap->{options}->{winname}." ".$heap->{options}->{winname}."_iframex"); 
            push(@{$heap->{log}}, "Program terminated with ".length($heap->{buf})." Bytes.");
         } else {
            push(@{$heap->{log}}, "<font color=red>Timeout!</font>");
         }
         return if $heap->{done}++;
      },
      onCmdStop => sub {
         my $heap = shift;
         die if shift;
         push(@{$heap->{log}}, "Programm stopped");
         return if $heap->{done}++;
         $heap->{options}->{sendRefresh}($heap)
            if (exists($heap->{options}->{sendRefresh}) &&
               defined($heap->{options}->{sendRefresh}) &&
                        $heap->{options}->{sendRefresh}  &&
                  (ref($heap->{options}->{sendRefresh}) eq "CODE"));
      },
      sendRefresh => sub {
         my $heap = shift;
         $heap->{options}->{qxself}->sendToQXForSession($heap->{options}->{sessionid}, "iframewritereset ".$heap->{options}->{winname}."_iframe"." ".CGI::escape(
            "<font face=arial><br><br><center><b>Bitte warten!</b><br><br>Berechnung läuft seit ".(time()-$heap->{start})." Sekunden.</center><br><br><hr>".join("<br>", (map { encode("iso-8859-1", decode("utf8", $_)) } grep { defined($_) } @{$heap->{log}}))."<br><font size=1>out=".length($heap->{options}->{htmlout})." in=".length($heap->{buf})." error=".length($heap->{error})."</font>".($heap->{tmpmsg} ? "<hr>".$heap->{tmpmsg} : "")
            #.(($heap->{error} && $debug) ? "<hr>".$heap->{error} : "")
         ), 1);
         $heap->{options}->{qxself}->sendToQXForSession($heap->{options}->{sessionid}, "iframewriteclose ".$heap->{options}->{winname}."_iframe");
      },
   });
}
