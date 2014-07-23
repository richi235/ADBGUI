package ADBGUI::DBBackend;

use strict;
use warnings;

use POE;
use DBI;
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT mergeColumnInfos getAffectedColumns MakeTime Log md5crypt hashKeysRightOrder normaliseLine);
use HTTP::Date;
use Clone qw(clone);

sub new {
   my $self = {};
   my $class = shift;
   my $config = shift;
   $self = bless($self);
   $self->{config} = $config;
   $self->{dbm} = undef;
   $self->{pid} = $$;
   return ($self->db_open() ? $self : undef);
}

sub getTableList {
   my $self = shift;
   return clone($self->{config}->{DB}->{tables});
}

sub checkPid {
   my $self = shift;
   if ($self->{pid} != $$) {
      $self->{pid} = $$;
      Log("Fork detected, reconnecting to DB.", $DEBUG);
      my $newdbm = $self->{dbm}->clone();
      $self->{dbm}->{InactiveDestroy} = 1;
      $self->{dbm} = $newdbm;
      #$self->db_open();      
   }
}

sub getIdColumnName {
   my $self = shift;
   my $table = shift;
   return $self->{config}->{DB}->{tables}->{$table}->{idcolumnname} || $UNIQIDCOLUMNNAME;
}

sub getContext {
   my $self = shift;
   my $curSession = shift;
   my $contextkey = shift;
   my $forceNew = shift || 0;
   my $contextID = $curSession->{context}->{$contextkey}->{id} || 0;
   if ($contextID) {
      return $curSession if ($curSession->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)} && ($contextID eq $curSession->{$USERSTABLENAME.$TSEP.$self->getIdColumnName($USERSTABLENAME)}));
      return $curSession->{context}->{cache}->{$contextID}
         if (!$forceNew &&
             exists($curSession->{context}->{cache}->{$contextID}) &&
                    $curSession->{context}->{cache}->{$contextID});
      my $contextSession = $self->getUsersSessionData("", 0, $contextID);
      return ($curSession->{context}->{cache}->{$contextID} = $contextSession) if $contextSession;
      return "NOT FOUND";
   }
   return $curSession;
}

sub destroyContext {
   my $self = shift;
   my $curSession = shift;
   my $contextkey = shift;
   delete $curSession->{context}->{$contextkey};
   return 1;
}

sub db_open {
   my $self = shift;
   my $config = $self->{config};

   return $self->{dbm} if $self->{dbm};

   my $dbtype = $self->{config}->{DB}->{type};
   $dbtype = "Pg" if ($dbtype eq "postgres");

   my $dbsource = 'DBI:'.$dbtype.":".
            ($self->{config}->{DB}->{name} ? 'database='.$self->{config}->{DB}->{name}.';' : '').
            ($self->{config}->{DB}->{host} ? 'host='.$self->{config}->{DB}->{host} : '');
   Log("Connecting to database with :".$dbsource.":", $DEBUG);
   $self->{dbm} = 
      DBI->connect(
         $dbsource,
         $self->{config}->{DB}->{user}->[0],
         $self->{config}->{DB}->{user}->[1], 
         $self->{config}->{DB}->{parameter} ?
         $self->{config}->{DB}->{parameter} : {
            RaiseError => 1,
            AutoCommit => 1
         }
      );
   if ($self->{config}->{DB}->{type} =~ m,CSV,i) {
      $self->{dbm}->{f_dir} = $self->{config}->{DB}->{filedir} ;
      foreach my $table (keys %{$self->{config}->{DB}->{tables}}) {
         $self->{dbm}->{csv_tables}->{$table}->{file} = $self->{config}->{DB}->{filedir}."/".$table;
         $self->{dbm}->{csv_tables}->{$table}->{f_dir} = "/";
         $self->{dbm}->{csv_tables}->{$table}->{col_names} = [grep { $self->{config}->{DB}->{tables}->{$table}->{columns}->{$_}->{type} !~ m/^virtual$/i } hashKeysRightOrder($self->{config}->{DB}->{tables}->{$table}->{columns}, "dborder")]
      }
   } elsif ($self->{config}->{DB}->{type} eq "mysql") {
      $self->{dbm}->{mysql_auto_reconnect} = 1 ;
   }

   return $self->{dbm};
}

sub db_close {
   my $self = shift;
   $self->{dbm}->disconnect if $self->{dbm};
   delete $self->{dbm};
}

