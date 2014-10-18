package ADBGUI::Text;

use strict;
use warnings;

sub new 
{
   my $proto = shift;
   my $self  = 
   {
   ### Strings for GUI.pm START ###    
      ACTIVE_OPERATOR      => 'X',
      INACTIVE_OPERATOR    => '_',
      PASSCHANGED          => "Password changed.\n",
      T_CHANGEPASS         => 'change password',
      T_CHANGEPASS_DESC    => 'Here you can change your password',
      INVALID_FILENAME     => 'Invalid filename!',
      INVALID_LOGLINE      => 'Invalid Logline!',
      NO_STATPATH          => 'No STAT-Path!',
      AUSW_UNAVAIL         => 'evaluation is not available',
      ERROR_DURING         => 'Error during: ',
      WRONG_FORMAT         => ' does have wrong format',
      WRONG_SYNTAX         => ' does not have the right syntax',
      IS_MISSING           => ' is missing!',

      # search window
      CRITERION            => 'Criterion',
      FROM                 => 'From:',
      TO                   => 'To:',
      DAY                  => 'Day ',
      TIME                 => 'Time ',
      ACTIVE               => 'active: ',

      ADMINISTRATION  => 'Administration',
      ANALYSIS        => 'Analysis',
      CHANGE          => 'Change',
      CHANGE_LINES    => 'line/page',
      DATA            => 'Data',
      ENTRY_DELETED   => 'Entry is deleted',
      ENTRY_UNDELETED => 'restored Entry',
      FORM_ADD        => 'Add',
      FORM_CHANGE     => 'change',
      FOOT_NOTE       => 'ADBGUI V2.0',
      FOUND_ENTRIES   => 'Found Entries: ',
      GRAPH           => 'Grafic',
      INSERT          => 'insert',
      INSERTED        => 'inserted',
      MAIN_TITLE      => 'ADBGUI',
      OF_DATA         => 'of Data',
      PASSWORD        => 'password',
      REFRESH         => 'refresh',
      REFRESHED       => 'refreshed',
      SITE            => 'site',
      TABLE           => 'table',
      USERNAME        => 'username',
      ACTION          => 'Action triggered',
      ACTION_BUSY     => 'Command already running',
      REFRESHM        => "Waiting %d Seconds to look for a new link. <A HREF='%s'>Manual refresh</A>",
      REDIRECT        => "%s: Redirecting to <A HREF='%s' target='oben'>%s</A><br>",
      NOLINK          => "%s: Currently no link present.",
      LINKTRANSFERED  => "The content has been transfered. You can view the content at: ".
                         "<A HREF='%s' target='_blank'>%s</A>",
      ASSIGNED        => "Assigned",
      UNASSIGNED      => "Unassigned",
      ORDERBY         => "Order by:",
      MISSING_CONFIG  => "Config is missing!",

      # Error Messages:
      AUTH_FAILED          => 'Authentication failed. Try again.',
      NO_ENTRIES           => 'No entries.',
      UNKNOWN_TABLE        => 'Unknown table',
      SESSION_RESTORE      => 'Sessionrestore failed for SessionID ',
      ERR_SET_FILTER       => 'Error while setting filter',
      ERR_RETRIEVE         => 'failed.',
      ERR_NO_ID            => 'No id given!',
      ERR_LINES_EXPECTED   => 'Expected one line, but got more than that.',

      # Confirmation Messages
      FILTER_ACTIVE   => 'Displayed table rows are filtered.',
      FILTER_RESET    => 'reset filter',
   
      # Button labels
      B_ENTRY           => 'home',
      B_ADD             => 'Add entry',
      B_ANALYSE         => 'to the log files',
      B_CONFIG          => 'configure Filter',
      B_DEL             => 'delete',
      B_UNDEL           => 'undelete',
      B_OVERVIEW        => 'Overview',
      B_EDIT            => 'Edit',
      B_FILTER          => 'filter data',
      B_RETURN          => 'Back to overview',
      B_RETURN_MAIN     => 'Back to main menu',
      B_USER_ADMINISTRATION => 'User Management',
      B_USE_FILTER      => 'apply filter',
      B_LOGOUT          => 'log out',
      B_ACTION          => 'Actions',
      B_BOSS            => 'BOSS Button - activate changes NOW',
      B_TERM            => 'Close tunnel',
      B_OPEN            => 'Open tunnel',
      B_SHOW_ALL        => 'all',
      B_SHOW_OPENED     => 'open tunnels',
      B_SCHEDULE        => 'schedule',
      B_CHANGEPASS      => 'change password',
      B_CRYPTOCARD      => 'Initialise Cryptocard',
      B_ASSIGN          => 'Assign',
      B_START           => 'Startpage',

      T_UNDEL           => 'Yes, really undelete',
      T_DEL             => 'Yes, really delete',
      T_DELNO           => 'No, back to Overview',
      T_UNDELNO         => 'No, back to Overview',

      WHITELIST         => "ALL",
      
      # Text for the individual categories
      T_ADD             => 'add entry',
      T_ADD_DESC        => 'here you can add an entry to the table previosly displayed',
      T_WELCOME         => 'Welcome to the default installation of the <b>A</b>utomatical <b>D</b>atabase <b>G</b>raphical <b>U</b>ser <b>I</b>nterface!',
      T_DELETE          => 'delete entry',
      T_DELETE_DESC     => 'Do you really want to delete this entry?',
      T_UNDELETE        => 'Undelete entry',
      T_UNDELETE_DESC   => 'Do you really want to undelete this entry?',
      T_EDIT            => 'Edit entry',
      T_EDIT_DESC       => 'Here you can edit the previously selected entry.',
      T_SEARCH          => 'Data filter',
      T_SEARCH_DESC     => 'Here you can filter the previously displayed tables with the criteria shown below.' . 
                           'If you want to get back to the previous Page, without filtering anything, use the "back" button of your browser.'  ,
      T_SECTION         => 'Section Overview',
      T_SECTION_DES     => 'xxx',
   ### Strings for GUI.pm END ###

   #### Strings from Qooxdoo.pm START ####
      qx  =>
      {
          accessing               =>  "Access to ",
          context                 =>  "context",
          enable                  =>  "Enable ",
          password                =>  "Password",
          unnamed                 =>  "Unnamed",
          username                =>  "Username",
          live_stats              =>  "Live Statistics",

          saved_filters           =>  "Saved filters: ",
          first_entry             =>  "First Entry",
          new_entry               =>  "New Entry", 

          # Buttons
          new                     =>  "New",
          edit                    =>  "Change",
          delete                  =>  "Delete",
          filter                  =>  "Filter",
          
          # Error Messages:
          activate_not_configured =>  "The following 'Activate' is not configured: ",
          application_unavailable =>  "Currently this application is not available. Please try again later.",
          col_info_error          =>  "Got corrupted information about following column: '",
          context_error           =>  "(Error while creating Context: ",
          failed                  =>  "FAILED",
          internal_error          =>  "Internal error",
          no_log_data             =>  "No Log Data existing",
          permission_denied       =>  "No access permission",
          popupid_missing         =>  "Id of popup-window for the following action is missing: ",
          qx_context_error        =>  "Internal Error while creating the following Qooxdoo Contexd: ",
          col_load_error          =>  "Error while loading the following column: '",
          unknown_command         =>  "Unknown command/action: ",
          table_non_modifiable    =>  "Table not modifiable.",
          delrow_failed           =>  "Deleting this line failed.",
          delrow_linex_failed     =>  "Deleting the following line failed: ",
          login_error             =>  "Login-error",
          wrong_pw_user_combo     =>  "Invalid username or password.",
          no_crosslink_id         =>  "No crosslink id\n"
          
          paths     =>
          {
              qx_building_subdir => "/myproject/build/",
              system_search_png  => "resource/qx/icon/Tango/16/actions/system-search.png",
              list_add           => "resource/qx/icon/Tango/16/actions/list-add.png",
          },
          # potentielle übersetzungskandidaten:

          stats_window =>
          {
              sessions   =>  "Open sessions: ",
              cur_time   =>  "Current time in seconds after UNIX-epoch:  ",
              refresh    =>  "Refresh"

          },

      },

   };

   bless ($self);
   return $self;
}

1;
