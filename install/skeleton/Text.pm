package example::Text;

use strict;
use warnings;

our @ISA;

sub new
{
    my $proto  = shift;
    my $self   = shift;
    
    my $class  = ref($proto) || $proto;
    my $parent = $self ? ref($self) : "";
    $self = $self ? $self : {};

    @ISA = ($parent) if $parent;

    bless( $self, $class );
    return $self;
}

1;