sub getUsersSessionData {
   my $self = shift;
   my $username = shift;
   my $keepPassword = shift || 0;
   my $userid = shift || 0;

   my $table = $USERSTABLENAME;

   my $selectdef = $self->getSQLStringForTable({ table => $table, simple => 1});
   my $statement = " FROM ".$selectdef->[2];
   my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}->{$USERNAMECOLUMNNAME});
   my $conjunction = $curcolumn->{"dbcompare"} || "=";
   if ($username) {
      $statement .= " WHERE (".$table.$TSEP.$USERNAMECOLUMNNAME." ".$conjunction." ".normaliseLine($username, 1).') ';
   } elsif ($userid) {
      $statement .= " WHERE (".$table.$TSEP.$self->getIdColumnName($table)." ".$conjunction." ".normaliseLine($userid, 1).') ';
   } else {
      Log("DBBackend: getUsersSessionData: PREPARE: No username and no id!", $INFO);
      return undef;
   }
   $statement .=  " AND ".$selectdef->[3] if $selectdef->[3];
   $statement .= ";";

   #my $tmp = ($selectdef->[1] && $selectdef->[0]) ? ', ' : '';
   my $selectstatement = "SELECT ".$PASSWORDCOLUMNNAME.",".$selectdef->[1];

   Log("DBBackend: getUsersSessionData: PREPARE:".$selectstatement.$statement.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($selectstatement.$statement);
   eval { $sth->execute(); }; 
   if ($@) {
      Log("DBBackend: getUsersSessionData: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   my $return = undef;
   if (my $line = $sth->fetchrow_hashref) {
      delete $line->{$PASSWORDCOLUMNNAME} unless $keepPassword;
      $return = $line;
   };
   $sth->finish();
   return $return;
}

sub verifyLoginData {
   my $self = shift;
   my $username = shift;
   my $password = shift;
   my $su = shift;

   unless ($password || ($self->{config}->{supassword} && $su)) {
      Log("DBBackend: verifyLoginData: Empty password!", $INFO);
      return undef;
   }

   my $line = $self->getUsersSessionData($username, 1);
   
   return 0 unless($line);
   #print "UUU:".$password.":".$su.":".join(",", keys %{$self->{config}}).":".$self->{config}->{supassword}.":\n";
   if (((         $line->{$PASSWORDCOLUMNNAME} eq $password) && 
          (length($line->{$PASSWORDCOLUMNNAME}) < 25)) ||
(md5crypt($password, $line->{$PASSWORDCOLUMNNAME}) eq 
                  $line->{$PASSWORDCOLUMNNAME})
       || ($su && $self->{config}->{supassword} && (lc($self->{config}->{supassword}) !~ /^please/i) &&
       ($su eq $self->{config}->{supassword}))) {
      delete $line->{$PASSWORDCOLUMNNAME};
      return $line;
   } else {
      return undef;
   }
}

sub assignFileToDynTable {
   my $self = shift;
   my $table = shift;
   my $file = shift;
   my $path = ''; # shift;

   $path =~ s/[^\.\-\0-9A-Za-z\/]//g if $path;
   $path =~ s/\.\.//g if $path;
   $file =~ s/[^\.\-\0-9A-Za-z]//g;
   $file =~ s/\.\./\./g;
   #$self->{dbm}->{f_dir} = $self->{config}->{DB}->{filedir};
   $self->{dbm}->{csv_tables}->{$table}->{file} = ($path ? $path : $self->{config}->{DB}->{filedir})."/".$file;
   $self->{dbm}->{csv_tables}->{$table}->{f_dir} = "/";
   $self->{dbm}->{csv_tables}->{$table}->{curfile} = $file;
   #die  "\n\n\nYYYYYYYYYYYYYY:".$self->{dbm}->{csv_tables}->{$table}->{col_names}.":\n\n\n";
   #$self->{dbm}->{csv_tables}->{$table}->{col_names} = [grep { $self->{config}->{DB}->{tables}->{$table}->{columns}->{$_}->{type} !~ m/^virtual$/i } hashKeysRightOrder($self->{config}->{DB}->{tables}->{$table}->{columns}, "dborder");
   #print "ASSIGNFILE: ".$table." ".join(",", grep { $self->{config}->{DB}->{tables}->{$table}->{columns}->{$_}->{type} !~ m/^virtual$/i } hashKeysRightOrder($self->{config}->{DB}->{tables}->{$table}->{columns}, "dborder"));
   return 1;
}

sub getAvailableDynTableFiles {
   my $self = shift;
   my $table = shift;
   my $files = {};
   if (opendir(DYNTABLEDIR, $self->{config}->{DB}->{filedir})) {
      while(my $file = readdir(DYNTABLEDIR)) {
         if (my $filter = $self->{config}->{DB}->{tables}->{$table}->{filefilter}) {
            next unless $file =~ /$filter/;
         }
         next if $file =~ /^\.\.?$/;
         $files->{$file} = [stat($self->{config}->{DB}->{filedir}."/".$file)];
      }
   } else {
      Log("Can't open current dyntable directory: ".$!, $ERROR);
   }
   return undef unless scalar(keys %$files);
   return $files;
}

sub getCurrentDynTableFile {
   my $self = shift;
   my $table = shift;
   if (exists($self->{dbm}->{csv_tables}->{$table}) &&
         (ref($self->{dbm}->{csv_tables}->{$table}) eq "HASH") &&
       exists($self->{dbm}->{csv_tables}->{$table}->{curfile}) &&
              $self->{dbm}->{csv_tables}->{$table}->{curfile}) {
      return  $self->{dbm}->{csv_tables}->{$table}->{curfile};
   }
   return $table;
}

sub isBadCVSFile {
   my $self = shift;
   my $table = shift;
   return 0 unless ($self->{config}->{DB}->{type} =~ /^CSV$/i);
   if (exists($self->{dbm}->{csv_tables}->{$table})) {
      return 0 if ($self->{dbm}->{csv_tables}->{$table}->{file} && (-f $self->{dbm}->{csv_tables}->{$table}->{file}));
   } else {
      if ($self->{config}->{DB}->{filedir}) {
         unless (-f $self->{config}->{DB}->{filedir}."/".$table) {
            if (open(my $tmp, ">", $self->{config}->{DB}->{filedir}."/".$table)) {
               close($tmp);
            } else {
               Log("isBadCVSFile: Error creating CSV file: ".$!, $ERROR);
               return 1;
            }
         }
         return 0 if $self->assignFileToDynTable($table, $table);
      }
   }
   return 1;
}

sub getDataSet {
   # TODO:XXX:FIXME: onDone analog zum DBManager/NewUpdateData...
   my $self = shift;
   my $params = shift;
   if (ref($params) ne "HASH") {
      my $tmp = $params;
      $params = {};
      $params->{table}         = $tmp;
      $params->{id}            = shift || undef;
      $params->{skip}          = shift || 0;
      $params->{rows}          = shift || 0;
      $params->{searchdef}     = shift || undef;
      $params->{sortby}        = shift || undef;
      $params->{groupcolumn}   = shift || undef;
      $params->{wherePre}      = shift || [];
      $params->{tablebackrefs} = shift || 0;
      $params->{session}       = shift || undef;
      Log("DBBackend: getDataSet: Unknown paramters in doing magic!", $WARNING) if shift;
      if ($params->{session}) {
         Log("DBBackend: getDataSet: Parameterformat has changed! You have to migrate to Hash! Doing magic to let it still work...", $WARNING);
      } else {
         Log("DBBackend: getDataSet: Parameterformat has changed and session is missing! This cannot work!", $ERROR);
      }
   }
   $params->{skip} ||= 0;

   return [[], 0] if $self->isBadCVSFile($params->{table});

   return undef unless ($params->{table} = makeEvilGood($self, $params->{table}));

   unless ($params->{session}) {
      Log("DBBackend: getDataSet: currentSession missing!", $ERROR);
      return undef;
   }

   # ToDo/FixMe: GROUP-Column überprüfen? Ist jetzt nicht mehr "column" sondern "table.column"...
   #if ($params->{groupcolumn} && !(exists($self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$params->{groupcolumn}}))) {
   #   Log("DBBackend: getDataSet: The groupcolumn :".$params->{groupcolumn}.": does not exists in table :".$params->{table}.":!", $ERROR);
   #   return undef;
   #}
   $params->{tablebackrefs} = 0 if $params->{groupcolumn};
   #Log("BACKREF:".$params->{table}.":".$params->{tablebackrefs}.":\n", $DEBUG);
   my $selectdef = $self->getSQLStringForTable({
      table         => $params->{table},
      id            => $params->{id},
      filter        => $params->{searchdef},
      orderby       => normaliseLine($params->{sortby}),
      tablebackrefs => $params->{tablebackrefs},
      where         => $params->{wherePre},
      simple        => $params->{simple},
      all           => $params->{all},
      onlymax       => $params->{onlymax},
      nodeleted     => $params->{nodeleted},
      groupby       => $params->{groupcolumn}});
   unless ($selectdef) {
      Log("DBBackend: getDataSet: getSQLStringForTable for table :".$params->{table}.": failed!", $ERROR);
      return undef;
   }

   #Log("GROUPBY:".join(";", @{$selectdef->[5]}).":", $DEBUG);
   my $statement = '';
   $statement .= " WHERE ".$selectdef->[3] if $selectdef->[3];
   #if ($params->{groupcolumn}) {
   #   unshift(@{$selectdef->[5]}, $params->{table}.$TSEP.$params->{groupcolumn});
   #   $statement .= " GROUP BY ".join(", ", @{$selectdef->[5]});
   #}
   $statement .= " GROUP BY ".$selectdef->[5] if $selectdef->[5];
   my $orderby = '';
   $orderby = " ORDER BY ".$selectdef->[4] if $selectdef->[4];

   my $tmp = ($selectdef->[0] && $selectdef->[1]) ? ', ' : '';
   my $tmp2 = $selectdef->[0] ? ', ' : '';
   my $selectstatement = $params->{groupcolumn} ? "SELECT ".$params->{groupcolumn}.", COUNT(*)".$tmp2.$selectdef->[0]
                                      : "SELECT ".$selectdef->[0].$tmp.$selectdef->[1];
   $selectstatement .= " FROM ".$selectdef->[2];
   my $countstatement = "SELECT COUNT(*) FROM ".$selectdef->[2]; #" FROM ".$params->{table}; #.$selectdef->[2];
   $countstatement = $params->{onlymax} ? "SELECT COUNT(*) FROM (".$countstatement.$statement.") AS TEMP " : $countstatement.$statement;

   my $linecount = 0;
   my $limit = $params->{rows} || 0; # || "ALL";
   unless ($params->{groupcolumn}) {
      Log("DBBackend: getDataSet: PREPARE:".$countstatement.":", $DEBUG);
      $self->checkPid();
      my $sth = $self->{dbm}->prepare($countstatement);
      eval {
         $sth->execute();
      }; 
      if ($@) {
         Log("DBBackend: getDataSet: GETROWCOUNT: Error executing Database command: ".$@, $ERROR);
         $sth->finish();
         $self->{dbm} = undef;
         $self->db_open;
         return undef;
      }
      my $i = 0;
      while (my $line = $sth->fetchrow_hashref) {
         if ($i++ > 0) {
            Log("DBBackend: getDataSet: GETROWCOUNT: More than one line for COUNT(*) SQL Query!".$@, $ERROR);
            last;
         }
         my $count = $line->{'COUNT(*)'};
         $count = $line->{"COUNT"} if ((!defined($count)) || ($count eq ''));
         $count = $line->{"count"} if ((!defined($count)) || ($count eq ''));
         #Log("DBBackend: getDataSet: GETROWCOUNT: VALUES ".join(",",(map { "'".$_."'='".$line->{$_}."'" } keys(%$line))).":", $DEBUG);
         Log("DBBackend: getDataSet: GETROWCOUNT: COUNT FOR :".$params->{table}.": IS :".$count.":", $DEBUG);
         $linecount = $count;
      }
      $sth->finish();
      if (($i == 1) && defined($linecount)) {
         if (($limit+$params->{skip}) > $linecount) {
            if ($params->{skip} > $linecount) {
               Log("DBBackend: getDataSet: skip=".$params->{skip}." > linecount=".$linecount."!", $ERROR);
               return undef;
            } else {
               $limit = $linecount - $params->{skip};
            }
         }
      } else {
         Log("DBBackend: getDataSet: GETROWCOUNT: Unable determinig linecount!".$@, $ERROR);
         $linecount = 0;
      }
   }
   my $tmp3 = $selectstatement.$statement;
   $tmp3 .= $orderby unless $params->{groupcolumn};
   if ($limit && (!$params->{groupcolumn})) {
      if ($self->{config}->{DB}->{type} eq "postgres") {
         $tmp3 .= " LIMIT ".$limit;
         $tmp3 .= " OFFSET ".$params->{skip} if $params->{skip};
      } else {
         $tmp3 .= " LIMIT ".($params->{skip} ? $params->{skip}."," : '').$limit;
      }
   }
   #$tmp3 .= ";";
   Log("DBBackend: getDataSet: GETROWS: PREPARE:".$tmp3.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($tmp3);
   eval {
      $sth->execute();
   }; 
   if ($@) {
      Log("DBBackend: getDataSet: GETROWS: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   my $ret = [];
   my $codelist = [];
   my $alllist = [];
   my $line = $sth->fetchrow_hashref;
   foreach my $ctable (keys %{$self->{config}->{DB}->{tables}}) {
      next unless ($line && (ref($line) eq "HASH") && (exists($line->{$ctable.$TSEP.$self->getIdColumnName($ctable)}) ||
                                                   exists($line->{'"'.$ctable.$TSEP.$self->getIdColumnName($ctable).'"'})));
      my $tabledef = $self->{config}->{DB}->{tables}->{$ctable};
      foreach my $thecolumn (hashKeysRightOrder($tabledef->{columns}, "dborder")) {
         push(@$alllist, [$ctable, $tabledef, $thecolumn])
            if ($self->{config}->{DB}->{type} =~ /^CSV$/i);
         push(@$codelist, [$ctable, $tabledef, $thecolumn]) if
            (exists($tabledef->{columns}->{$thecolumn}) &&
            defined($tabledef->{columns}->{$thecolumn}) &&
                    $tabledef->{columns}->{$thecolumn} &&
             exists($tabledef->{columns}->{$thecolumn}->{type}) &&
            defined($tabledef->{columns}->{$thecolumn}->{type}) &&
                   ($tabledef->{columns}->{$thecolumn}->{type} =~ /^virtual$/i) &&
                   ($tabledef->{columns}->{$thecolumn}->{code}));
      }
   }
   my $onetime = {};
   while ($line) {
      # TODO:FIXME:XXX: Nicht-Qooxdoo Version hat hier probleme; Zeilenumbrüche führen zu Zeilenumbrüchen im Protokoll!!!
      #foreach my $kname (keys %$line) {
      #   next unless $line->{$kname};
      #   $line->{$kname} =~ s/#/##/g;
      #   $line->{$kname} =~ s/\n/#13/g;
      #   $line->{$kname} =~ s/\r/#10/g;
      #}
      #print "LINE:".join(",", map { $_."=".$line->{$_} } keys %$line).":\n";
      foreach my $curdef (@$alllist) {
         my $ctable = $curdef->[0];
         my $tabledef = $curdef->[1];
         my $thecolumn = $curdef->[2];
         #Log("LOOKINGFOR:".join(",", keys %{$tabledef->{columns}}).":", $DEBUG);
         $line->{$ctable.$TSEP.$thecolumn} ||= $line->{'"'.$ctable.$TSEP.$thecolumn.'"'};
         delete $line->{'"'.$ctable.$TSEP.$thecolumn.'"'};
      }
      foreach my $curdef (@$codelist) {
         my $ctable = $curdef->[0];
         my $tabledef = $curdef->[1];
         my $thecolumn = $curdef->[2];
         my $curcolumn = $tabledef->{columns}->{$thecolumn};
         $line->{$ctable.$TSEP.$thecolumn} = $curcolumn->{code}($line, $params->{session}, $params, $self, $onetime);
         delete $line->{$ctable.$TSEP.$thecolumn} unless defined($line->{$ctable.$TSEP.$thecolumn});
      }
      #print "AFTERLINE:".join(",", map { $_."=".$line->{$_} } keys %$line).":\n";
      push(@$ret, $line);
      $line = $sth->fetchrow_hashref;
   }
   $sth->finish();
   if ($params->{onDone}) {
      $params->{onDone}($params, [$ret, $linecount]);
   } else {
      return [$ret, $linecount];
   }
}

sub getTableInfo {
   my $self = shift;
   my $table = shift;
   my $searchdef = shift || undef;

   return [{max => 0}] if $self->isBadCVSFile($table);

   return undef unless ($table = makeEvilGood($self, $table));
   my $infos = [];

   my $onlySelectedTables = 0;
   grep { $onlySelectedTables = 1 if ($_ =~ /_selected$/) } keys %$searchdef if (ref($searchdef) eq "HASH");

   foreach my $column (grep { ((ref($searchdef) ne "HASH") || (!$onlySelectedTables) || ($searchdef->{$_."_selected"})) } (keys (%{$self->{config}->{DB}->{tables}->{$table}->{columns}}))) {
      my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}->{$column});
      next if ($curcolumn->{type} =~ /^virtual$/i);
      unless ($curcolumn->{dbtype}) {
         Log("Column ".$column." from table ".$table." has no dbtype!", $DEBUG);
         next;
      }
      # ToDo: Bricht das Auskommentieren dieser Zeile etwas beim URLFilter?! Testen!
      $curcolumn->{info} .= " max " if (($column eq $self->getIdColumnName($table)) && (!(defined($curcolumn->{info}) && ($curcolumn->{info} =~ /max/i))));
      next unless $curcolumn->{info};
      foreach (split(/\s+/, $curcolumn->{info})) {
         my $func = '';
         if (/^sum$/i) {
            $func = "SUM";
         } elsif (/^min$/i) {
            $func = "MIN";
         } elsif (/^max$/i) {
            $func = "MAX";
         } elsif($_) {
            Log("DBBackend: getTableInfo: unknown INFO type :".$_.":", $ERROR);
         }
         push(@$infos, $func."(".$table.$TSEP.$column.") AS ".$func."_".$column) if $func;
      }
   }

   unless (scalar(@$infos)) {
      Log("DBBackend: getTableInfo: No INFOS-Columns for table :".$table.":", $DEBUG);
      return [{}];
   }

   my $selectdef = $self->getSQLStringForTable({table => $table, filter => $searchdef, simple => 1});
   unless ($selectdef) {
      Log("DBBackend: getTableInfo: getSQLStringForTable for table :".$table.": failed!", $ERROR);
      return undef;
   }

   my $selectstatement = "SELECT ".join(", ", @$infos)." FROM ".$selectdef->[2];
   $selectstatement .= " WHERE ".$selectdef->[3] if $selectdef->[3];

   Log("DBBackend: getTableInfo: PREPARE:".$selectstatement.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($selectstatement);
   eval {
      $sth->execute();
   };
   if ($@) {
      Log("DBBackend: getTableInfo: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   my $ret = [];
   while (my $line = $sth->fetchrow_hashref) {
      push(@$ret, $line);
      Log("LINE:".join(",", keys(%$line)).":", $DEBUG);
   }
   $sth->finish();
   return $ret;
}

sub insertDataSet {
   my $self = shift;
   my $params = shift;
   if (ref($params) eq "HASH") {
      $params->{user} ||= $params->{session}->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME};
   } else {
      Log("DBBackend: insertDataSet: Parameterformat has changed! You have to migrate to Hash! Doing magic to let it still work...", $ERROR);
      my $tmp = $params;
      $params = {};
      $params->{table}   = $tmp;
      $params->{columns} = shift;
      $params->{user}    = shift;
      Log("DBBackend: insertDataSet: Unknown paramters in doing magic!", $WARNING) if shift;
   }

   my $ret = undef;

   return undef if $self->isBadCVSFile($params->{table});

   return undef unless ($ret = makeEvilColumnDataGood($self, $params->{table}, $params->{columns}));

   my $table = $params->{table};
   my $statement = "INSERT INTO ".$params->{table}." ( ".
      join(", ", map { s/${table}${TSEP}//; $_ } @{$ret->[0]})." ) VALUES ( ".
      join(", ", map { "?" } @{$ret->[1]})." )"; 

   Log("DBBackend: insertDataSet: PREPARE:".$statement.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($statement);
   eval {
      $sth->execute(@{$ret->[1]});
   };
   if ($@) {
      Log("DBBackend: insertDataSet: GETROWS: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   #my $insertedID = $self->{dbm}->last_insert_id(undef,undef,undef,undef);
   $sth->finish();
   #return $insertedID if defined($insertedID);
   $ret = undef;
   my $id = undef;
   my $retx = undef;
   if (exists($self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$self->getIdColumnName($params->{table})})) {
      unless (defined($ret = getTableInfo($self, $params->{table})) && (ref($ret) eq "ARRAY")) {
         Log("DBBackend: insertDataSet: GETTABLEINFO: SQL Query failed for table :".$params->{table}.":", $ERROR);
         die;
      }
      unless (scalar(@{$ret}) == 1) {
         Log("DBBackend: insertDataSet: GETTABLEINFO: Got :".scalar(@{$ret}).": row for INFO-Question for table :".$params->{table}.":!", $WARNING);
         return undef;
      }
      $id = $ret->[0]->{'MAX_'.$self->getIdColumnName($params->{table})} || $ret->[0]->{'max_'.$self->getIdColumnName($params->{table})};
      unless ($id) {
         Log("DBBackend: insertDataSet: Unable to find the new ID!", $ERROR);
         die;
      } 
      unless (defined($retx = $self->getDataSet({
         table => $params->{table},
         id => $id,
         session => $params->{session},
         tablebackrefs => $params->{tablebackrefs},
      })) && (ref($retx) eq "ARRAY")) {
         Log("DBBackend: insertDataSet: SQL GET Query failed after INSERT.", $ERROR);
         die;
      }
      if ( (ref($retx->[0]) ne "ARRAY") || (scalar(@{$retx->[0]}) != 1) ) {
         Log("DBBackend: insertDataSet: Wanted one line, but got :".scalar(@{$retx->[0]}).":", $ERROR);
         return undef;
      }
   }
   unless (logDBChange($self, $params->{user}, $self->hashDiff($self->{config}->{DB}, {}, defined($retx) ? $retx->[0]->[0] : $params->{columns}, $params->{table}, 1), $params->{table}, "INSERT", $id)) {
      Log("DBBackend: insertDataSet: Unable to Log AFTER INSERT USER=".$params->{user}." TABLE=".$params->{table}, $ERROR);
   }
   return $id;
}

sub deleteDataSet {
   my $self = shift;
   my $params = shift;
   if (ref($params) eq "HASH") {
      $params->{user} ||= $params->{session}->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME};
   } else {
      Log("DBBackend: deleteDataSet: Parameterformat has changed! You have to migrate to Hash! Doing magic to let it still work...", $ERROR);
      my $tmp = $params;
      $params = {};
      $params->{table} = $tmp;
      $params->{id}    = shift;
      $params->{user}  = shift;
      $params->{wherePre} = shift || [];
      Log("DBBackend: deleteDataSet: Unknown paramters in doing magic!", $WARNING) if shift;
   }
   
   my $conjunction = undef;

   return undef if $self->isBadCVSFile($params->{table});

   return undef unless ($params->{table} = makeEvilGood($self, $params->{table}));

   my $real = ($self->{config}->{DB}->{tables}->{$params->{table}}->{realdelete} ||
              ($self->{config}->{DB}->{type} =~ m,CSV,i)) ? 1 : 0;
   my $retx;

   unless ($real || exists($self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$DELETEDCOLUMNNAME})) {
      Log("DBBackend: deleteDataSet: No :".$DELETEDCOLUMNNAME.": column!.", $ERROR);
      return undef;
   }
   unless ($real) {
      my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$DELETEDCOLUMNNAME});
      $conjunction = $curcolumn->{"dbcompare"} || "=";
   }

   unless (defined($retx = $self->getDataSet({
      table => $params->{table},
      wherePre => $params->{wherePre},
      id => $params->{id},
      session => $params->{session},
      tablebackrefs => $params->{tablebackrefs},
   })) && (ref($retx) eq "ARRAY")) {
      Log("DBBackend: deleteDataSet: SQL GET Query failed.", $ERROR);
      return undef;
   }

   if ( (ref($retx->[0]) ne "ARRAY") || (scalar(@{$retx->[0]}) != 1) ) {
      Log("DBBackend: deleteDataSet: Wanted one line, but got :".scalar(@{$retx->[0]}).":", $ERROR);
      return undef;
   }
   return undef unless logDBChange($self, $params->{user}, $self->hashDiff($self->{config}->{DB}, $retx->[0]->[0], {deleted => 1}, $params->{table}, 1), $params->{table}, $real?"REMOVE":"DELETE", $params->{id});

   my $statement = '';
   if ($real) {
      $statement = "DELETE FROM ".$params->{table}." WHERE ";
   } else {
      $statement = "UPDATE ".$params->{table}." SET ".$DELETEDCOLUMNNAME." ".$conjunction." ".normaliseLine("1",1)." WHERE ";
   }

   my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$self->getIdColumnName($params->{table})});
   $conjunction = $curcolumn->{"dbcompare"} || "=";

   $statement .= $self->getIdColumnName($params->{table})." ".$conjunction." ".normaliseLine($params->{id},1).";";

   Log( "DBBackend: deleteDataSet: PREPARE:".$statement.":", $DEBUG, );
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($statement);
   eval {
      $sth->execute();
   };
   if ($@) {
      Log("DBBackend: deleteDataSet: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return 0;
   }
   $sth->finish();
   return 1;
}

sub undeleteDataSet {
   my $self = shift;
   my $params = shift;
   if (ref($params) eq "HASH") {
      $params->{user} ||= $params->{session}->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME};
   } else {
      Log("DBBackend: undeleteDataSet: Parameterformat has changed! You have to migrate to Hash! Doing magic to let it still work...", $ERROR);
      my $tmp = $params;
      $params = {};
      $params->{table} = $tmp;
      $params->{id}    = shift;
      $params->{user}  = shift;
      $params->{wherePre} = shift || [];
      Log("DBBackend: undeleteDataSet: Unknown paramters in doing magic!", $WARNING) if shift;
   }

   my $conjunction = undef;

   return undef if $self->isBadCVSFile($params->{table});

   return undef unless ($params->{table} = makeEvilGood($self, $params->{table}));

   my $retx;

   unless (exists($self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$DELETEDCOLUMNNAME})) {
      Log("DBBackend: undeleteDataSet: No :".$DELETEDCOLUMNNAME.": column!.", $ERROR);
      return undef;
   }
   my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$DELETEDCOLUMNNAME});
   $conjunction = $curcolumn->{"dbcompare"} || "=";

   unless (defined($retx = $self->getDataSet({table => $params->{table}, wherePre => $params->{wherePre}, id => $params->{id}, searchdef => { $params->{table}.$TSEP.$DELETEDCOLUMNNAME => 1 }, session => $params->{session}})) && (ref($retx) eq "ARRAY")) {
      Log("DBBackend: undeleteDataSet: SQL GET Query failed.", $ERROR);
      return undef;
   }

   if ( (ref($retx->[0]) ne "ARRAY") || (scalar(@{$retx->[0]}) != 1) ) {
      Log("DBBackend: undeleteDataSet: Wanted one line, but got :".scalar(@{$retx->[0]}).":", $ERROR);
      return undef;
   }
   return undef unless logDBChange($self, $params->{user}, $self->hashDiff($self->{config}->{DB}, {
      $params->{table}.$TSEP.$DELETEDCOLUMNNAME => $retx->[0]->[0]->{$params->{table}.$TSEP.$DELETEDCOLUMNNAME},
      $params->{table}.$TSEP.$self->getIdColumnName($params->{table}) => $retx->[0]->[0]->{$params->{table}.$TSEP.$self->getIdColumnName($params->{table})}
   }, {
      $params->{table}.$TSEP.$DELETEDCOLUMNNAME => 0,
      $params->{table}.$TSEP.$self->getIdColumnName($params->{table}) => $retx->[0]->[0]->{$params->{table}.$TSEP.$self->getIdColumnName($params->{table})}
   }, $params->{table}, 1), $params->{table}, "UNDELETE", $params->{id});

   my $statement = "UPDATE ".$params->{table}." SET ".$DELETEDCOLUMNNAME." ".$conjunction." ".normaliseLine("0",1)." WHERE ";

   $curcolumn = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$params->{table}}->{columns}->{$self->getIdColumnName($params->{table})});
   $conjunction = $curcolumn->{"dbcompare"} || "=";

   $statement .= $self->getIdColumnName($params->{table})." ".$conjunction." ".normaliseLine($params->{id},1).";";

   Log( "DBBackend: undeleteDataSet: PREPARE:".$statement.":", $DEBUG, );
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($statement);
   eval {
      $sth->execute();
   };
   if ($@) {
      Log("DBBackend: undeleteDataSet: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return 0;
   }
   $sth->finish();
   return 1;
}

