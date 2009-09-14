#!/usr/bin/perl -w

#################################################################################
# TriviaBot.pl                                                                  #
#                                                                               #
# connects to IRC and runs a triviaBot on the given channel                     #
#################################################################################

use Net::IRC;
use DBI;
use Time::HiRes qw( usleep gettimeofday tv_interval stat );
use strict;


my $irc = new Net::IRC;
my $dbh = DBI->connect("dbi:SQLite:dbname=Trivia.db","","") or die "Can't open DB: $!";

my $botName = "dO__Ob";       # the bots nick for IRC
my $password = "trivia";      # the password for admining the bot
my $defaultQuestions = 10;    # default number of questions if not specified 

my $conn = $irc->newconn(
	Server 		=> shift || 'irc.freenode.net',      # the network to connect to
	Port		=> shift || '8001',                  # the port to use for the connection
	Nick		=> $botName,
	Ircname		=> 'A RevenanTrivia Bot',
	Username	=> 'bot'
);

$conn->{channel} = shift || '##l2l';                  # the channel to join on successful connect



my $triviaStatus = 0;
my $numQuestions = 0;
my $questionAsked = 0;
my $answer;
my $qNum = 0;
my $startTime;
my $totalQuestions;
my $hint;
my $qPoints;
my $hintTime;
my $streakPlayer;
my $streak;
my $startTimep;

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
		
		my $sth = $dbh->prepare(qq{SELECT count(id) FROM questions});
		$sth->execute() or die $dbh->errstr;

		my @result = $sth->fetchrow_array();
		
		$qNum = 0;
		$streakPlayer = "";
		$conn->privmsg($conn->{channel}, "Starting trivia round of $numQuestions questions - $totalQuestions total.");
		$triviaStatus = 1;
		
		$sth->finish();
	}

	if($text =~ m/^\!strivia/ && $triviaStatus == 1)
	{
		$conn->privmsg($conn->{channel}, "Stopping trivia...");
		$triviaStatus = 0;
		$questionAsked = 0;
	}

	if($text =~ m/^\!hof/)
	{
		# show scores
		show_scores($conn);
	}
	
	if($text =~ m/^\!stats/)
	{
		# show individual states
		show_stats($event->{nick});
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
		$startTimep = [gettimeofday];
		$hintTime = time;
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
	
	if(get_seconds($hintTime) > 10 && $qPoints > 1)
	{
		show_hint($conn);
		$qPoints--;
		$hintTime = time;
	}

}


# get the number of seconds passed 
sub get_seconds {
	my $curTime = time;
	my $sTime = shift || $startTime;
	my $seconds = $curTime - $sTime;
	
	return $seconds;
}

# get the time for the answer (more exact)
sub get_answer_seconds {
	return tv_interval ($startTimep, [gettimeofday]);
}

# ask a question
sub ask_question {
	my $conn = shift;
	my $flag = 0;
	
	$qNum++;
	
	# get and echo the question
	my $sth = $dbh->prepare(qq{SELECT * FROM questions ORDER BY RANDOM() LIMIT 1});
	$sth->execute() or $flag = 1;

	my $result = $sth->fetchrow_hashref();
	$answer = $result->{answer};
	
	if($flag == 1)
	{
		# null question or answer, remove and pick a new one
		$dbh->do(qq{DELETE FROM questions where id = $result->{id} });
		$qNum--;
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
		$prevHint = $answer;
		$prevHint =~ tr/[a-zA-Z0-9]/\*/;
		@hintArr = split(//, $prevHint);
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
	
	if($streakPlayer ne $player)
	{
		$streakPlayer = $player;
		$streak = 1;
	}
	else
	{
		$streak++;
	}
	
	# check if player is in the database already
	my $sth = $dbh->prepare(qq{SELECT * FROM players WHERE player = '$player'});
	$sth->execute() or die $dbh->errstrl;
	my $result = $sth->fetchrow_hashref();
	my $curpoints = $result->{score};
	my $curtime = $result->{time};
	my $curstreak = $result->{streak};
	$sth->finish();
	
	my $answerTime = get_answer_seconds();

	if($curpoints eq "" || !defined($curpoints))
	{
		# insert the player and points
		$dbh->do(qq{INSERT INTO players values('$player', $points, 1, $answerTime)}) or die $dbh->errstr;
	}
	else
	{
		# update the player's points
		$points += $curpoints;
		
		if($streak > $curstreak)
		{
			$curstreak = $streak;
		}
		
		if($answerTime < $curtime)
		{
			$curtime = $answerTime; 
		}
		
		$sth = $dbh->prepare(qq{UPDATE players SET score = $points, time = $curtime, streak = $curstreak  WHERE player = '$player'});
		$sth->execute() or die $dbh->errstr;
		$sth->finish();
	
	}
	
}

sub show_stats {
	my $player = shift;
	
	my $sth = $dbh->prepare(qq{SELECT * FROM players WHERE player = '$player'});
	$sth->execute() or die $dbh->errstrl;
	my $result = $sth->fetchrow_hashref();
	#my $points = $result->{score};
	$sth->finish();
	
	if($result->{score} eq "")
	{
		$result->{score} = 0;
	}
	
	$conn->privmsg($conn->{channel}, $player . ": you have " . $result->{score} . " points, a streak of " . $result->{streak} . 
												" questions, and a record time of " . $result->{time}. " seconds.");
}

# show the scores
sub show_scores {
	my $conn = shift;

	my $sth = $dbh->prepare(qq{SELECT * FROM players ORDER BY score DESC});
	$sth->execute() or die $dbh->errstrl;
	
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
	
	# append the best time and streak
	$sth = $dbh->prepare(qq{SELECT * FROM players ORDER BY time ASC});
	$sth->execute() or die $dbh->errstrl;
	my $result = $sth->fetchrow_hashref();
	
	$msg .= " Best time " . $result->{time} ." by " . $result->{player} . ".";

	$sth = $dbh->prepare(qq{SELECT * FROM players ORDER BY streak DESC});
	$sth->execute() or die $dbh->errstrl;
	$result = $sth->fetchrow_hashref();
	
	$msg .= " Best streak " . $result->{streak} . " by " . $result->{player} . ".";
	
	$conn->privmsg($conn->{channel}, $msg);
	$sth->finish();
}

# delete all questions where there is no value in one or more of the fields
sub clean_db {
	$dbh->do(qq{DELETE FROM questions where id IS NULL OR question IS NULL OR answer IS NULL }) or die $dbh->errstrl;
}

$conn->add_handler('join', \&on_join);
$conn->add_handler('part', \&on_part);
$conn->add_handler('public', \&on_public);
$conn->add_handler('msg', \&on_msg);

# The end of MOTD (message of the day), numbered 376 signifies we've connected
$conn->add_handler('376', \&on_connect);

clean_db();

# while bot is running handle the trivia and the irc 
while(1) {

	if($triviaStatus == 1)
	{
		trivia_loop($conn);
	}
	
	# this causes a really annoying warning while running
	$irc->do_one_loop();
}
