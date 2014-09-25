package ADBGUI::Text;

use strict;
use warnings;

sub new 
{
   my $proto = shift;
   my $self  = 
   {
      ACTIVE_OPERATOR      => "X",
      INACTIVE_OPERATOR    => "_",
      PASSCHANGED          => "Password changed.\n",
      T_CHANGEPASS         => 'Passwort aendern',
      T_CHANGEPASS_DESC    => 'Hier koennen Sie Ihr Passwort aendern.',
      INVALID_FILENAME     => 'Invalid filename!',
      INVALID_LOGLINE      => 'Invalid Logline!',
      NO_STATPATH          => 'No STAT-Path!',
      AUSW_UNAVAIL         => 'Auswertung ist nicht verfuegbar.',
      ERROR_DURING         => 'Fehler beim ',
      WRONG_FORMAT         => ' does have wrong format',
      WRONG_SYNTAX         => ' does not have the right syntax',
      IS_MISSING           => ' is missing!',


      ADMINISTRATION  => 'Administration',
      ANALYSIS        => 'Auswertung',
      CHANGE          => 'Wechseln',
      CHANGE_LINES    => "Zeilen/Seite",
      DATA            => 'Daten',
      ENTRY_DELETED   => 'Eintrag gel&ouml;scht.',
      ENTRY_UNDELETED => 'Eintrag wiederhergestellt.',
      FORM_ADD        => 'Hinzuf&uuml;gen',
      FORM_CHANGE     => '&Auml;ndern',
      FOOT_NOTE       => 'ADBGUI V2.0',
      FOUND_ENTRIES   => 'Gefundene Eintr&auml;ge',
      GRAPH           => 'Grafik',
      INSERT          => 'Einf&uuml;gen',
      INSERTED        => 'eingef&uuml;gt',
      MAIN_TITLE      => 'ADBGUI',
      OF_DATA         => 'der Daten',
      PASSWORD        => 'Passwort',
      REFRESH         => 'Aktualisieren',
      REFRESHED       => 'aktualisiert',
      SITE            => 'Seite',
      TABLE           => 'Tabelle',
      USERNAME        => 'Benutzername',
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
      AUTH_FAILED          => 'Authentication failed. Try again.',
      NO_ENTRIES           => 'Keine Eintr&auml;ge.',
      UNKNOWN_TABLE        => 'Unknown table',
      SESSION_RESTORE      => 'Sessionrestore failed for SessionID ',
      ERR_SET_FILTER       => 'Fehler beim setzen des Filters.',
      ERR_RETRIEVE         => 'failed.',
      ERR_NO_ID            => 'No id given!',
      ERR_LINES_EXPECTED   => 'Expected one line, but got more than that.',

      # Bestaetigungen
      FILTER_ACTIVE   => 'Inhalte der Tabellen wurden gefiltert.',
      FILTER_RESET    => 'Filter zuruecksetzen',
   
      # Beschriftung der Buttons
      B_ENTRY           => 'home',
      B_ADD             => 'Eintrag hinzuf&uuml;gen',
      B_ANALYSE         => 'zu den Log-Dateien',
      B_CONFIG          => 'Filter konfigurieren',
      B_DEL             => "Löschen",
      B_UNDEL           => "Wiederherstellen",
      B_OVERVIEW        => "Overview",
      B_EDIT            => 'Edit',
      B_FILTER          => 'Daten filtern',
      B_RETURN          => 'Zur&uuml;ck zur &Uuml;bersicht',
      B_RETURN_MAIN     => 'Zur&uuml;ck zum Hauptmen&uuml;',
      B_USER_ADMINISTRATION => "Benutzerverwaltung",
      B_USE_FILTER      => 'Filter anwenden',
      B_LOGOUT          => 'log out',
      B_ACTION          => 'Aktionen',
      B_BOSS            => 'BOSS Button - activate changes NOW',
      B_TERM            => 'Close tunnel',
      B_OPEN            => 'Open tunnel',
      B_SHOW_ALL        => "all",
      B_SHOW_OPENED     => "open tunnels",
      B_SCHEDULE        => "schedule",
      B_CHANGEPASS      => "change password",
      B_CRYPTOCARD      => 'Initialise Cryptocard',
      B_ASSIGN          => 'Assign',

      T_UNDEL      => 'Ja, wirklich wiederherstllen.',
      T_DEL        => 'Ja, wirklich loeschen.',
      T_DELNO      => 'Nein, zurück zur &Uuml;bersicht',
      T_UNDELNO    => 'Nein, zurück zur &Uuml;bersicht',

      WHITELIST    => "ALL",
      
      # Texte der einzelnen Kategorien
      T_ADD         => 'Eintrag hinzuf&uuml;gen',
      T_ADD_DESC    => 'Hier kann der zuvor angezeigten Tabelle ein Eintrag hinzuf&uuml;gen.',
      T_WELCOME     => 'Willkommen bei der Defaultinstallation des <b>A</b>utomatical <b>D</b>atabase <b>G</b>raphical <b>U</b>ser <b>I</b>nterface!',
      T_DELETE      => 'Eintrag l&ouml;schen',
      T_DELETE_DESC => 'M&ouml;chten Sie diesen Eintrag wirklich l&ouml;schen?',
      T_UNDELETE    => 'Eintrag wiederherstellen',
      T_UNDELETE_DESC   => 'M&ouml;chten Sie diesen Eintrag wirklich wiederherstellen?',
      T_EDIT        => 'Eintrag bearbeiten',
      T_EDIT_DESC   => 'Hier k&ouml;nnen Sie den zuvor angeklickten Eintrag editieren.',
      T_SEARCH      => 'Daten-Filter',
      T_SEARCH_DESC => 'Hier k&ouml;nnen Sie die zuvor angezeigten Tabellen nach den unten aufgef&uuml;hrten Kriterien filtern. Wenn Sie die Tabelle doch nicht filtern wolle gehen Sie &uuml;ber den Zur&uuml;ck-Schalter Ihres Browser wieder zur vorherigen Seite.',
      T_SECTION     => '&Uuml;bersicht &uuml;ber die Abteilungen',
      T_SECTION_DES => 'xxx',
      B_START       => 'Startseite'
   };

   bless ($self);
   return $self;
}

1;