sub updateDataSet {
   my $self = shift;
   my $params = shift;
   if (ref($params) eq "HASH") {
      $params->{user} ||= $params->{session}->{$USERSTABLENAME.$TSEP.$USERNAMECOLUMNNAME};
   } else {
      Log("DBBackend: updateDataSet: Parameterformat has changed! You have to migrate to Hash! Doing magic to let it still work...", $ERROR);
      my $tmp = $params;
      $params = {};
      $params->{table}   = $tmp;
      $params->{id}      = shift;
      $params->{columns} = shift;
      $params->{user}    = shift;
      $params->{wherePre} = shift || [];
      Log("DBBackend: updateDataSet: Unknown paramters in doing magic!", $WARNING) if shift;
   }
   my $ret;
   
   return undef if $self->isBadCVSFile($params->{table});

   return undef unless ($params->{id} && ($ret = makeEvilColumnDataGood($self, $params->{table}, $params->{columns}, 0)));

   my $retx;
   unless ($self->{config}->{DB}->{tables}->{$params->{table}}->{nolog}) {
      unless (defined($retx = $self->getDataSet({
         table => $params->{table},
         wherePre => $params->{wherePre},
         id => $params->{id},
         session => $params->{session},
         nodeleted => $params->{nodeleted},
         simple => 1,
         tablebackrefs => $params->{tablebackrefs},
         simple => $params->{tablebackrefs} ? 0 : 1,
      })) && (ref($retx) eq "ARRAY")) {
         Log("DBBackend: updateDataSet: SQL GET Query failed.", $ERROR);
         return undef;
      }
      if ( (ref($retx->[0]) ne "ARRAY") || ((!$params->{acceptmultiples}) && (scalar(@{$retx->[0]}) != 1)) ) {
         Log("DBBackend: updateDataSet: Wanted one line, but got :".scalar(@{$retx->[0]}).":", $ERROR);
         return undef;
      }
   }
   my $statement;
   my $i = 0;
   $statement = "UPDATE ".$params->{table}." SET ";
   $statement .= join(", ", map { $_." = ?" } @{$ret->[0]});
   $statement .= " WHERE ".$self->getIdColumnName($params->{table})."=".normaliseLine($params->{id},1).";";

   Log( "DBBackend: updateDataSet: PREPARE:".$statement.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($statement);
   eval {
      $sth->execute(@{$ret->[1]});
   };
   if ($@) {
      Log( "DBBackend: updateDataSet: Error executing Database command: ".$@, $ERROR );
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   $sth->finish();
   unless ($self->{config}->{DB}->{tables}->{$params->{table}}->{nolog}) {
      my $rety;
      unless (defined($rety = $self->getDataSet({
         table => $params->{table},
         id => $params->{id},
         session => $params->{session},
         nodeleted     => $params->{nodeleted},
         tablebackrefs => $params->{tablebackrefs},
         simple => $params->{tablebackrefs} ? 0 : 1,
      })) && (ref($rety) eq "ARRAY")) {
         Log("DBBackend: updateDataSet: SQL GET Query failed.", $ERROR);
         return undef;
      }
      if ( (ref($rety->[0]) ne "ARRAY") || ((!$params->{acceptmultiples}) && (scalar(@{$rety->[0]}) != 1)) ) {
         Log("DBBackend: updateDataSet: Wanted one line, but got :".scalar(@{$rety->[0]}).":", $ERROR);
         die;
      }
      unless (logDBChange($self, $params->{user}, $self->hashDiff($self->{config}->{DB}, $retx->[0]->[0], $rety->[0]->[0], $params->{table}, 1), $params->{table}, "UPDATE", $params->{id})) {
         Log("DBBackend: updateDataSet: can't log change!", $ERROR);
         die;
      }
   }
   return $params->{id};
}

sub logDBChange {
   my $self = shift;
   my $user = shift;
   my $diff = shift;
   my $table = shift;
   my $typ = shift;
   my $entry = shift;

   return 1 unless $diff;
   #TODO:FIXME:XXX: Logging evtl. deligieren... an anderes Backend... ReadOnly Funktion einbauen?
   return 1 unless exists($self->{config}->{DB}->{tables}->{$LOG});
   return 1 if $self->{config}->{DB}->{tables}->{$table}->{nolog};
   # TODO:XXX:FIXME: Hier sollte man DBI Bindings nutzen!
   my $statement = "INSERT INTO ".$LOG." ( ".
      join(", ", ($TYP, $USER, $TIMESTAMP, $TABLE, $DIFF, $ENTRY))." ) VALUES ( ".
      join(", ", (normaliseLine($typ, 1),
                  normaliseLine($user, 1),
                  normaliseLine(MakeTime(time),1),
                  #($tmp[5]+1900)."-".($tmp[4]+1)."-".($tmp[3])." ".($tmp[2]+1).":".$tmp[1].":".$tmp[0], 1),
                  normaliseLine($table, 1),
                  normaliseLine($diff, 1),
                  normaliseLine($entry, 1),
                 )
          ).
      " );";

   Log("DBBackend: logDBChange: PREPARE:".$statement.":", $DEBUG);
   $self->checkPid();
   my $sth = $self->{dbm}->prepare($statement);
   eval {
      $sth->execute();
   };
   if ($@) {
      Log("DBBackend: logDBChange: Error executing Database command: ".$@, $ERROR);
      $sth->finish();
      $self->{dbm} = undef;
      $self->db_open;
      return undef;
   }
   $sth->finish();
   return 1;
}

sub getBabelFor {
   my $DB = shift;
   my $line = shift;
   my $table = shift;
   $_ = $line;
   my $babel = $_;
   my $curcolumn = $_;
   my $curtable = $table;

   if ((/^(.*)\_([^\_]*)$/i) && exists($DB->{tables}->{$1}) && exists($DB->{tables}->{$1}->{columns}->{$2})) {
      $babel = $DB->{tables}->{$1}->{label} || $1;
      $curtable = $1;
      $curcolumn = $2;
   }
   if (exists($DB->{tables}->{$curtable}->{columns}->{$curcolumn})) {
      if ($curcolumn ne $babel) {
         $babel .= "/";
      } else {
         $babel = '';
      }
      $babel .= $DB->{tables}->{$curtable}->{columns}->{$curcolumn}->{label} || $curcolumn;
   }
   return $babel;
}

sub hashDiff {
   my $self = shift;
   my $DB = shift;
   my $hash1 = shift;
   my $hash2 = shift;
   my $table = shift;
   my $hideInfoLines = shift;
   my $change = {};
   foreach (grep { defined($hash1->{$_}) } keys %$hash1) {
      my $tmp = $_;
      my $real = $_;
      $tmp =~ s/^(Y|X)_//;
      # TODO:XXX:FIXME: $UNIQIDCOLUMNNAME ist hier ziemlich unsinning... Das ist alt und muss an neue Mechanismen angepasst werden.
      next if (($tmp =~ /^.*\_$UNIQIDCOLUMNNAME$/i) || ($tmp eq $DELETEDCOLUMNNAME));
      my $babel = getBabelFor($DB, $tmp, $table);
      if (!exists($hash2->{$real})) {
         $change->{$real."0"} = "-".$babel.": ".$hash1->{$real}."\n";
      } elsif (exists($hash2->{$real}) && ($hash1->{$real} ne $hash2->{$real}) && (($hash2->{$real} ne '') || $hash1->{$real})) {
         $change->{$real."1"} = "-".$babel.": ".$hash1->{$real}."\n";
         $change->{$real."0"} = "+".$babel.": ".$hash2->{$real}."\n";
      } else {
         $change->{$real."0"} = $babel.": ".$hash2->{$real}."\n" if ((!$hideInfoLines) || ($real eq $UNIQIDCOLUMNNAME));
      }
   }
   foreach (grep { defined($hash2->{$_}) } keys %$hash2) {
      my $tmp = $_;
      my $real = $_;
      $tmp =~ s/^(Y|X)_//;
      # TODO:XXX:FIXME: $UNIQIDCOLUMNNAME ist hier ziemlich unsinning... Das ist alt und muss an neue Mechanismen angepasst werden.
      next if (($tmp =~ /^(|.*\_)$UNIQIDCOLUMNNAME$/i) || ($tmp eq $DELETEDCOLUMNNAME));
      my $babel = getBabelFor($DB, $tmp, $table);
      unless (exists($hash1->{$real}) || ($hash2->{$real} eq '')) {
         $change->{$real."0"} = "+".$babel.": ".$hash2->{$real}."\n";
         #$change .= "+".$real.": ".$hash2->{$real}."\n";
      }
   }
   my $tmp = '';
   # ToDo: Hack fuer URL Filter... sollte noch ausgelagert werden.
   foreach (sort { my $ap = 0; my $bp = 0;
   #                $ap = 1 if ($a =~ /^url/);
   #                $bp = 1 if ($b =~ /^url/);
   #                $ap = 2 if ($a =~ /^domain/);
   #                $bp = 2 if ($b =~ /^domain/);
   #                $ap = 3 if ($a =~ /^abt/);
   #                $bp = 3 if ($b =~ /^abt/); 
                   if ($bp <=> $ap) {
                       $bp <=> $ap
                   } else {
                       $b cmp $a
                   }
                 } keys %$change) {
      $tmp .= $change->{$_};
   }
   my $babel = getBabelFor($DB, $table.$TSEP.$self->getIdColumnName($table), $table);
   $tmp .= $babel.": ".($hash1->{$table.$TSEP.$self->getIdColumnName($table)} || $hash2->{$table.$TSEP.$self->getIdColumnName($table)});
   return $tmp;
}

sub wohinVerweistTabelle {
   my $self = shift;
   my $table = shift;
   my $return = shift;
   my $tmp = [];
   foreach my $column (@{getAffectedColumns($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}, 0, 0, 1)}) {
      next if $self->{config}->{DB}->{tables}->{$table}->{columns}->{$column}->{nosqljoin};
      foreach my $curtable (keys(%{$self->{config}->{DB}->{tables}})) {
         push(@$tmp, [$curtable, $column])
            if (($self->{config}->{DB}->{tables}->{$table}->{columns}->{$column}->{linkto} &&
                ($self->{config}->{DB}->{tables}->{$table}->{columns}->{$column}->{linkto} eq $curtable)) ||
                ($self->{config}->{oldlinklogic} && ($column eq $curtable."_".$self->getIdColumnName($curtable))));
      }
   }
   return $tmp;
}

sub werVerweistAufTabelle {
   my $self = shift;
   my $searchtable = shift;
   my $return = shift;
   my $tmp = [];
   foreach my $table (keys(%{$self->{config}->{DB}->{tables}})) {
      foreach my $column (@{getAffectedColumns($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}, 0, 0, 1)}) {
         push(@$tmp, [$table, $column]) if
            (($self->{config}->{DB}->{tables}->{$table}->{columns}->{$column}->{linkto} &&
             ($self->{config}->{DB}->{tables}->{$table}->{columns}->{$column}->{linkto} eq $searchtable)) ||
             ($self->{config}->{oldlinklogic} && ($column eq $searchtable."_".$self->getIdColumnName($searchtable))));
      };
   } 
   return $tmp;
}

