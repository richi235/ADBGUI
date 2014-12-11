package example::DBDesign;

use strict;
use warnings;

use ADBGUI::BasicVariables;
use ADBGUI::DBDesign(qw/$RIGHTS $DBUSER/);
use ADBGUI::Tools qw(Log);

our @ISA;

BEGIN {
    use Exporter;
    our @ISA    = qw(Exporter);
    our @EXPORT = qw//;
}

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

sub getDB
{
    my $self = shift;
    my $DB   = $self->SUPER::getDB() || {};

    return $DB;
}

1;
