use warnings;
use strict;

use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT hashKeysRightOrder mergeColumnInfos);
use DBConfig;

sub openFileForWrite {
   my $filename = shift;

   unless (open(WFILE, ">".$filename)) {
      Log("UNABLE TO OPEN LOGFILE '".$filename."' !!! DYING NOW!", $ERROR);
      die();
   }
   return *WFILE;
}

sub writeMySQLScript {
   my $filename = shift;
   my $handle = openFileForWrite($filename);
   #my $handle = \*STDOUT;
   print $handle $DB->{$DB->{type}}->{pre} || $DB->{pre};
   foreach my $table (hashKeysRightOrder($DB->{tables})) {
      print $handle "CREATE TABLE ".$table." (\n";
      my @tmp = ();
      my $space = '   ';
      my $curtabledef = $DB->{tables}->{$table};
      foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
         my $curcolumn = mergeColumnInfos($DB, $curtabledef->{columns}->{$column});
         next unless $curcolumn->{dbtype};
         my $line = '';
         my $comment = $curcolumn->{comment} || '';
         $comment = $space."-- ".$comment if $comment;
         $comment = join("\n".$space."-- ", split("\n", $comment)) if $comment;
         $line .= $comment."\n" if $comment;
         $line .= $space.$column;
         $line .= " ".$curcolumn->{dbtype};
         $line .= " NOT NULL" if $curcolumn->{notnull};
         $line .= " UNIQUE" if $curcolumn->{uniq};
         $line .= " auto_increment" if $curcolumn->{auto_increment};
         $line .= " DEFAULT '".$curcolumn->{default}."'" if defined($curcolumn->{default});
         push(@tmp, $line);
      }
      push(@tmp, $space."PRIMARY KEY (".join(", ", @{$curtabledef->{primarykey}}).")")
         if (scalar(@{$curtabledef->{primarykey}}));
      print $handle join(",\n",@tmp);
      print $handle "\n);\n";
   }
   my $alreadyCreatedUsers = {};
   foreach my $table (keys(%{$DB->{tables}})) {
      unless (exists($alreadyCreatedUsers->{$DB->{tables}->{$table}->{dbuser}->[0]})) {
         print $handle "DROP USER ".$DB->{tables}->{$table}->{dbuser}->[0].";\n";
         print $handle "CREATE USER ".$DB->{tables}->{$table}->{dbuser}->[0].
                       " PASSWORD '".$DB->{tables}->{$table}->{dbuser}->[1]."';\n";
      }
      $alreadyCreatedUsers->{$DB->{tables}->{$table}->{dbuser}->[0]}++;
      print $handle "GRANT ".join(", ", @{$DB->{tables}->{$table}->{rights}})." on ".
            $table." TO ".$DB->{tables}->{$table}->{dbuser}->[0].";\n";
      print $handle "GRANT select, update on ".$table."_".$UNIQIDCOLUMNNAME."_seq TO ".$DB->{tables}->{$table}->{dbuser}->[0].";\n";
   }
   print $handle $DB->{$DB->{type}}->{post} || $DB->{post};
}

unless ($ARGV[0]) {
   Log("You didn't spedify a filename!", $ERROR);
   die;
}

Log('$DB->{type} = "'.$DB->{type}.'"; Are you sure this is right?!', $WARNING) unless ($DB->{type} =~ /postgres/i);
writeMySQLScript($ARGV[0]);