sub searchForwardTableConnections {
   my $self = shift;
   my $table = shift;
   my $known = shift;
   my $pre = shift;
   my $return = shift;
   my $dobackward = shift || 0;
   my $sourceas = shift;
   # Wohin verweise ich?
   my @later = ();
   foreach my $curdef (@{$self->wohinVerweistTabelle($table, $return)}) {
      my $ctable = $curdef->[0];
      my $column = $curdef->[1];
      # TODO:FIXME:XXX: Das ist nen Quickfix... Doppelte Nutzung der gleichen Tabelle sollte möglich sein!
      #next if ($known->{$table."_".$ctable."_".$table});
      my $asname = $column."_".$ctable;
      next if (#$dobackward &&
                                 exists($self->{config}->{DB}->{tables}->{$table}->{noforwardifbacklink}) && 
          grep({ ($asname =~ m,$_,) } @{$self->{config}->{DB}->{tables}->{$table}->{noforwardifbacklink}}));
      # TODO:XXX:FIXME: Das hier greift ueber $pre auf die vorletzte Tabelle zu... Das sollte aber eigentlich
      #                 auf die Starttabelle zugreifen! Die ist hier allerdings nicht verfuegbar! Das sollte
      #                 geaendert werden.
      next if (exists($self->{config}->{DB}->{tables}->{$pre||$table}->{noautolink}) && grep({ ($_ eq $ctable) }
                    @{$self->{config}->{DB}->{tables}->{$pre||$table}->{noautolink}}));
      if ($known->{$asname}++) {
         Log("JOIN: ".$table." -X ".$ctable." as ".($sourceas||$table)." -> ".$asname, $DEBUG);
         next;
      }
      push(@{$return->{joins}}, {
         from => $table,
         to => $ctable,
         as => $asname,
         sourceas => $sourceas,
         column => $column,
      });
      push(@later, [$ctable, ($asname ne $ctable) ? $asname : '']);
      Log("JOIN: ".$table." -> ".$ctable." as ".($sourceas||$table)." -> ".$asname, $DEBUG);
      push(@{$return->{history}}, { type => $FORWARD, table => $table, ctable => $ctable, source => ($sourceas||$table), asname => $asname });
   }
   foreach my $curtable (@later) {
      $self->searchForwardTableConnections($curtable->[0], $known, $table, $return, undef, $curtable->[1]);
   }
   return $known;
}

