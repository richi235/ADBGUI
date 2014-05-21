package ADBGUI::BasicVariables;

use strict;
use warnings;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw/$MODIFY $ADMIN $AREAMANAGER $ACTIVESESSION $NOTHING $USERSTABLENAME $UNIQIDCOLUMNNAME
                    $USERNAMECOLUMNNAME $PASSWORDCOLUMNNAME $DELETEDCOLUMNNAME $TIMESTAMP $USER $TABLE $TYP $BACKWARD
                    $ENTRY $DIFF $LOG $AREAMANAGERFLAGCOLUMNNAME $ADMINFLAGCOLUMNNAME $MODIFYFLAGCOLUMNNAME $FORWARD 
                    $ERROR $WARNING $INFO $DEBUG $COLUMNCONJUNCTION $PIDFILE $TSEP $LISTACTION $NEWACTION $UPDATEACTION/;
}

our $TSEP = ".";

our $FORWARD = 1;
our $BACKWARD = 2;

my ($PROCNAME) = $0 =~ m!([^/]+)$!;
$PROCNAME =~ s/\.\w+$//;
our $PIDFILE = "/var/run/${PROCNAME}.pid";

our $COLUMNCONJUNCTION = " | ";

# Rechteflags, die ein User haben kann
# Applikationsspezifische Flags beginnen ab 2**10!
our $MODIFY        = 2**3;
our $ADMIN         = 2**2; 
our $AREAMANAGER   = 2**1;
our $ACTIVESESSION = 2**0;
our $NOTHING       = 0;

our $LISTACTION = 1;
our $NEWACTION = 2;
our $UPDATEACTION = 3;

# Tabellenamenfestlegung
our $USERSTABLENAME = "users";

# Spaltenfestlegung Grundsaetzlich
our $UNIQIDCOLUMNNAME          = "id";
our $USERNAMECOLUMNNAME        = "username";
our $PASSWORDCOLUMNNAME        = "password";
our $DELETEDCOLUMNNAME         = "deleted";
our $TIMESTAMP                 = "mydate";
our $USER                      = "username";
our $TABLE                     = "mytable";
our $TYP                       = "type";
our $ENTRY                     = "entry";
our $DIFF                      = "diff";
our $LOG                       = "log";
our $AREAMANAGERFLAGCOLUMNNAME = "areamanager";
our $ADMINFLAGCOLUMNNAME       = "admin";
our $MODIFYFLAGCOLUMNNAME      = "modify";

# Logmeldungs-Typen
our $ERROR = 4;
our $WARNING = 3;
our $INFO = 2;
our $DEBUG = 1;

