#!/usr/bin/perl

use strict;
use warnings;

use ADBGUI::GUI;
use ADBGUI::Text;
use ADBGUI::DBDesign;
use ADBGUI::Loader;
use DBDesign qw/$DB/;

my $loader = ADBGUI::Loader->new(["GUI", "Text"]);

my $dbs = [$DB];

my $gui = $loader->newObject("GUI", [$dbs, $loader->newObject("Text", []), 'gui.cfg']);

$gui->run();
