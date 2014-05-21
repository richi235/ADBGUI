use strict;
use JSON;
my $in = "";

my $jsonfile    = "myproject/config.json";
my $jsonfilenew = "myproject/config.json.new";

my $locale = $ENV{LANG} || "de";
$locale =~ s,\.UTF\-8$,,gi;

open(CONFIG, "<", $jsonfile) || die $!;

while(<CONFIG>) {
   chomp;
   s/(\/\/.*$)//;
   $in .= $_;
}

close(CONFIG);

$in =~ s,/\*[^\*]*\*/,,gm;

my $config = from_json( $in, { utf8  => 1 } );

if (ref($config->{let}->{LOCALES}) eq "ARRAY") {
   if (scalar(grep { lc($_) eq $locale } @{$config->{let}->{LOCALES}})) {
      print "Locales beinhaltet bereits '".$locale."'.\n";
   } else {
      push(@{$config->{let}->{LOCALES}}, $locale);
      open(CONFIG, ">", $jsonfilenew) || die $!;
      syswrite(CONFIG, to_json($config, { ascii => 1, pretty => 1 } ));
      close(CONFIG);
      rename($jsonfilenew, $jsonfile);
      print "Locales um '".$locale."' erweitert.\n";
   }
} else {
   die "Ungueltige Config; keine Locales!";
}

