use DBI;

use strict;
use warnings;
use DBDesign;
my $block = 100;

binmode(STDERR, ":utf8");
binmode(STDOUT, ":utf8");

my $wanted = $ARGV[0] ? [split(",", $ARGV[0])] : [keys(%{$DB->{tables}})];

syswrite(STDERR, "Starting backup...");
my $db = DBI->connect("DBI:".$DB->{type}.":".$DB->{name}.";host=".$DB->{host}, $DB->{user}->[0], $DB->{user}->[1]);
foreach (@$wanted) {
   my $table = $_;
   #next unless $table eq "kind";
   my $pos = 0;
   my $curblock = $block;
   #$curblock = 1 if ($table eq "kind");
   syswrite(STDERR, "\n".$table.":starting\r");
   while(1) {
      my $sth = $db->prepare("SELECT * FROM ".$table." LIMIT ".$pos.", ".$curblock.";");
      $sth->execute;
      my $found = 0;
      while (my $c = $sth->fetchrow_hashref) {
         syswrite(STDERR, $table.":".$pos.":".$c->{id}."      \r");
         $found++;
         my $columns = [keys %$c];
         $columns = [grep { $DB->{tables}->{$table}->{columns}->{$_}->{type} !~ m,^virtual$,i } keys %{$DB->{tables}->{$table}->{columns}}];
         print "INSERT INTO ".$table." (".join(",", @$columns).") VALUES (".join(",", map {
            if (defined($c->{$_})) {
               my $line = $c->{$_};
               if (($DB->{tables}->{$table}->{columns}->{$_}->{type} =~ m,^image$,) ||
                   ($line =~ m,[^a-zA-Z0-9\-\.\,\=\(\)\ü\ö\ä\Ü\Ö\Ä\s],)) {
                  $line = "x".chr(39).unpack("H*", $line).chr(39);
               } else {
                  $line =~ s,\',\'\',g;
                  $line = chr(39).$line.chr(39);
               }
               $line
            } else { 'NULL' }
         } @$columns).");\n";
      }
      $sth->finish;
      last unless $found;
      $pos += $curblock;
   }
}

syswrite(STDERR, "\nBackup done.\n");

