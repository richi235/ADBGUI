#!/usr/bin/perl

use strict;
use warnings;

my $skeletondir = "install/skeleton/";
my $modulename = $ARGV[0];

unless ($modulename) {
   print "You need to specify the moudle name as paramter!\n";
   exit(1);
}

if (opendir(DIR, $skeletondir)) {
   mkdir($modulename);
   while (my $file = readdir(DIR)) {
      next unless -f $skeletondir.$file;
      print $file."...\n";
      if (open(IN, "<", $skeletondir.$file)) {
         if (open(OUT, ">", $modulename."/".$file)) {
            while (<IN>) {
               s,^package example::,package ${modulename}::,i;
               print OUT;
            }
            close(IN);
            close(OUT);
         } else {
            print "Error writing ".$modulename."/".$file.": ".$!;
            exit(1);
         }
      } else {
         print "Error reading ".$file.": ".$!;
         exit(1);
      } 
   }
   print "bilder/...\n";
   mkdir($modulename."/bilder/");
} else {
   print "Could not open skeleton dir: ".$!."\n";
   exit(1);
}

