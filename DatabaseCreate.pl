#!/usr/bin/perl -w

#################################################################################
# DatabaseCreate.pl                                                             #
#                                                                               #
# will read in questions from questions.txt and dump them into the database     #
################################################################################# 


use DBI;
use strict;

my $dbh = DBI->connect("dbi:SQLite:dbname=Trivia.db","","") or die "Can't open DB: $!";

open(DAT, "questions.txt") || die("Could not open file!"); 
my @raw_data=<DAT>;
close(DAT);

print "Starting transfer...\n";

foreach my $question (@raw_data)
{
	chomp($question);
	(my $q, my $a) = split(/\*/, $question);
	$q = $dbh->quote($q);
	$a = $dbh->quote($a);
	
	my $sql = qq{INSERT INTO questions (question,answer) values($q, $a)};
	print "About to execute [$sql]\n";
	
	$dbh->do($sql) or die $dbh->errstr;
} 

print "Transfer complete.\n";