use strict;
use warnings;

use DBDesign qw($DB);
use ADBGUI::BasicVariables;
use ADBGUI::Tools qw(:DEFAULT hashKeysRightOrder mergeColumnInfos Log);

sub openFileForWrite {
   my $filename = shift;

   unless (open(WFILE, ">".$filename)) {
      Log("UNABLE TO OPEN LOGFILE '".$filename."' !!! DYING NOW!", $ERROR);
      die();
   }
   return *WFILE;
}

sub writeMySQLScript {
   my $dbstate = shift,
   my $filename = shift;
   my $handle = $filename ? openFileForWrite($filename) : \*STDOUT;
   print $handle $DB->{$DB->{type}}->{pre} || $DB->{pre}
      unless ($dbstate =~ m,empty,);
   print $handle $DB->{$DB->{type}}->{dropDB}.$DB->{name}.";\n"
      if (($dbstate =~ m,dropdb,) && $DB->{type} && $DB->{$DB->{type}}->{dropDB});
   print $handle $DB->{$DB->{type}}->{createDB}.$DB->{name}.";\n"
      if ((($dbstate =~ m,createdb,) || ($dbstate =~ m,dropdb,)) && $DB->{type} && $DB->{$DB->{type}}->{createDB});
   print $handle $DB->{$DB->{type}}->{useDB}.$DB->{name}.";\n"
      if ($DB->{type} && $DB->{$DB->{type}}->{useDB});
   foreach my $table (hashKeysRightOrder($DB->{tables})) {
      print $handle "create table ".$table." (\n";
      my @tmp = ();
      my $space = '   ';
      my $curtabledef = $DB->{tables}->{$table};
      foreach my $column (hashKeysRightOrder($curtabledef->{columns})) {
         my $curcolumn = mergeColumnInfos($DB, $curtabledef->{columns}->{$column});
         next unless $curcolumn->{dbtype};
         my $line = '';
         my $comment = $curcolumn->{comment} || '';
         $comment = $space."# ".$comment if $comment;
         $comment = join("\n".$space."# ", split("\n", $comment)) if $comment;
         $line .= $comment."\n" if $comment;
         $line .= $space.$column;
         $line .= " ".$curcolumn->{dbtype};
         $line .= " NOT NULL" if $curcolumn->{notnull};
         $line .= " UNIQUE KEY" if $curcolumn->{uniq};
         $line .= " auto_increment" if $curcolumn->{auto_increment};
         push(@tmp, $line);
      }
      push(@tmp, $space."PRIMARY KEY (".join(", ", @{$curtabledef->{primarykey}}).")")
         if (scalar(@{$curtabledef->{primarykey}}));
      print $handle join(",\n",@tmp);
      print $handle "\n);\n";
   }
   foreach my $table (keys(%{$DB->{tables}})) {
      unless ($DB->{tables}->{$table} &&
              $DB->{tables}->{$table}->{rights} &&
         (ref($DB->{tables}->{$table}->{rights}) eq "ARRAY")) {
         print STDERR "WARNUNG: Tabelle ".$table." hat keine oder eine fehlerhafte Berechtigungsdefinition!\n";
         next;
      }
      print $handle "grant ".join(", ", @{$DB->{tables}->{$table}->{rights}})." on ".$DB->{name}.".".
            $table." TO ".$DB->{tables}->{$table}->{dbuser}->[0].'@'.$DB->{tables}->{$table}->{dbuser}->[2].
            " identified by '".$DB->{tables}->{$table}->{dbuser}->[1]."';\n";
   }
   print $handle $DB->{$DB->{type}}->{post} || $DB->{post}
      unless ($dbstate =~ m,empty,);
}

my $params = [@ARGV];

my $filename = undef;
my $dbstate = 0;
while (my $curparam = shift(@$params)) {
   if (($curparam =~ m/createdb/) ||
       ($curparam =~ m/dropdb/) ||
       ($curparam =~ m/empty/)) {
       $dbstate .= " " if $dbstate;
       $dbstate .= $curparam;
   } else {
       $filename = $curparam;   
   }
}

Log('$DB->{type} = "'.$DB->{type}.'"; Are you sure this is right?!', $WARNING) unless ($DB->{type} =~ /mysql/i);
writeMySQLScript($dbstate, $filename || undef);

