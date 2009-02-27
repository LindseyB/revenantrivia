#!/usr/bin/perl -w

use Net::IRC;
use DBI;
use strict;

my $irc = new Net::IRC;
my $dbh = DBI->connect("dbi:SQLite:dbname=Trivia.db","","") or die "Can't open DB: $!";

my $botName = "dO__Ob";
my $password = "trivia";
my $defaultQuestions = 10;



my $triviaStatus = 0;
my $numQuestions = 0;
my $questionAsked = 0;
my $answer;
my $qNum = 0;
my $startTime;

my $conn = $irc->newconn(
	Server 		=> shift || 'irc.freenode.net',
	Port		=> shift || '6667',
	Nick		=> $botName,
	Ircname		=> 'A Test Bot',
	Username	=> 'bot'
);

$conn->{channel} = shift || '#l2l';

sub on_connect {

	# shift in our connection object that is passed automatically
	my $conn = shift;

	$conn->join($conn->{channel});
	$conn->privmsg($conn->{channel}, 'It\'s trivia time!');
	$conn->{connected} = 1;

}

sub on_join {

	# get our connection object and the event object, which is passed
	# with this event automatically
	my ($conn, $event) = @_;

	my $nick = $event->{nick};
	if($nick ne $botName)
	{
		$conn->privmsg($conn->{channel}, "Y halo thar, $nick!");
	}
}

sub on_part {
	# don't do anything
}

sub on_msg {

	my ($conn, $event) = @_;

	my $text = $event->{args}[0];

	if($text eq ("!quit ".$password))
	{
		$conn->privmsg($conn->{channel}, "Goodbai!");
		$dbh->disconnect;
		exit();
	}
}

sub on_public {

	my ($conn, $event) = @_;

	# check if we can start trivia
	my $text = $event->{args}[0];

	if ($text =~ m/^\!trivia\s*(\d*)/ && $triviaStatus == 0)
	{
		if($1 eq "")
		{
			$numQuestions = $defaultQuestions;
		}
		else
		{
			$numQuestions = $1;
		}
		
		$qNum = 0;
		$conn->privmsg($conn->{channel}, "Starting trivia round of $numQuestions questions.");
		$triviaStatus = 1;
	}

	if($text =~ m/^\!strivia/ && $triviaStatus == 1)
	{
		$conn->privmsg($conn->{channel}, "Stopping trivia...");
		$triviaStatus = 0;
	}

	if($text =~ m/^\!hof/)
	{
		# show scores
	}

	if($triviaStatus == 1)
	{
		# convert to same case
		$text = lc $text;
		$answer = lc $answer;
	
		# check if it's the answer
		if($text eq $answer)
		{
			$conn->privmsg($conn->{channel}, $event->{nick}." is awarded 1 point for the answer " + $answer);
			$questionAsked = 0;
			award_points($conn, $event->{nick}, 1);
			$numQuestions--;
			
			if($numQuestions == 0)
			{
				$conn->privmsg($conn->{channel}, "Round over." );
				$triviaStatus = 0;
			}
		}
	}
}

sub trivia_loop {
	my $conn = shift;
		
	if($questionAsked == 0)
	{
		$questionAsked = 1;
		$startTime = time;
		ask_question($conn);
	}
	
	if(get_seconds() > 30)
	{
		$conn->privmsg($conn->{channel}, "Time up! The answer was " . $answer );
		$questionAsked = 0;
		$numQuestions--;
	}
}

# get the number of seconds passed 
sub get_seconds {
	my $curTime = time;
	my $seconds = $curTime - $startTime;
	
	return $seconds;
}

# ask a question
sub ask_question {
	my $conn = shift;
	
	$qNum++;
	
	my $question_number = rand(10) + 1; 
	$question_number = int $question_number;
	
	# get and echo the question
	my $sth = $dbh->prepare(qq{SELECT question,answer FROM questions WHERE id = $question_number});
	$sth->execute() or die $dbh->errstr;

	my $result = $sth->fetchrow_hashref();
	$answer = $result->{answer};

	$conn->privmsg($conn->{channel}, $qNum . ') ' . $result->{question});

	$sth->finish();
		
}

# show a hint
sub show_hint {
	
}

# award points to the player
sub award_points {
	my $conn = shift;
	my $player = shift;
	my $points = shift;
	
	# check if player is in the database already
	my $sth = $dbh->prepare(qq{SELECT * FROM players WHERE player = '$player'});
	$sth->execute() or die $dbh->errstrl;
	my $result = $sth->fetchrow_hashref();
	my $curpoints = $result->{score};
	$sth->finish();

	if($curpoints eq "")
	{
		# insert the player and points
		$dbh->do(qq{INSERT INTO players values('$player', $points)}) or die $dbh->errstr;
	}
	else
	{
		# update the player's points
		$points += $curpoints;
		
		$sth = $dbh->prepare(qq{UPDATE players SET score = $points  WHERE player = '$player'});
		$sth->execute() or die $dbh->errstr;
		$sth->finish();	
	}
	
}

# show the scores
sub show_scores {

}

$conn->add_handler('join', \&on_join);
$conn->add_handler('part', \&on_part);
$conn->add_handler('public', \&on_public);
$conn->add_handler('msg', \&on_msg);

# The end of MOTD (message of the day), numbered 376 signifies we've connected
$conn->add_handler('376', \&on_connect);

# while bot is running handle the trivia and the irc 
while(1) {

	if($triviaStatus == 1)
	{
		trivia_loop($conn);
	}
	
	$irc->do_one_loop();
}