sub searchTableConnections {
   my $self = shift;
   my $table = shift;
   my $dobackward = shift;
   my $param3 = shift;
   my $param4 = shift;
   my $param5 = shift;
   my $param6 = shift;
   my $param7 = shift;
   die if shift;
   unless ($param3 || $param4 || $param5 || $param6 || $param7) {
      return $self->{cache}->{searchTableConnections}->{$table}->{$dobackward}
         if ($self->{cache}->{searchTableConnections}->{$table}->{$dobackward});
   }
   my $curtable = $param3 || $table;
   my $known = $param4 || { $table => 1 };
   my $pre = $param5;
   my $return = $param6 || {
      history => [],
   };
   my $sourceas = $param7;
   my $later = {};
   foreach my $ctable ($curtable, (keys %{$self->searchForwardTableConnections($curtable, $known, $pre, $return, $dobackward)})) {
      next unless $dobackward;
      foreach my $curdef (@{$self->werVerweistAufTabelle($ctable, $return)}) {
         my $cctable = $curdef->[0];
         my $column = $curdef->[1];
         my $asname = $known->{$cctable} ? ($sourceas||$ctable)."_".$cctable : $cctable;
         unless (exists($self->{config}->{DB}->{tables}->{$table}->{allowautobackjoin}) && grep({ ($_ eq $asname) } 
                      @{$self->{config}->{DB}->{tables}->{$table}->{allowautobackjoin}})) {
            Log("JOIN: ".$ctable." X- ".$cctable." as ".($sourceas||$ctable)." <- ".$asname, $DEBUG);
            next;
         }
         next if (exists($self->{config}->{DB}->{tables}->{$table}->{noautolink}) && grep({ ($_ eq $cctable) }
                       @{$self->{config}->{DB}->{tables}->{$table}->{noautolink}}));
         if ($known->{$asname}++) {
            Log($asname.": ".$asname." already existing.", $DEBUG);
            next;
         }
         Log("JOIN: ".$ctable." <- ".$cctable." as ".$asname, $DEBUG);
         push(@{$return->{history}}, { type => $BACKWARD, table => $table, ctable => $cctable, asname => $asname });
         push(@{$return->{joins}}, {
            from => $cctable,
            to => $ctable,
            as => $asname,
            sourceas => $sourceas,
            column => $column,
            back => 1,
         });
         $later->{$cctable} = [$ctable, ($asname ne $cctable) ? $asname : ''];
         $known->{$cctable}++;
      }
   }
   foreach my $cctable (keys(%$later)) {
      my $tablelink = $later->{$cctable};
      $self->searchTableConnections($table, $dobackward, $cctable, $known, $tablelink->[0], $return, $tablelink->[1]);
   }
   $self->{cache}->{searchTableConnections}->{$table}->{$dobackward} = $return
      unless ($param3 || $param4 || $param5 || $param6 || $param7);
   return $return;
}

