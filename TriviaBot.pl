#!/usr/bin/perl -w

#################################################################################
# TriviaBot.pl                                                                  #
#                                                                               #
# connects to IRC and runs a triviaBot on the given channel                     #
#################################################################################

use Net::IRC;
use DBI;
use strict;

my $irc = new Net::IRC;
my $dbh = DBI->connect("dbi:SQLite:dbname=Trivia.db","","") or die "Can't open DB: $!";


my $botName = "dO__Ob";       # the bots nick for IRC
my $password = "trivia";      # the password for admining the bot
my $defaultQuestions = 10;    # default number of questions if not specified 

my $conn = $irc->newconn(
	Server 		=> shift || 'irc.freenode.net',      # the network to connect to
	Port		=> shift || '6667',                  # the port to use for the connection
	Nick		=> $botName,
	Ircname		=> 'A RevenanTrivia Bot',
	Username	=> 'bot'
);

$conn->{channel} = shift || '#l2l';                  # the channel to join on successful connect



my $triviaStatus = 0;
my $numQuestions = 0;
my $questionAsked = 0;
my $answer;
my $qNum = 0;
my $startTime;
my $totalQuestions;
my $hint;
my $qPoints;

sub on_connect {

	# shift in our connection object that is passed automatically
	my $conn = shift;

	$conn->join($conn->{channel});
	$conn->privmsg($conn->{channel}, 'It\'s trivia time!');
	$conn->{connected} = 1;
	
	# get total number of questions in database
	my $sth = $dbh->prepare(qq{SELECT max(id) FROM questions});
	$sth->execute() or die $dbh->errstr;

	my @result = $sth->fetchrow_array();
	$totalQuestions = $result[0];
	$sth->finish();
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
		show_scores($conn);
	}

	if($triviaStatus == 1)
	{
		# convert to same case
		$text = lc $text;
		$answer = lc $answer;
	
		# check if it's the answer
		if($text eq $answer)
		{
			$conn->privmsg($conn->{channel}, $event->{nick}." is awarded " . $qPoints . " points for the answer: " . $answer);
			$questionAsked = 0;
			award_points($conn, $event->{nick}, $qPoints);
			$numQuestions--;
			
			if($numQuestions == 0)
			{
				$conn->privmsg($conn->{channel}, "Stopping Trivia: Round of " . $qNum . " questions over." );
				show_scores($conn);
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
		$qPoints = 4;
		$startTime = time;
		ask_question($conn);
	}
	
	if(get_seconds() > 60 && $questionAsked == 1)
	{
		$conn->privmsg($conn->{channel}, "Time up! The answer was " . $answer );
		$questionAsked = 0;
		$numQuestions--;
		
		if($numQuestions == 0 )
		{
			$conn->privmsg($conn->{channel}, "Stopping Trivia: Round of " . $qNum . " questions over." );
			show_scores($conn);
			$triviaStatus = 0;
		}
	}
	
	if((get_seconds() == 10 || get_seconds() == 20 || get_seconds() == 30) && $questionAsked == 1)
	{
		show_hint($conn);
		$qPoints--;
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
	
	my $question_number = rand($totalQuestions) + 1; 
	$question_number = int $question_number;
	
	# get and echo the question
	my $sth = $dbh->prepare(qq{SELECT question,answer FROM questions WHERE id = $question_number});
	$sth->execute() or die $dbh->errstr;

	my $result = $sth->fetchrow_hashref();
	$answer = $result->{answer};
	
	if($result->{question} eq "" || $answer eq "")
	{
		# null question or answer, pick a new one
		ask_question();
	}
	else
	{
		$hint = "";
		$conn->privmsg($conn->{channel}, $qNum . ') ' . $result->{question});
	}

	$sth->finish();
		
}

# show a hint
sub show_hint {
	my $conn = shift;
	my $prevHint = $hint;
	my $answerLen = length($answer);
	my $revealCount;
	my @hintArr;
	my $revealIndex;
	
	
	# create the hint
	if($prevHint eq "")
	{
		@hintArr = split(//, $answer);
		
		for(my $i = 0; $i < $answerLen; $i++)
		{
			if($hintArr[$i] ne " ")
			{
				$hintArr[$i] = "*";
			}
		}
	}
	else
	{
		@hintArr = split(//, $prevHint);
	}
	
	my @wordArr = split(//, $answer);
	
	my $counter;
	for(my $i=0; $i<$answerLen; $i++)
	{
		if($hintArr[$i] eq "*")
		{
			$counter++;
		}
	}
	
	# get the number of letters to reveal
	$revealCount = $counter * 0.45;

	# reveal letters in the hint
	while($revealCount > 0)
	{
		$revealIndex = rand($answerLen);
		$revealIndex = int $revealIndex;

		if($hintArr[$revealIndex] eq "*")
		{
			$hintArr[$revealIndex] = $wordArr[$revealIndex];
			$revealCount--;
		}
		else
		{
			# go find the next possible spot to reveal
			while(1)
			{
				$revealIndex++;
		
				if($revealIndex == $answerLen)
				{
					$revealIndex = 0;
				}
		
				if($hintArr[$revealIndex] eq "*")
				{
					$hintArr[$revealIndex] = $wordArr[$revealIndex];
					$revealCount--;
					last;					
				}
			}
		}
	}
	
	$hint = join('',@hintArr);
	$conn->privmsg($conn->{channel}, "Here's a hint: " . $hint );
	
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
	my $conn = shift;

	my $sth = $dbh->prepare(qq{SELECT * FROM players ORDER BY score DESC});
	$sth->execute() or die $dbh->errstrl;
	#my $result = $sth->fetchrow_hashref();
	my $msg = "The top scoring players are: ";
	
	my $i = 0;
	
	my( $player, $score);
	$sth->bind_columns(\$player, \$score);

	while($sth->fetch() && $i < 3)
	{
		if($player ne "" || $score ne "")
		{
			if($i < 2)
			{
				$msg .= $player . " with " . $score . ", ";
			}
			else
			{
				$msg .= "and " . $player . " with " . $score . ".";
			}
		}
		$i++;
	}
	
	$conn->privmsg($conn->{channel}, $msg);
	$sth->finish();
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
	
	# this causes a really annoying warning while running
	$irc->do_one_loop();
}