use DBI;
use ADBGUI::DBDesign;
use ADBGUI::Tools qw(mergeColumnInfos);
use ADBGUI::BasicVariables;

use strict;
use warnings;

my $tables = {};
my $tablesvals = {};

my $dbdesign = ADBGUI::DBDesign->new();

my $DB = $dbdesign->getDB();

my $DSTDB = {
   type => "mysql",
   name => $ARGV[0] || "saytrust",
   user => $ARGV[1] || "root",
   host => $ARGV[2] || "localhost",
   pass => $ARGV[3] || "",
};

my $db = DBI->connect("DBI:".$DSTDB->{type}.":".$DSTDB->{name}.";host=".$DSTDB->{host}, $DSTDB->{user}, $DSTDB->{pass});

my $sth = $db->prepare("show tables");
$sth->execute;

while (my $c = $sth->fetchrow_hashref) {
   my $table = $c->{"Tables_in_".$DSTDB->{name}};
   print STDERR $table."\n";
   my $sth2 = $db->prepare("show columns from ".$table);
   $sth2->execute;
   while (my $t = $sth2->fetchrow_hashref) {
      my $type = '"'.getMachingType($DB, $t->{Type}).'"';
      if (($t->{Extra} =~ m,auto_increment,)) { # && ($type eq "number")) {
         if ($tablesvals->{$table}->{idcolumnname}) {
            print STDERR "WARNING: Table ".$table.": Ignoring second autoincrement candidate '".$t->{Field}."'. The column '".$tablesvals->{$table}->{idcolumnname}."' has already been selected.\n";
         } else {
            $type = '$UNIQIDCOLUMNNAME';
            $tablesvals->{$table}->{idcolumnname} = $t->{Field};
         }
      }
      $tables->{$table}->{$t->{Field}} = {
         type => $type,
         name => $t->{Field},
         null => $t->{Null} ? 1 : 0,
         default => $t->{Default} || "",
      };
      #print STDERR "  ".join(",", map { $_."=".($t->{$_}||"UNDEF") } keys %$t)."\n";
   }
   #$tablesvals->{$table}->{rights} = '$RIGHTS';
   #$tablesvals->{$table}->{dbuser} = '$DBUSER';
   if (                    $tablesvals->{$table}->{idcolumnname} &&
       $tables->{$table}->{$tablesvals->{$table}->{idcolumnname}}) {
      $tablesvals->{$table}->{idcolumnname} = '"'.$tablesvals->{$table}->{idcolumnname}.'"';
   } else {
      print STDERR "WARNING: Table ".$table." has no idcolumn!\n"
   }
   $sth2->finish;
}
$sth->finish;

printHumanResult();

sub getSplitedVarname { 
   my $name = shift;
   my $num = undef;
   if ($name =~ m,^(\D+)\((\d+)\)$,) {
      $name = $1;
      $num = $2;
   }
   return {type => $name, len => $num};
}

sub getMachingType {
   my $DB = shift;
   my $name = shift;
   return "text" if ($name eq "text");
   my $var = getSplitedVarname($name);
   foreach my $curset (sort {
      (( $a->{var}->{type} cmp $b->{var}->{type} ) ||
      (( $a->{var}->{len} &&  $b->{var}->{len} ) ?
        ($a->{var}->{len} <=> $b->{var}->{len}) : 0) ||
      (( $b->{typedef}->{prioautodblayout}||0) <=>
       ( $a->{typedef}->{prioautodblayout}||0)))
   } map {
      {%$_, var => getSplitedVarname($_->{typedef}->{dbtype})}
   } grep { $_->{typedef}->{dbtype}
   } map { {typedef => mergeColumnInfos($DB, { type => $_ }),
            name    => $_}
   } keys %{$DB->{types}}) {
      my $vartype = $var->{type};
      #my $varlen  = $var->{len} || 0;
      #print STDERR "A".$curset->{var}->{type}."<->".$vartype."\n";
      if ($curset->{var}->{type} =~ m,^$vartype,i) {
         if (($var->{len}||0) <= ($curset->{var}->{len}||0)) {
            return $curset->{name};
         } else {
            #print STDERR "INFO: ".$name." is too big for ".$curset->{name}.". Trying next.\n";
         }
      }
      #print "DBTYPE:".$curset->{name}.":".$curset->{typedef}->{dbtype}.":\n";
      #print $t->{Field}." <-> ".
      #$t->{Type};
   }
   print STDERR "WARNING: '".$name."' cannot mapped to a dbtype of ADBGUI. Using as fallback 'text'.\n";
   return "text";
}

sub printSperateResult {
   foreach my $table (keys %$tables) {
      foreach my $column (sort { ($tables->{$table}->{$b}->{type} eq '$UNIQIDCOLUMNNAME') <=>
                                 ($tables->{$table}->{$a}->{type} eq '$UNIQIDCOLUMNNAME') } keys %{$tables->{$table}}) {
         my $curdef = $tables->{$table}->{$column};
         if ($tablesvals->{$table}) {
            print '   $DB->{tables}->{"'.$table.'"} = {'."\n";
            foreach my $curkey (keys %{$tablesvals->{$table}}) {
               print '      '.$curkey.' => '.$tablesvals->{$table}->{$curkey}.','."\n";
            }
            print '   };'."\n";
         }
         print '   $DB->{tables}->{"'.$table.'"}->{columns}->{"'.$column.'"} = {'."\n";
         print '      type => '.$curdef->{type}.','."\n";
         print '   };'."\n";
      }
   }
}

sub printHumanResult {
   foreach my $table (keys %$tables) {
      print '   $DB->{tables}->{"'.$table.'"} = {'."\n";
      if ($tablesvals->{$table}) {
         foreach my $curkey (keys %{$tablesvals->{$table}}) {
            print '      '.$curkey.' => '.$tablesvals->{$table}->{$curkey}.','."\n";
         }
      }
      #print '      rights => $RIGHTS,'."\n";
      #print '      dbuser => $DBUSER,'."\n";
      print '      columns => {'."\n";
      foreach my $column (sort { ($tables->{$table}->{$b}->{type} eq '$UNIQIDCOLUMNNAME') <=>
                                 ($tables->{$table}->{$a}->{type} eq '$UNIQIDCOLUMNNAME') } keys %{$tables->{$table}}) {
         my $curdef = $tables->{$table}->{$column};
         print '         "'.$column.'" => {'."\n";
         print '            type => '.$curdef->{type}.','."\n";
         print '         },'."\n";
      }
      print '      }'."\n";
      print '   };'."\n";
   }
}
