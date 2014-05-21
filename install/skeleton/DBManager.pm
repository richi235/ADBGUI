package example::DBManager;

use strict;
use warnings;
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(Log);

our @ISA;

sub new {
   my $proto = shift;
   my $class = ref($proto) || $proto;
   my $self = shift;
   my $parent = $self ? ref($self) : "";
   @ISA = ($parent) if $parent;
   $self = $self ? $self : {};
   bless ($self, $class);
   return $self;
}

1;
