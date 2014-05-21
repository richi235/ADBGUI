package Example::DBDesign;

use strict;
use warnings;
use ADBGUI::BasicVariables; # fuer $UNIQIDCOLUMNNAME
use ADBGUI::DBDesign; # fuer $RIGHTS, $DBUSER 

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

sub getDB {
   my $self = shift;
   my $DB = $self->SUPER::getDB() || {};
   $DB->{menu}->{"attr"}->{text} = "Verschiedene Attribute";

#######################################################################
##                                                                    #     
## In Tabelle "tabelle_01" werden Attribute der Tabelle vorgestellt   #
##                                                                    #
#######################################################################

 $DB->{tables}->{"tabelle_01"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 5,
      label => "Tabellenattribute 1",

      crossShowInSelections => "exp_text1",  # noch kein Effekt gefunden
      menuname => "attr",                    # Ein Menue wird eingefuegt, der Menue-Name muss vorher definiert werden
      nolog => 1,                            # Eintraege dieser Tabelle werden nicht geloggt
      icon => 'bilder/edit.png',             # Im Menue-Eintrag und im Fester-Header wird das Icon angezeigt

      infotext => "Infotext der bei der Tabellen Uebersicht angezeigt wird.",
      infotextedit => "Infotext Edit Wo?",

#      listimagedefault => 'bilder/edit.png', # Anzeige nicht ersichtlich
#      listimagecolumn => 'bilder/edit.png',  # Anzeige nicht ersichtlich
#      listtextcolumn => "Listentext",         # Wann wird das angezeigt

      orderby => [$NAMECOLUMNNAME.$TSEP.$NAMECOLUMNNAME],
#      prioorderby => # wie orderby wird immer dannach sortiert 

      realdelete => 0,                        # echtes löschen, wie kontrollieren?

#### Qooxdoo Attribute ####
      qxeditwidth => 1000, # breite des Fensters beim Erstellen oder Ändern eines Eintrages
      qxeditheight => 200, # höhe des Fensters beim erstellen oder Ändern eines Eintrages
      qxwidth => 800,   # breite der Tabelle beim Öffnen
      qxheight => 300,   # höhe der Tabelle beim Öffnen
      qxopenfilewidth => 100,
      qxopenfileheight => 100,
      qxactivatewidth => 100,
      qxactivateheight => 100,
#      qxhidden => 1,  # die Tabelle wird nicht im Menue angezeigt.
   };

  $DB->{tables}->{"tabelle_01"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_01"}->{columns}->{"exp_text1"} = {
      type => "text",
      label => "text 1",
      order => 2,            
   };

   $DB->{tables}->{"tabelle_01"}->{columns}->{"exp_text2"} = {
      type => "text",
      label => "text 2",
      order => 3,            
   };

   $DB->{tables}->{"tabelle_01"}->{columns}->{"exp_delColName"} = {
      type => $DELETEDCOLUMNNAME,
      label => "Gelöschter Spaltenname",
      order => 4,            
   };


#######################################################################
##                                                                    #     
## In Tabelle "tabelle_1" alle Werte des Attributes type vorgestellt  #
##                                                                    #
#######################################################################


  $DB->{tables}->{"tabelle_1"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 11,
      menuname => "attr",
      label => "Alle Einabetypen",
   };


  $DB->{tables}->{"tabelle_1"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 0,
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_virtual"} = {
      type => "virtual",
      label => "Virtual ",
      default => "Type Virtual wird als Überschrift verwendet",
      order => 1,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_text"} = {
      type => "text",
      label => "Kurzer Text ",
      order => 2,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_longtext"} = {
      type => "longtext",
      label => "Langer Text",
      order => 3,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_htmltext"} = {
      type => "htmltext",
      label => "Html Text",
      order => 4,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_password"} = {
      type => "password",
      label => "Password",
      order => 5,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_boolean"} = {
      type => "boolean",
      label => "Boolean - Wahrheitswert",
      order => 6,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_number"} = {
      type => "number",
      label => "Eine Zahl Int(32)",
      order => 7,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_longnumber"} = {
      type => "longnumber",
      label => "Eine große Zahl Int(64)",
      order => 8,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_datavolume"} = {
      type => "datavolume",
      label => "Datavolume",
      order => 9,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_image"} = {
      type => "image",
      label => "Ein Bild - evtl. noch nicht einsatzbereit",
      order => 10,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_date"} = {
      type => "date",
      label => "Datum",
      order => 11,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_datetime"} = {
      type => "datetime",
      label => "Datum und Zeit",
      order => 12,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_inet"} = {
      type => "inet",
      label => "Inet",
      order => 13,            
   };

   $DB->{tables}->{"tabelle_1"}->{columns}->{"exp_deletedcolumnname"} = {
      type => $DELETEDCOLUMNNAME,
      label => "Gelöschter Spaltenname",
      order => 14,            
   };

###########################################################################
##                                                                        #     
## In Tabelle "tabelle_2" werden die Attribute einer Spalte vorgestellt   #
##                                                                        #
###########################################################################

  $DB->{tables}->{"tabelle_2"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      menuname => "attr",
      order => 12,
      label => "Eigenschaften",
   };


  $DB->{tables}->{"tabelle_2"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_default"} = {
      type => "text",
      label => "Default Eintrag",
      default => "Das steht defaultmäßig hier",
      order => 1,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_nochange"} = {
      type => "text",
      label => "Nochange",
      nochange => 1,
      order => 2,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_notnull"} = {
      type => "text",
      label => "Notnull",
      notnull => 1,
      order => 3,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_writeonly"} = {
      type => "text",
      label => "Writeonly",
      writeonly => 1,
      order => 4,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_readonly"} = {
      type => "text",
      label => "Readonly",
      readonly => 1,
      default => "Das kann man nur lesen",
      order => 5,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_newonly"} = {
      type => "text",
      label => "Newonly",
      newonly => 1,
      default => "kann nur am Anfang belegt werden",
      order => 6,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_help"} = {
      type => "longtext",
      label => "Help",
      help => "Das ist ein Hilfetext",
      default => "kann nur am Anfang belegt werden",
      order => 7,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_hidden"} = {
      type => "text",
      label => "Hidden",
      hidden => 1,
      default => "Es wird nicht angezeigt",
      selectAlsoIfHidden => 1,
      order => 8,            
   };

   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_showInSelect"} = {
      type => "text",
      label => "ShowInSelect",
      showInSelect => 1,
      order => 9,            
   };

 # Eine Zahl mit oder ohne Nachkommastellen. Ob mit Komma oder Punkt getrennt wird ist hier egal.)
   $DB->{tables}->{"tabelle_2"}->{columns}->{"exp_unitSyntax"} = {
      type => "text",
      label => "Unit mit Syntaxcheck",
      unit => "xx.xx oder yy,yy",
      syntaxcheck => '^[\d]+([,.]\d+)?$',
      order => 10,            
   };

