#!/usr/bin/perl

package DBDesign;

use strict;
use warnings;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw/$DB/;
}

use ADBGUI::DBDesign;
use ADBGUI::Loader;

my $loader = ADBGUI::Loader->new(["DBDesign"]);

our $DB =
   $loader->newObject("DBDesign")->getDB();

1;

