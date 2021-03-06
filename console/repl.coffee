#!/usr/bin/env coffee
readline = require 'readline'
{argv} = require 'optimist'
jvm = require '../src/jvm'
{read_classfile} = require './runner'

repl_run = (rs, cname, args) ->
  cname = cname[0...-6] if cname[-6..] is '.class'
  jvm.run_class rs, cname, args

read_stdin = (n_bytes, resume) ->
  process.stdin.resume()
  process.stdin.once 'data', (data) ->
    process.stdin.pause()
    resume data

if require.main == module
  # initialize the RuntimeState
  write_stdout = process.stdout.write.bind process.stdout
  rs = new runtime.RuntimeState(write_stdout, read_stdin, read_classfile)

  # create the REPL
  stdin = process.openStdin()
  repl = readline.createInterface stdin, process.stdout

  # set up handlers
  repl.on 'close', ->
    repl.output.write '\n'
    repl.input.destroy()
  repl.on 'line', (line) ->
    toks = line.split /\s+/
    if toks?[0]?.length > 0
      repl_run rs, toks[0], toks[1..]
      repl.output.write '\n'
    repl.prompt()

  # set the prompt, display it, and begin the loop
  repl.setPrompt 'doppio> '
  repl.prompt()
