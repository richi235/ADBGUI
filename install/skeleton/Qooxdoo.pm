package example::Qooxdoo;

use strict;
use warnings;
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(Log);
use POE;

our @ISA;

sub new
{
    my $proto  = shift;
    my $self   = shift;

    my $class  = ref($proto) || $proto;
    my $parent = $self ? ref($self) : "";
    $self      = $self ? $self : {};

    @ISA = ($parent) if $parent;

    bless( $self, $class );

    return $self;
}

# Here, You can directly use $self->{text} and all the other
# Member variables of Qooxdoo.pm of the superclass and all other modules.

1;