#############################################################################
##                                                                          #     
## In Tabelle "tabelle_3" werden Qooxdoo-Attribute der Spalte vorgestellt   #
##                                                                          #
#############################################################################


  $DB->{tables}->{"tabelle_3"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      menuname => "attr",
      order => 13,
      label => "qx-Attribute",
   };

  $DB->{tables}->{"tabelle_3"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_normal"} = {
      type => "text",
      label => "Ohne qx Angabe",
      order => 2,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxminsize"} = {
      type => "text",
      label => "qxminsize",
      default => "Gibt die Mindestbreite in der Tabellenuebersicht an.",
      qxminsize => 50,
      order => 3,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxmaxsize"} = {
      type => "text",
      label => "qxmaxsize",
      default => "Gibt die Maximalebreite in der Tabellenuebersicht an.",
      qxmaxsize => 50,
      order => 4,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxwidth"} = {
      type => "longtext",
      label => "qxwidth",
      qxwidth => 500,
      order => 5,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxheight"} = {
      type => "longtext",
      label => "qxheight",
      qxheight => 1000,
      order => 6,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxdefaultsize"} = {
      type => "text",
      label => "qxdefaultsize",
      default => "Legt die Breite fest.",
      qxdefaultsize => 100,
      order => 7,            
   };

   $DB->{tables}->{"tabelle_3"}->{columns}->{"exp_qxtype"} = {
      type => "text",
      label => "qxtype",
      qxtype => "html",
      order => 8,            
   };