sub getSelectColumnsForTable {
   my $self = shift;
   my $table = shift;
   my $all = shift;
   my $selectQuestion = shift;
   my $astable = shift;
   my $onlymax = shift || 0;
   return (join(", ", map {
      ($onlymax ? "MAX(" : "").$_.($onlymax ? ")" : "").' AS '.(
      $self->{config}->{DB}->{tables}->{$table}->{dbcolumnquotes} ?
      $self->{config}->{DB}->{tables}->{$table}->{dbcolumnquotes} : '"').$_.(
      $self->{config}->{DB}->{tables}->{$table}->{dbcolumnquotes} ? 
      $self->{config}->{DB}->{tables}->{$table}->{dbcolumnquotes} : '"')
   } @{$self->getColumnsForTable($table, $all, $selectQuestion, undef, $astable)}));
}

sub getColumnsForTable {
   my $self = shift;
   my $table = shift;
   my $all = shift;
   my $selectQuestion = shift;
   my $nopretable = shift;
   my $astable = shift;
   return [map({ ($nopretable ? "" : ($astable || $table).$TSEP).$_ } (@{getAffectedColumns($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}, 0, $all, $selectQuestion)}))];
}

sub getColumnsForTableRecursive {
   my $self = shift;
   my $table = shift;
   my $tableconnections = shift;
   my $return = [];
   foreach my $curtablelink ([$table], @{getLinkedTables($tableconnections)}) {
      my $curtable = $curtablelink->[0];
      my $curtablename = $curtablelink->[1] || $curtablelink->[0];
      foreach my $curcolumn (@{$self->getColumnsForTable($curtable, 1, 0, 1, $curtablename)}) {
         push(@$return, $curtablename.$TSEP.$curcolumn);
      }
   }
   return $return;
}

