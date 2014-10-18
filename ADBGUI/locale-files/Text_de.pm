package ADBGUI::Text;

use strict;
use warnings;

sub new 
{
   my $proto = shift;
   my $self  = 
   {
   #### Strings for GUI.pm Start ####    
      ACTIVE_OPERATOR      => "X",
      INACTIVE_OPERATOR    => "_",
      PASSCHANGED          => "Passwort geaendert.\n",
      T_CHANGEPASS         => 'Passwort aendern',
      T_CHANGEPASS_DESC    => 'Hier koennen Sie Ihr Passwort aendern.',
      INVALID_FILENAME     => 'Ungueltiger Dateiname!',
      INVALID_LOGLINE      => 'Ungueltige Log-Zeile',
      NO_STATPATH          => 'Kein STAT-Path vorhanden!',
      AUSW_UNAVAIL         => 'Auswertung ist nicht verfuegbar.',
      ERROR_DURING         => 'Fehler beim ',
      WRONG_FORMAT         => ' hat das falsche Format',
      WRONG_SYNTAX         => ' hat nicht die richtige Syntax',
      IS_MISSING           => ' fehlt',

      # search window
      CRITERION            => 'Kriterium',
      FROM                 => 'Von:',
      TO                   => 'Bis:',
      DAY                  => 'Tag ',
      TIME                 => 'Zeit ',
      ACTIVE               => 'aktiv: ',

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
      REFRESHM        => "Warte %d Sekunden auf einen neuen Link. <A HREF='%s'> Manuell aktualisieren.</A>",
      REDIRECT        => "%s: Leite um auf: <A HREF='%s' target='oben'>%s</A><br>",
      NOLINK          => "%s: Kein Link vorhanden.",
      LINKTRANSFERED  => "Der Link wurde zur Uebertragung weitergegeben. Sie koennen die Darstellung ".
                         "im Internetbrowser unter <A HREF='%s' target='_blank'>%s</A> erreichen.",
      ASSIGNED        => "zugeordnet",
      UNASSIGNED      => "nicht zugeordnet",
      ORDERBY         => "Sortieren nach:",
      MISSING_CONFIG  => "Fehlende Konfiguration(sdatei)",

      # Fehlermeldungen
      AUTH_FAILED          => 'Authentifizierung fehlgeschlafen. Versuchen sie es erneut.',
      NO_ENTRIES           => 'Keine Eintr&auml;ge.',
      UNKNOWN_TABLE        => 'Unbekannte Tabelle',
      SESSION_RESTORE      => 'Wiederherstellen der Sitzung mit folgender ID fehlgeschlagen:',
      ERR_SET_FILTER       => 'Fehler beim setzen des Filters.',
      ERR_RETRIEVE         => 'fehlgeschlagen.',
      ERR_NO_ID            => 'Fehler: Keine ID uebergeben!',
      ERR_LINES_EXPECTED   => 'Eine Zeile Output wurde erwartet, aber deutlich mehr Zeilen kamen.',

      # Bestaetigungen
      FILTER_ACTIVE   => 'Inhalte der Tabellen wurden gefiltert.',
      FILTER_RESET    => 'Filter zuruecksetzen',
   
      # Beschriftung der Buttons
      B_ENTRY           => 'Home',
      B_ADD             => 'Eintrag hinzuf&uuml;gen',
      B_ANALYSE         => 'zu den Log-Dateien',
      B_CONFIG          => 'Filter konfigurieren',
      B_DEL             => 'Löschen',
      B_UNDEL           => 'Wiederherstellen',
      B_OVERVIEW        => 'Uebersicht',
      B_EDIT            => 'Editieren',
      B_FILTER          => 'Daten filtern',
      B_RETURN          => 'Zur&uuml;ck zur &Uuml;bersicht',
      B_RETURN_MAIN     => 'Zur&uuml;ck zum Hauptmen&uuml;',
      B_USER_ADMINISTRATION => "Benutzerverwaltung",
      B_USE_FILTER      => 'Filter anwenden',
      B_LOGOUT          => 'Ausloggen',
      B_ACTION          => 'Aktionen',
      B_BOSS            => 'BOSS Button - Aenderungen JETZT übernehmen',
      B_TERM            => 'Tunnel schließen',
      B_OPEN            => 'Tunnel öffnen',
      B_SHOW_ALL        => 'Alles anzeigen',
      B_SHOW_OPENED     => 'Tunnel öffnen',
      B_SCHEDULE        => 'Plan',
      B_CHANGEPASS      => 'Passwort aendern',
      B_CRYPTOCARD      => 'Cryptocard initialisieren',
      B_ASSIGN          => 'zuweisen',
      B_START           => 'Startseite',

      T_UNDEL      => 'Ja, wirklich wiederherstllen.',
      T_DEL        => 'Ja, wirklich loeschen.',
      T_DELNO      => 'Nein, zurück zur &Uuml;bersicht',
      T_UNDELNO    => 'Nein, zurück zur &Uuml;bersicht',

      WHITELIST    => 'ALLE',
      
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
      B_START       => 'Startseite',
   #### Strings for GUI.pm END #####

   #### Strings from Qooxdoo.pm START ####
      qx  =>
      {
          accessing               =>  "Zugriff auf ",
          context                 =>  "Kontext",
          close                   =>  "Schliessen",
          enable                  =>  "Aktiviere ",
          password                =>  "Passwort",
          unnamed                 =>  "Unbenannt",
          username                =>  "Benutzername",
          live_stats              =>  "Live Statistiken",

          saved_filters           =>  "Gespeicherte Filter: ",
          created_entry           =>  "Erstellter Eintrag",
          first_entry             =>  "Erster Eintrag",
          new_entry               =>  "Neuer Eintrag", 

          # Filter Window
          filter_in               =>  "Filter in ",
          filter_criterion        =>  "Filterkriterium",
          
          # HTML Preview window
          preview_of              =>  "Preview von ",
          of_entry                =>  " von Eintrag ",
          in                      =>  " in ",
          
          # Buttons
          new                     =>  "Neu",
          edit                    =>  "Bearbeiten",
          delete                  =>  "Entfernen",
          filter                  =>  "Filter",
          
          # Error Messages:
          activate_not_configured =>  "Das folgende 'Activate' ist nicht konfiguriert: ",
          application_unavailable =>  "Derzeit ist diese Anwendung nicht verfügbar, bitte versuchen Sie es später wieder.",
          col_info_error          =>  "Fehlerhafte Informationen ueber Tabellen-Spalte: '",
          col_load_error          =>  "Fehler beim Laden folgender Tabellen-Spalte: '",
          context_error           =>  "(Fehler beim Erstellen des Kontexts: ",
          delrow_failed           =>  "Das Löschen dieser Zeile ist fehlgeschlagen.",
          delrow_linex_failed     =>  "Das Löschen folgender Zeile ist fehlgeschlagen: ",
          failed                  =>  "Operation fehlgeschlagen",
          internal_error          =>  "Interner Fehler",
          login_error             =>  "Loginfehler",
          no_crosslink_id         =>  "Fehlende ID für Tabellen-Quer-Verknüpfung\n"
          no_log_data             =>  "Keine Log Daten vorhanden!",
          onSaveEditEntry_error   =>  "Kritischer Fehler beim Ausführen der onSaveEditEntry Funktion aufgetreten.",
          permission_denied       =>  "Fehlende Zugriffsberechtigung",
          popupid_missing         =>  "Die ID für das Popup-Window für folgende Aktion fehlt: ",
          qx_context_error        =>  "Interner Fehler beim Erstellen des folgenden Qooxdoo Contexts:",
          unknown_command         =>  "Unbekannte Aktion: ",
          table_non_modifiable    =>  "Tabelle nicht bearbeitbar",
          wrong_pw_user_combo     =>  "Ungültige Benutzername-Passwort Kombination.",
          
          paths     =>
          {
              qx_building_subdir => "/myproject/build/",
              system_search_png  => "resource/qx/icon/Tango/16/actions/system-search.png",
              list_add           => "resource/qx/icon/Tango/16/actions/list-add.png",
          },
          # potentielle übersetzungskandidaten:

          stats_window =>
          {
              sessions   =>  "Offene Sitzungen: ",
              cur_time   =>  "Aktuelle Uhrzeit in Sekunden nach UNIX-time-epoch:  ",
              refresh    =>  "Aktualisieren"

          },    
              
      },

   };

   bless ($self);
   return $self;
}

1;
