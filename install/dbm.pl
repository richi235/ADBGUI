use strict;
use warnings;

use ADBGUI::Text;
use ADBGUI::GUI;
use ADBGUI::DBManager;
use ADBGUI::Qooxdoo;
use ADBGUI::Loader;
use DBDesign qw/$DB/;

my $configkeys = [qw(Name Debug Daemon ListenIP ListenPort ReadTimeOut ReadLineTimeOut ClientTimeout LoginSessionTimeout CustomCmdTimeout QooxdooListenIP QooxdooListenPort)];

my $loader = ADBGUI::Loader->new(["GUI", "Qooxdoo", "DBManager", "Text"]);

my $dbs = [$DB];

my $adbgui = $loader->newObject("Qooxdoo", [
   $loader->newObject("GUI",       [$dbs,              $loader->newObject("Text", []), 'gui.cfg']),
   $loader->newObject("DBManager", [$dbs, $configkeys, $loader->newObject("Text", []), 'dbm.cfg']),
]);

print "Running ".localtime(time())."\n";

POE::Kernel->run();
