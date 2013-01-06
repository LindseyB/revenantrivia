#################################################################################
# TriviaBot.rb                                                                  #
#                                                                               #
# connects to IRC and runs a triviaBot on the given channel                     #
#                                                                               #
# This program is free software. It comes without any warranty, to the extent   #
# permitted by applicable law. You can redistribute it and/or modify it under   #
# the terms of the Do What The Fuck You Want To Public License, Version 2, as   #
# published by Sam Hocevar. See http://sam.zoy.org/wtfpl/COPYING for more       #
# details.                                                                      #
#                                                                               #
#################################################################################

require 'isaac'
require 'yaml'
require 'sqlite3'
require 'pp'

# open the config file to setup the bot
CONFIG = YAML.load_file('config.yml')
DATABASE = "Trivia.db"
DEFUALT_QUESTIONS = 10

questions = 10
triviaRunning = false
answer = ""
questionsAsked = 0

# try to open the database
begin 
  if File.exist?(DATABASE)
    $db = SQLite3::Database.open DATABASE
  else
    # raise an error if the database isn't found since the
    # program won't run correctly with an empty database
    raise "Database file not found"
  end
rescue Exception => e
  # rescue any exceptions and abort the program
  puts e
  abort("Problem opening database, unable to proceed")
end

# connect to the server with a given nickname
configure do |c|
  c.nick    = CONFIG['nickname']
  c.server  = CONFIG['server']
  c.port    = CONFIG['port']
end

# join the channels upon connect
on :connect do
  CONFIG['channels'].each do |channel|
    puts "joining #{channel}"
    join channel
    msg channel, "It's trivia time!" # announce our presence
  end
end

# !trivia [num]
# start trivia round of specified questions or default (10)
on :channel, /^\!trivia\s*(\d*)/ do |num|
  # ignore the command if trivia is running
  if triviaRunning 
    return 
  end 

  if num.empty? 
    questions = DEFUALT_QUESTIONS
  else
    questions = num
  end

  msg channel, "Starting trivia round of #{questions} questions"
  triviaRunning = true # mark trivia as running
  questionsAsked = 0  # reset question counter
end

# !stop
# stop trivia from running
on :channel, /^\!stop/ do
  # ignore this command if trivia isn't running
  unless triviaRunning
    return
  end

  triviaRunning = false
  msg channel, "Stopping trivia round"
end

# !scores
# show top scoring players
on :channel, /^\!scores/ do
  show_scores
end

# !stats
# get individual stats for the player
on :channel, /^\!stats/ do
  show_stats(nick)
end


on :channel do
  # TODO: check for answers here
  questionsAsked += 1
  get_question(questionsAsked)
end

helpers do
  def get_question(questionsAsked)
    row = $db.execute('SELECT * FROM questions ORDER BY RANDOM() LIMIT 1')

    # grossssss, using array indexes like this is ugly
    msg channel, "Question #{questionsAsked}: #{row[0][1]}"
    answer = row[0][2]
  end

  def show_hint(answer, prevHint)
  end

  def award_points(player, points)
  end

  def show_stats(player)
  end

  def show_scores
  end

end