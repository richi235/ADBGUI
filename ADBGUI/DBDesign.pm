package ADBGUI::DBDesign;

use strict;
use warnings;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw/$NAMECOLUMNNAME $TYP $TIMESTAMP $DBUSER $AJAXDISCONNECTED $AJAXFLUSHED $AJAXSTART
                    $TABLE $DIFF $USER $ABTEILUNGEN $FETCHMAIL $DB $HOMEDIR
                    $HOST $USER $DOMAIN $SQUID $FORWARD $ALIAS $DOMAINACCESS
                    $DOMAINADMIN $DOMAINPUSER $DOMAINDEACTIVATED $RIGHTS
                    $DOMAINPROFILE $QUESTION $REALGROUPNAME $GROUPID/;
}

use ADBGUI::BasicVariables;
use ADBGUI::DBDesign_Labels;

our @ISA;

our $NAMECOLUMNNAME = "name";
our $AJAXDISCONNECTED = 1;
our $AJAXFLUSHED      = 2;
our $AJAXSTART        = 3;

my $labels = $ADBGUI::DBDesign_Labels::labels;


sub new
{
   my $proto = shift;
   my $self = shift;

   my $class = ref($proto) || $proto;
   my $parent = $self ? ref($self) : "";

   @ISA = ($parent) if $parent;

   $self = $self ? $self : {};
   bless ($self, $class);

   return $self;
}

#   DBUser     User  Passwort
our $DBUSER = ["web", '', 'localhost']; # Letzer Parameter ist IP des Clients. Postgress hat das nicht,
                                       # aber MySQL.
# Standardrights
our $RIGHTS = ["insert","select","update"];

