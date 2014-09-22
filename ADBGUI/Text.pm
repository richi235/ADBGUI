package ADBGUI::Text;

use strict;
use warnings;

sub new {
   my $proto = shift;
   my $self  = {
      ACTIVE_OPERATOR => "X",
      INACTIVE_OPERATOR => "_",
      PASSCHANGED     => "Password changed.\n",
      T_CHANGEPASS     => 'Passwort aendern',
      T_CHANGEPASS_DESC => 'Hier koennen Sie Ihr Passwort aendern.',
      INVALID_FILENAME => 'Invalid filename!',
      INVALID_LOGLINE  => 'Invalid Logline!',
      NO_STATPATH      => 'No STAT-Path!',
      AUSW_UNAVAIL     => 'Auswertung ist nicht verfuegbar.',
      ERROR_DURING     => 'Fehler beim ',
      WRONG_FORMAT     => ' does have wrong format',
      WRONG_SYNTAX     => ' does not have the right syntax',
      IS_MISSING       => ' is missing!',

      # Images
      I_REFRESH        => '/bilder/redo.gif',
      I_FILTER         => '/bilder/find.gif',
      I_ENTRY          => '/bilder/go_to_program_s_website.gif',
       #I_ADD            => '/bilder/add.jpg',
      I_LOGOUT         => '/bilder/exit.gif',
      I_SHOW_ALL       => '/bilder/find.gif',
      I_SHOW_OPENED    => '/bilder/find.gif',
      I_CHANGEPASS     => '/bilder/password.gif',
      I_DISCONNECTED   => '/bilder/i-information.gif',
      I_CONNECTED      => '/bilder/yes.gif',
      I_CONNECT        => '/bilder/disconnect2.gif',
      I_DISCONNECT     => '/bilder/connect2.gif',
      I_CRYPTOCARDASSIGN => '/bilder/connected.jpg',
      I_EDIT           => '/bilder/preferences.png',
      I_DEL            => '/bilder/delete.png',
      I_ASSIGN         => '/bilder/assign.jpg',

      B_CRYPTOCARD     => 'Initialise Cryptocard',
      B_ASSIGN         => 'Assign',
      ADMINISTRATION  => 'Administration',
      ANALYSIS   => 'Auswertung',
      CHANGE      => 'Wechseln',
      CHANGE_LINES    => "Zeilen/Seite",
      DATA      => 'Daten',
      ENTRY_DELETED   => 'Eintrag gel&ouml;scht.',
      ENTRY_UNDELETED   => 'Eintrag wiederhergestellt.',
      FORM_ADD   => 'Hinzuf&uuml;gen',
      FORM_CHANGE   => '&Auml;ndern',
      FOOT_NOTE   => 'ADBGUI V2.0',
      FOUND_ENTRIES   => 'Gefundene Eintr&auml;ge',
      GRAPH      => 'Grafik',
      INSERT      => 'Einf&uuml;gen',
      INSERTED   => 'eingef&uuml;gt',
      MAIN_TITLE   => 'ADBGUI',
      OF_DATA      => 'der Daten',
      PASSWORD   => 'Passwort',
      REFRESH      => 'Aktualisieren',
      REFRESHED   => 'aktualisiert',
      SITE      => 'Seite',
      TABLE      => 'Tabelle',
      USERNAME   => 'Benutzername',
      ACTION          => 'Aktion ausgeloest',
      ACTION_BUSY     => 'Kommando laeuft bereits',
      REFRESHM        => "Waiting %d Seconds to look for a new link. <A HREF='%s'>Manual refresh</A>",
      REDIRECT        => "%s: Redirecting to <A HREF='%s' target='oben'>%s</A><br>",
      NOLINK          => "%s: Currently no link present.",
      LINKTRANSFERED  => "Der Link wurde zur Uebertragung weitergegeben. Sie koennen die Darstellung ".
                          "im Internetbrowser unter <A HREF='%s' target='_blank'>%s</A> erreichen.",
      ASSIGNED        => "Assigned",
      UNASSIGNED      => "Unassigned",
      ORDERBY         => "Order by:",
      MISSING_CONFIG  => "Config is missing!",

      # Fehlermeldungen
      AUTH_FAILED   => 'Authentication failed. Try again.',
      NO_ENTRIES   => 'Keine Eintr&auml;ge.',
      UNKNOWN_TABLE   => 'Unknown table',
      SESSION_RESTORE => 'Sessionrestore failed for SessionID ',
      ERR_SET_FILTER   => 'Fehler beim setzen des Filters.',
      ERR_RETRIEVE   => 'failed.',
      ERR_NO_ID   => 'No id given!',
      ERR_LINES_EXPECTED   => 'Expected one line, but got more than that.',

      # Bestaetigungen
      FILTER_ACTIVE   => 'Inhalte der Tabellen wurden gefiltert.',
      FILTER_RESET    => 'Filter zuruecksetzen',
   
      # Beschriftung der Buttons
      B_ENTRY         => 'home',
      B_ADD      => 'Eintrag hinzuf&uuml;gen',
      B_ANALYSE   => 'zu den Log-Dateien',
      B_CONFIG   => 'Filter konfigurieren',
      B_DEL      => "Löschen",
      B_UNDEL      => "Wiederherstellen",
      I_OVERVIEW   => "/bilder/information.png",
      B_OVERVIEW   => "Overview",
      T_UNDEL      => 'Ja, wirklich wiederherstllen.',
      T_DEL      => #'<img align="absmiddle" src="/bilder/delete.png" alt="Loeschen" title="Loeschen"> 
      'Ja, wirklich loeschen.',
      T_DELNO      => #'<img align="absmiddle" src="/bilder/stop.png" alt="Loeschen" title="Abbruch"
      'Nein, zurück zur &Uuml;bersicht',
      T_UNDELNO      => #'<img align="absmiddle" src="/bilder/stop.png" alt="Loeschen" title="Abbruch"
      'Nein, zurück zur &Uuml;bersicht',
      B_EDIT      => 'Edit',
      B_FILTER   => 'Daten filtern',
      B_RETURN   => 'Zur&uuml;ck zur &Uuml;bersicht',
      B_RETURN_MAIN   => 'Zur&uuml;ck zum Hauptmen&uuml;',
      B_USER_ADMINISTRATION => "Benutzerverwaltung",
      B_USE_FILTER   => 'Filter anwenden',
      B_LOGOUT        => 'log out',
      B_ACTION        => 'Aktionen',
      B_BOSS          => 'BOSS Button - activate changes NOW',
      B_TERM          => 'Close tunnel',
      B_OPEN          => 'Open tunnel',
      B_SHOW_ALL      => "all",
      B_SHOW_OPENED   => "open tunnels",
      B_SCHEDULE      => "schedule",
      B_CHANGEPASS    => "change password",
      WHITELIST       => "ALL",
      
      # Texte der einzelnen Kategorien
      T_ADD      => 'Eintrag hinzuf&uuml;gen',
      T_ADD_DESC   => 'Hier kann der zuvor angezeigten Tabelle ein Eintrag hinzuf&uuml;gen.',
      T_WELCOME   => 'Willkommen bei der Defaultinstallation des <b>A</b>utomatical <b>D</b>atabase <b>G</b>raphical <b>U</b>ser <b>I</b>nterface!',
      T_DELETE   => 'Eintrag l&ouml;schen',
      T_DELETE_DESC   => 'M&ouml;chten Sie diesen Eintrag wirklich l&ouml;schen?',
      T_UNDELETE   => 'Eintrag wiederherstellen',
      T_UNDELETE_DESC   => 'M&ouml;chten Sie diesen Eintrag wirklich wiederherstellen?',
      T_EDIT      => 'Eintrag bearbeiten',
      T_EDIT_DESC   => 'Hier k&ouml;nnen Sie den zuvor angeklickten Eintrag editieren.',
      T_SEARCH   => 'Daten-Filter',
      T_SEARCH_DESC   => 'Hier k&ouml;nnen Sie die zuvor angezeigten Tabellen nach den unten aufgef&uuml;hrten Kriterien filtern. Wenn Sie die Tabelle doch nicht filtern wolle gehen Sie &uuml;ber den Zur&uuml;ck-Schalter Ihres Browser wieder zur vorherigen Seite.',
      T_SECTION   => '&Uuml;bersicht &uuml;ber die Abteilungen',
      T_SECTION_DESC   => 'xxx',
      B_START => 'Startseite'
   };
   bless ($self);
   return $self;
}

1;
