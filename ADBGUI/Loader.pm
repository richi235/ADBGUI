package ADBGUI::Loader;

use strict;
use warnings;


sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $dsts = shift;
   my $self  = {};
   bless ($self, $class);
   foreach my $dst (@$dsts) {
      push(@{$self->{pmdef}}, [[], $dst]);
   }

   opendir(PACKETS, ".");
   while(my $dirname = readdir(PACKETS)) {
      next unless -d $dirname;
      next if $dirname =~ m,^\.+$,;
      next if ($dirname eq "ADBGUI");
      next if ($dirname eq "install");
      foreach my $curdef (@{$self->{pmdef}}) {
         if (-R $dirname."/".$curdef->[1].".pm") {
            push(@{$curdef->[0]}, [$dirname, $curdef->[1]]);
            require $dirname."/".$curdef->[1].".pm";
            #print "FOUND: ".$dirname."::".$curdef->[1]."\n";
         }
      }
   }
   return $self;
}

sub newObject {
   my $self = shift;
   my $curid = shift;
   my $curdef = undef;
   foreach my $curpmdef (@{$self->{pmdef}}) {
      next if ($curpmdef->[1] ne $curid);
      $curdef = $curpmdef;
      last;
   }
   die "Unbekanntes Modul '".$curid."' !" unless $curdef;
   my $params = shift;
   my $newobj = undef;
   #print "Starting ".$curdef->[1]."\n";
   eval '$newobj = ADBGUI::'.$curdef->[1].'->new(@$params)';
   die $@ if $@;
   #print '  ADBGUI::'.$curdef->[1]."\n";
   foreach my $curpacket (@{$curdef->[0]}) {
      #print "  ".$curpacket->[0]."::".$curpacket->[1]."\n";
      eval '$newobj = '.$curpacket->[0]."::".$curpacket->[1].'->new($newobj)';
      die $@ if $@;
   }
   return $newobj;
}

1;