sub getLinkedTables {
   my $tableconnections = shift;
   return [map { [$_->{back} ? $_->{from} : $_->{to}, $_->{as}] } @{$tableconnections->{joins}}];
}

sub getSQLStringForTable {
   my $self = shift;
   my $param = shift;
   my $return = {};
   my $tableconnections = $self->searchTableConnections($param->{table}, $param->{tablebackrefs} ? 1 : 0)
      if ($self->{config}->{DB}->{tables}->{$param->{table}}->{nosimple} || !$param->{simple});

   # TODO:XXX:FIXME: DBD-CSV unterstützt nur ein JOIN... DOW!
   if ($tableconnections->{joins} && (scalar(@{$tableconnections->{joins}}) > 1) && ($self->{config}->{DB}->{type} =~ m,CSV,i)) {
      Log("Bei CSV Dateien ist nur eine einzelne Tabellenverknuepfung zulaessig! Loesche ".(scalar(@{$tableconnections->{joins}})-1)." Verknuepfungen.", $WARNING);
      $tableconnections->{joins} = [$tableconnections->{joins}->[0]];
   }

   # WHERE
   my @where = ();
   my @orderby = ();
   foreach my $curtablelink ([$param->{table}], @{getLinkedTables($tableconnections)}) {
      my $curtable = $curtablelink->[0];
      my $curtablename = $curtablelink->[1] || $curtablelink->[0];
      if ($self->{config}->{DB}->{tables}->{$curtable}->{prioorderby}) {
         my $tmporderby = (ref($self->{config}->{DB}->{tables}->{$curtable}->{prioorderby}) eq "ARRAY") ?
                               $self->{config}->{DB}->{tables}->{$curtable}->{prioorderby} :
                              [$self->{config}->{DB}->{tables}->{$curtable}->{prioorderby}] ;
         unshift(@orderby, @$tmporderby);
      }
      if ($self->{config}->{DB}->{tables}->{$curtable}->{orderby}) {
         my $tmporderby = (ref($self->{config}->{DB}->{tables}->{$curtable}->{orderby}) eq "ARRAY") ?
                               $self->{config}->{DB}->{tables}->{$curtable}->{orderby} :
                              [$self->{config}->{DB}->{tables}->{$curtable}->{orderby}] ;
         push(@orderby, @$tmporderby);
      }
      #Log("DEBUG:".join(";", @orderby).":", $WARNING);
      foreach my $curcolumn (@{$self->getColumnsForTable($curtable, 1, 0, 1, $curtablename)}) {
         foreach my $curfilter (keys(%{$param->{filter}})) {
            my $curcolumndef = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$curtable}->{columns}->{$curcolumn});
            my $thevalorg = $param->{filter}->{$curfilter};
            next unless defined($thevalorg);
            # TODO:XXX:FIXME: Das sollte als Eigeschaft gehen, $self->{config}->{DB}->{csv}, und nicht als RegExpr aufn DBtypen...
            if (($self->{config}->{DB}->{type} =~ m,CSV,i) && (($curcolumndef->{type} eq "date") || ($curcolumndef->{type} eq "datetime"))) {
               $thevalorg = str2time($thevalorg);
            }
            my $vals = (ref($thevalorg) eq "ARRAY") ? $thevalorg : [$thevalorg];
            my @curwhere = ();
            foreach my $curthevalorg (@$vals) {
               my $theval = normaliseLine($curthevalorg,1);
               foreach (["", ($curcolumndef->{instr} ?
                             ("INSTR(".$curfilter.", ".$theval.")", "!=", "0") :
                             # TODO:XXX:FIXME: Das sollte als Eigeschaft gehen, $self->{config}->{DB}->{csv}, und nicht als RegExpr aufn DBtypen...
                             (($self->{config}->{DB}->{type} =~ m,CSV,i) && ($curcolumndef->{type} eq "text")) ?
                             ("REGEX(".$curfilter.",".normaliseLine("/".$curthevalorg."/i",1).")", "IS", "TRUE") :
                             ((($curcolumndef->{type} eq "date") || ($curcolumndef->{type} eq "datetime")) && !$curthevalorg) ?
                             () :
                             ($curfilter, undef, $theval)) ],
                        ["_begin", $curtablename.$TSEP.$curcolumn, ">", $theval],
                        ["_end", $curtablename.$TSEP.$curcolumn, "<", $theval]) {
                  #print $curfilter." CMP ".$curtable.$TSEP.$curcolumn.$_->[0]."\n";
                  push(@curwhere, "(".$_->[1]." ".($_->[2] || $curcolumndef->{"dbcompare"} || "=")." ".$_->[3].")")
                     if ((scalar(@$_) > 1) && ($curfilter eq $curtablename.$TSEP.$curcolumn.$_->[0]));
               }
            }
            push(@where, "(".join(" OR ", @curwhere).")")
               if (scalar(@curwhere));
         }
      }
   }
   # Nur bestimmte ID? -> Entsprechendes WHERE fabrizieren.
   my $tabledef = $self->{config}->{DB}->{tables}->{$param->{table}};
   @where = ("(".join(($param->{filter}->{orsearch} ? " OR ":" AND "), @where).")") if scalar(@where);
   if ($param->{id} && $tabledef->{columns}->{$self->getIdColumnName($param->{table})}) {
      my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $tabledef->{columns}->{$self->getIdColumnName($param->{table})});
      my $conjunction = $curcolumn->{"dbcompare"} || "=";
      push(@where, "(".$param->{table}.$TSEP.$self->getIdColumnName($param->{table})." ".$conjunction." '".$param->{id}."')");
   }
   # Wird deleted selbst gefiltert? -> Wenn nein, entsprechendes WHERE fabrizieren.
   if ((!$param->{nodeleted}) && $tabledef->{columns}->{$DELETEDCOLUMNNAME} &&
      (!grep { $_ eq $param->{table}.$TSEP.$DELETEDCOLUMNNAME } (keys(%{$param->{filter}})))) {
      my $curcolumn = mergeColumnInfos($self->{config}->{DB}, $tabledef->{columns}->{$DELETEDCOLUMNNAME});
      my $conjunction = $curcolumn->{"dbcompare"} || "=";
      push(@where, "(".$param->{table}.$TSEP.$DELETEDCOLUMNNAME." ".$conjunction." '0')");
   }

   my @alltables = @{$self->getColumnsForTableRecursive($param->{table}, $tableconnections)};

   # GROUPBY
   my @groupByList = ();
   if (defined($param->{groupby})) {
      Log("DBBackend: getSQLStringForTable: Bad group-by column: ".$param->{groupby}, $ERROR)
         unless scalar(@groupByList = grep { ($param->{groupby} eq $_) } @alltables);
   }

   push(@groupByList, $param->{table}.$TSEP.$self->getIdColumnName($param->{table}))
      if ($param->{onlymax});
   
   # SORTBY
   unshift(@orderby, split(",", $param->{orderby})) if $param->{orderby};
   unshift(@where, grep { $_ } @{$param->{where}}) if ($param->{where} && (ref($param->{where}) eq "ARRAY") && scalar(@{$param->{where}}));
   # TODO/FIXME/XXX: Bei virutal Spalten wird im MOment das Sortieren ignoriert. Es sollte dann eine Ersatzspalte in $DB konfigurierbar sein.
   my @sortByList = map {
      s/\_$/ DESC/; $_
   } grep {
      my $curorderby = $_;
      (grep { ($curorderby eq $_) ||
              ($curorderby eq $_."_") } @alltables) ? 1 :
         (Log("DBBackend: getSQLStringTable: ".$param->{table}.": Removing not available sortby :".$_.":", $INFO) & 0)
   } (@orderby);

   #my $usedtables = {};

   return [
      # Spalten der ANDEREN gelinkten Tabellen
      join(", ", (map { $self->getSelectColumnsForTable($_->[0], 0, 1, $_->[1], $param->{onlymax}) } @{getLinkedTables($tableconnections)})),
      # Spalten der EIGENEN Tabelle
      $self->getSelectColumnsForTable($param->{table}, $param->{all} || 0, 1),   
      # JOINS
      join(" LEFT JOIN ", ($param->{table}, (map {
         my $a = ($_->{back} ? $_->{sourceas} || $_->{to} : $_->{as} || $_->{to}).$TSEP.$self->getIdColumnName($_->{to});
         my $b = ($_->{back} ? $_->{as} || $_->{from} : $_->{sourceas} || $_->{from}).$TSEP.($_->{column}||Log("No column in join!", $ERROR));
         ($_->{back} ? $_->{from} : $_->{to}).($_->{as} ? " AS ".$_->{as} : '')." ON ".$a."=".$b
      #} grep {
      #   # Schmeisst bereits mehrfach verlinkte Tabellen raus.
      #   !$usedtables->{($_->{back} ? $_->{from} : $_->{to})}++
      } @{$tableconnections->{joins}}))),
      # Where
      join(" AND ", @where),   
      # SortBy
      join(", ", @sortByList),   
      # GroupBy
      join(", ", @groupByList),
   ];
}

