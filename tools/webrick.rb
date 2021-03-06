#! /usr/bin/env ruby

require 'webrick'

include WEBrick

def start_webrick(config = {})
  server = HTTPServer.new(config)
  ['INT', 'TERM'].each {|signal|
    trap(signal) {server.shutdown}
  }
  server.start
end
  
if ARGV[0] == '--dev'
  puts "Starting WEBrick in dev mode"
  start_webrick(:DocumentRoot => "#{File.dirname __FILE__}/..",
                :Port         => 8000)
else
  start_webrick(:DocumentRoot => "#{File.dirname __FILE__}/../build",
                :Port         => 8000)
end