# Datenbankdefinition
sub getDB {
   my $self = shift;
   my $DB = {};
   $DB->{user} = $DBUSER;
   $DB->{type} = "mysql", # postgres oder mysql
   $DB->{host} = "localhost";
   $DB->{name} = "adbgui";
   $DB->{postgres} = {
      pre => "-- Achtung: Diese Datei wird automatisch erzeugt! <C4>nderungen\n".
             "--          muessen in DBDesign.pm durchgefuehrt werden, und\n".
             "--          'createPostGress.pl' erzeugt diese Datei dann neu.\n".
             "-- ACHTUNG: Alle Spalten werden LowerCase behandelt!\n\n",
      post => "\n".'insert into '.$USERSTABLENAME.' ('.$USERNAMECOLUMNNAME.', '.$PASSWORDCOLUMNNAME.
              ', '.$ADMINFLAGCOLUMNNAME.', '.$MODIFYFLAGCOLUMNNAME.") VALUES ('admin', '\$1\$87aO8jLQ\$Vjda50oS47CGlZ2RuroU61', '1', '1');\n"                                                                                    # Passwort ist "bitteaendern"
   };
   $DB->{mysql} = {
       pre => "# Achtung: Diese Datei wird automatisch erzeugt! <C4>nderungen\n".
              "#          muessen in Tools.pm durchgefuehrt werden, und\n".
              "#          'createMySQLScript.pl' erzeugt diese Datei dann neu.\n".
              "# ACHTUNG: Alle Spalten werden LowerCase behandelt!\n\n",
              #"drop database ".$DBNAME.";\ncreate database ".$DBNAME.";\nuse ".$DBNAME.";\n\n",
       post => "\n".'insert into '.$USERSTABLENAME.' ('.$USERNAMECOLUMNNAME.', '.$PASSWORDCOLUMNNAME.
               ', '.$ADMINFLAGCOLUMNNAME.', '.$MODIFYFLAGCOLUMNNAME.') VALUES ("admin", "\$1\$87aO8jLQ\$Vjda50oS47CGlZ2RuroU61",'.
               ' "1", "1");'."\n\nFLUSH PRIVILEGES;\n",                                  # Passwort ist "bitteaendern"
       createDB => "create database ",
       dropDB   => "drop database ",
       useDB    => "use "
   };
   $DB->{pre} = "## WARNING; UNSUPPORTED DATABASE TYPE BEGIN ##\n";
   $DB->{post} = "## WARNING; UNSUPPORTED DATABASE TYPE END ##\n";
   $DB->{types}->{$UNIQIDCOLUMNNAME} = {
      postgres => {
         dbtype => "serial8"
      },
      mysql => {
         auto_increment => 1
      },
      dbcompare => "=",
      hidden => 1,
      selectAlsoIfHidden => 1,
      dbtype => "INT(64)",
      label => $labels->{unique_id} 
   };
   
   $DB->{types}->{double} = {
      dbtype => "DOUBLE",
      replacecommas => 1,
      syntaxcheck => '^\d+(\.\d*)?$',
      dbcompare => "=",
   };

   $DB->{types}->{number} = {
      postgres => {
         dbtype => "int"
      },
      dbtype => "INT(32)",
      syntaxcheck => '^\d+$',
      dbcompare => "="
   };
   $DB->{types}->{timestamp} = {
      postgres => {
         dbtype => "int"
      },
      dbtype => "timestamp",
      syntaxcheck => '^\d+$',
      dbcompare => "="
   };
   $DB->{types}->{datavolume} = {
      postgres => {
         dbtype => "bigint"
      },
      syntaxcheck => '^\d+$',
      dbtype => "INT(64)",
      dbcompare => "="
   };
   $DB->{types}->{longnumber} = {
      postgres => {
         dbtype => "bigint",
      },
      prioautodblayout => 1,
      dbtype => "INT(64)",
      dbcompare => "="
   };
   $DB->{types}->{$DELETEDCOLUMNNAME} = {
      postgres => {
         dbtype => "boolean",
         "default" => "false"
      },
      dbtype => "INT(1)",
      notnull => 1,
      hidden => 1,
      showInSearch => 1,
      selectAlsoIfHidden => 1,
      "default" => "0",
      dbcompare => "=",
      label => $labels->{deleted}
   };
   $DB->{types}->{inet} = {
      postgres => {
         dbtype => "inet",
         dbcompare => "="
      },
      syntaxcheck => '^\d+(\.\d+){3}$',
      dbtype => "VARCHAR(15)",
      dbcompare => "LIKE"
   };
   $DB->{types}->{date} = {
      postgres => {
         dbtype => "timestamp",
         dbcompare => "="
      },
      syntaxcheck => '^\d{4}\-\d{1,2}\-\d{1,2}(\ \d{1,2}\:\d{1,2}(:\d{1,2})?)?$',
      dbtype => "datetime",
      dbcompare => "=",
      nobr => 1
   };
   $DB->{types}->{datetime} = {
      postgres => {
         dbtype => "timestamp",
         dbcompare => "="
      },
      syntaxcheck => '^\d{4}\-\d{1,2}\-\d{1,2}(\ \d{1,2}\:\d{1,2}(:\d{1,2})?)?$',
      dbtype => "datetime",
      dbcompare => "=",
      nobr => 1
   };
   $DB->{types}->{longtext} = {
      postgres => {
         dbtype => "text",
         dbcompare => "="
      },
      mysql => {
         instr => 1,
      },
      dbtype => "LONGTEXT",
      dbcompare => "LIKE"
   };
   $DB->{types}->{textarea} = {
      postgres => {
         dbtype => "text",
         dbcompare => "="
      },
      mysql => {
         instr => 1,
      },
      dbtype => "LONGTEXT",
      dbcompare => "LIKE"
   };
   $DB->{types}->{image} = {
      postgres => {
         dbtype => "", # TODO/FIXME/XXX
         dbcompare => "="
      },
      dbtype => "LONGBLOB",
      dbcompare => "LIKE"
   };
   $DB->{types}->{htmltext} = {
      postgres => {
         dbtype => "text",
         dbcompare => "="
      },
      dbtype => "BLOB",
      dbcompare => "LIKE"
   };
   $DB->{types}->{text} = {
      postgres => {
         dbtype => "text",
         dbcompare => "="
      },
      mysql => {
         instr => 1,
      },
      prioautodblayout => 1,
      dbtype => "VARCHAR(255)",
      dbcompare => "="
   };
   $DB->{types}->{password} = {
      postgres => {
         dbtype => "text",
         dbcompare => "="
      },
      dbtype => "VARCHAR(255)",
      dbcompare => "=",
      syntaxcheck => '^\S+$',
      secret => 1
   };
   $DB->{types}->{boolean} = {
      postgres => {
         dbtype => "boolean",
         "default" => "false",
         dbcompare => "="
      },
      booleanlabel => ["[ ]", "[X]"],
      dbtype => "INT(1)",
      "default" => "0",
      dbcompare => "LIKE",
      prioautodblayout => 1,
   };
   $DB->{types}->{virtual} = {
      readonly => 1
   };

   ############################################################
   #########   Next: The ADBGUI Base-Tables:  #################
   ############################################################
   
   # Users

   $DB->{tables}->{$USERSTABLENAME} =
   {
      primarykey => [$UNIQIDCOLUMNNAME, $USERNAMECOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 1,
      crossShowInSelect => $USERNAMECOLUMNNAME,
      label => $labels->{user} 
   };

   # ToDo: Die Standardspalten (also $UNIQIDCOLUMNNAME und $DELETEDCOLUMNNAME?)
   #       sollten standardmaessig da sein, ohne definert werden zu muessen.
   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 2
   };

   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$USERNAMECOLUMNNAME} = {
      type         => "text",
      nochange     => 1,
      notnull      => 1,
      showInSelect => 1,
      label        => $labels->{username},
      order        => 3
   };

   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$MODIFYFLAGCOLUMNNAME} = {
       type  => "boolean",
       label => $labels->{change_permission} ,
       order => 4
   };
   
   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$ADMINFLAGCOLUMNNAME} = {
       type   => "boolean",
       hidden => 0,
       label  => $labels->{superuser} ,
       order  => 5
   };

   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$PASSWORDCOLUMNNAME} = {
      type => "password",
      writeonly => 1,
      secret => 1,
      comment => $labels->{pw_comment} ,
      label => $labels->{password} ,
      order => 6
   };

   $DB->{tables}->{$USERSTABLENAME}->{columns}->{"beschreibung"} = {
      type  => "text",
      label => $labels->{description} ,
      order => 50
   };

   $DB->{tables}->{$USERSTABLENAME}->{columns}->{$DELETEDCOLUMNNAME} = {
      type  => $DELETEDCOLUMNNAME,
      order => 51,
   };

   # Log-table

   $DB->{tables}->{$LOG} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      readonly => 1,
      dbuser => $DBUSER,
      #hidden => 1,
      label => $labels->{action_log} ,
      order => 10000
   };

   $DB->{tables}->{$LOG}->{columns}->{$UNIQIDCOLUMNNAME} =
   {
      type => $UNIQIDCOLUMNNAME,
      order => 1
   };

   $DB->{tables}->{$LOG}->{columns}->{$TIMESTAMP} = {
      type => "datetime",
      showInSelect => 1,
      label => $labels->{time} ,
      order => 2
   };
   $DB->{tables}->{$LOG}->{columns}->{$USER} = {
      type => "text",
      showInSelect => 1,
      label => $labels->{user} ,
      order => 3
   };
   $DB->{tables}->{$LOG}->{columns}->{$TABLE} =
   {
      type => "text",
      showInSelect => 1,
      label => $labels->{table} ,
      order => 4 
   };
   $DB->{tables}->{$LOG}->{columns}->{$ENTRY} =
   {
      type => "text",
      showInSelect => 1,
      hidden => 1,
      label => $labels->{unique_id} ,
      order => 5 
   };
   $DB->{tables}->{$LOG}->{columns}->{$TYP} =
   {
      type => "text",
      showInSelect => 1,
      label => $labels->{type} ,
      order => 6 
   };
   $DB->{tables}->{$LOG}->{columns}->{$DIFF} =
   {
      type => "longtext",
      showInSelect => 1,
      label => $labels->{action} ,
      order => 7 
   };

   
   return $DB;
}
1;
