package ADBGUI::DBDesign_Labels;

use strict; 
use warnings;

our $labels =
{
    # log-table
    action_log   => "Aktions-log",
    time         => "Zeitpunkt",
    user         => "Benutzer",
    table        => "Tabelle",
    type         => "Aktions-Typ",
    action       => "Aktion",

    # Users-table
    username           => "Benutzername",
    change_permission  => "Änderungsberechtigung",
    description        => "Beschreibung",
    superuser          => "read-only Superuser",
    password           => "Passwort",
    pw_comment         => "Das geheime Passwort des Users",

    # ADBGUI Data-types:
    unique_id          => "Eindeutige ID",
    deleted            => 'Gel&ouml;scht',

};


1;
