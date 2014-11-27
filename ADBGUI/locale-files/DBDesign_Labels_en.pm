package ADBGUI::DBDesign_Labels;

use strict; 
use warnings;

our $labels =
{
    # log-table
    action_log   => "Action-Log",
    time         => "Time",
    user         => "User",
    table        => "Table",
    type         => "Action-Type",
    action       => "Action",

    # Users-table
    username           => "Username",
    change_permission  => "Change-Permission",
    description        => "Description",
    superuser          => "read-only Superuser",
    password           => "Password",
    pw_comment         => "The User's secret password",
    
    # ADBGUI Data-types:
    unique_id          => "Unique ID",
    deleted            => 'Deleted?',
};



1;