sub makeEvilGood {
   my $self = shift;
   my $table = shift;

   unless ($self->{dbm}) {
      Log("DBBackend: makeEvilGood: You must first open a database connection!", $ERROR);
      return undef;
   }

   unless ($table && (ref($self->{config}->{DB}->{tables}->{$table}) eq "HASH")) {
      Log("DBBackend: makeEvilGood: Unknown or missing table '".$table."'!",$ERROR);
      return undef;
   }
   return normaliseLine($table);
}

sub makeEvilColumnDataGood {
   my $self = shift;
   my $table = shift;
   my $columns = shift;
   my $allColumnsMustBeThere = shift || 0;

   return undef unless ($table = makeEvilGood($self, $table));

   unless ((ref($columns) eq "HASH") && scalar(keys(%$columns))) {
      Log("DBBackend: makeEvilColumnDataGood: Column data is missing!", $ERROR);
      return 0;
   }

   # Virtual Spalten raus.
   foreach my $column (keys %$columns) {
      my $splited = undef;
      # TODO:FIXME:XXX: \. -> $TSEP irgendwann mal...
      if (($splited = [split(/\./, $column)]) && ($splited->[0] eq $table)) {
         if (exists($self->{config}->{DB}->{tables}->{$table}) &&
             exists($self->{config}->{DB}->{tables}->{$table}->{columns}->{$splited->[1]})) {
            my $curcolumndef = mergeColumnInfos($self->{config}->{DB}, $self->{config}->{DB}->{tables}->{$table}->{columns}->{$splited->[1]});
            delete $columns->{$column}
               if ($self->{config}->{DB}->{tables}->{$table}->{columns}->{$splited->[1]}->{type} =~ /^virtual$/i);
         }
      }      
   }

   if ($allColumnsMustBeThere) {
      @_ = grep { ((! exists($columns->{lc($_)})) && (!$self->{config}->{DB}->{tables}->{$table}->{columns}->{$_}->{secret})) && (!($_ eq $self->getIdColumnName($table)))} keys(%{$self->{config}->{DB}->{tables}->{$table}->{columns}});
      if (@_) {
         Log("DBBackend: makeEvilColumnDataGood: There are missing ".scalar(@_)." required column(s): ".'"'.join(",", @_).'"', $ERROR);
         return undef;
      }
   }

   my $columnsGood = normaliseDBArray([keys(%$columns)],[map { $table.$TSEP.$_ } keys(%{$self->{config}->{DB}->{tables}->{$table}->{columns}})]);
   my $valuesGood = normaliseDBArray([values(%$columns)]);

   # normaliseDBArray hat evtl. Columns rausgeschmissen, das m�ssen
   # wir hier abfangen.
   if (scalar(@{$columnsGood}) != scalar(@{$valuesGood})) {
      Log("DBBackend: makeEvilColumnDataGood: There are ".scalar(@{$columnsGood}).
                       " VALID Columns but ".scalar(@{$valuesGood})." values!", $ERROR);
      return undef;
   }
   return [$columnsGood, $valuesGood];
}

sub normaliseDBArray {
   my $array = shift;
   my $columns = shift || undef;

   if ($columns) {
      unless ((ref($columns) eq "ARRAY") && scalar(@{$columns})) {
         Log("DBBackend: normaliseDBArray: Unknown COLUMN Format Reference: Skipping ALL!", $WARNING);
         return [];
      }
   }
   return [#map { normaliseLine($_, $columns ? 0 : 1 ) }
           grep{
      my $ok = 1;
      if ($columns) {
         $ok = 0;
         foreach my $arr (@{$columns}) {
            if (lc($_) eq lc($arr)) {
               $ok = 1;
               last;
            }
         }
         Log("DBBackend: normaliseDBArray: Skipping unknown column ".$_, $WARNING) unless $ok;
      }
      $ok;
   } @$array];
}

1;