######################################################
##                                                   #     
## Beispiel zum Erstellen einer einfachen Tabelle    #
##                                                   #
######################################################

## Einfache Tabelle: Farben ##

 $DB->{tables}->{"tabelle_4"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 14,
      label => "Einfache Tabelle (Farben)",
   };

  $DB->{tables}->{"tabelle_4"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_4"}->{columns}->{"exp_farbe"} = {
      type => "text",
      label => "Farbe",
      showInSelect => 1,
      order => 2,            
   };

   $DB->{tables}->{"tabelle_4"}->{columns}->{"exp_hexwert"} = {
      type => "text",
      label => "#Wert",
      showInSelect => 0,
      order => 3,            
   };

## Einfache Tabelle: Blumen ##

 $DB->{tables}->{"tabelle_6"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 16,
      label => "Einfache Tabelle (Blumen)",
   };

  $DB->{tables}->{"tabelle_6"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_6"}->{columns}->{"exp_name"} = {
      type => "text",
      label => "Blumenname",
      showInSelect => 1,
      order => 2,            
   };

   $DB->{tables}->{"tabelle_6"}->{columns}->{"exp_standort"} = {
      type => "text",
      label => "Standort",
      showInSelect => 0,
      order => 3,            
   };

######################################################
##                                                   #     
## Beispiel zum Erstellen einer 1:n Tabelle          #
##                                                   #
######################################################


## Personen werden ihre Lieblingsfarben zugeordnet  ##
## Greift auf die Tabelle Farben (tabelle_4) zu     ##


 $DB->{tables}->{"tabelle_5"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 15,
      label => "1:n Tabelle (Lieblingsfarben)",
   };


  $DB->{tables}->{"tabelle_5"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_5"}->{columns}->{"expVorname"} = {
      type => "text",
      label => "Vorname",
      order => 2,            
   };

   $DB->{tables}->{"tabelle_5"}->{columns}->{"expNachname"} = {
      type => "text",
      label => "Nachname",
      order => 3,            
   };

   $DB->{tables}->{"tabelle_5"}->{columns}->{"tabelle_4_".$UNIQIDCOLUMNNAME} = {
      type => "number",
      label => "Farbauswahl",
      order => 4,            
   };

######################################################
##                                                   #     
## Beispiel zum Erstellen einer n:m Tabelle          #
##                                                   #
######################################################


## Tabelle Verknuepft Blumen (tabelle_6) mit Farben (tabelle_4)  ##
## Ein weiteres Attribut wird ausserdem eingeführt               ##

 $DB->{tables}->{"tabelle_7"} = {
      primarykey => [$UNIQIDCOLUMNNAME],
      rights => $RIGHTS,
      dbuser => $DBUSER,
      order => 17,
      label => "n:m Tabelle (Farben-Blumen)",
      infotext => "Hiffetext Farben zu Blumen zuordnen - infotext",
   };


  $DB->{tables}->{"tabelle_7"}->{columns}->{$UNIQIDCOLUMNNAME} = {
      type => $UNIQIDCOLUMNNAME,
      order => 1,
   };

   $DB->{tables}->{"tabelle_7"}->{columns}->{"expVerk"} = {
      type => "text",
      label => "Verknuepfung",
      order => 2,            
   };

   $DB->{tables}->{"tabelle_7"}->{columns}->{"tabelle_4_".$UNIQIDCOLUMNNAME} = {
      type => "number",
      label => "Farbenauswahl",
      order => 3,            
   };

   $DB->{tables}->{"tabelle_7"}->{columns}->{"tabelle_6_".$UNIQIDCOLUMNNAME} = {
      type => "number",
      label => "Blumenauswahl",
      order => 4,            
   };



   return $DB;
}

1;
