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

# open the config file to setup the bot
CONFIG = YAML.load_file('config.yml')
DATABASE = "Trivia.db"

# try to open the database
begin 
  if File.exist?(DATABASE)
    db = SQLite3::Database.open DATABASE
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

on :channel do
  # fill this in with magic
end