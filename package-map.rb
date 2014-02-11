#!/usr/bin/env ruby
# coding: utf-8
# © 2014 Chris Riddoch.  See LICENSES for terms

require 'set'
require 'memoize'
include Memoize

def provider_of(name)
  return Set.new if name.empty?
  cmd = ["/usr/bin/zypper", "--no-refresh", "search", "--match-exact","--provides", name]
  IO.popen(cmd, 'r') {|io|
    l =  io.readlines
    io.close
    l
  }.drop_while {|l| l !~ /^--\+-+\+-+\+-+/}.drop(1).map {|line|
     h = {}
     [:status, :name, :summary, :type].zip(line.chomp.split(/\s*\|\s*/)).each {|pair|
       n, v = *pair
       h[n] = v
     }
     h[:name] # Just return the name.
  }.to_set   # .tap {|o| puts "#{o.inspect} provides #{name}"} # debuggig
end

def requirements_of(name)
  IO.popen(["/usr/bin/zypper", "--no-refresh", "info", "--requires", name], 'r') {|io|
    l = io.readlines
    io.close
    l
  }.drop_while {|l| l !~ /^Requires:$/}.drop(1).map { |req|
    req.chomp!
    provider_of(req.chomp)
  }.to_set.flatten # .tap {|o| puts "Found: #{o.inspect}"}  # debugging
end

def graph_requirements_of(name, done, edges)
  todo = Set.new()
  new_edges = requirements_of(name).map {|req|
    todo.add(req) unless done.include?(req)
    [name, req] # return an edge
  }
  done.add(name)
  todo.delete(name)
  remaining_edges = todo.map {|req|
    next if done.include?(req)
    ret = graph_requirements_of(req, done, edges)
    done = ret[:done]
    ret[:edges]  # return recursed edges into remaining_edges.
  }

  # remaining edges is a list of edge-pairs, or possibly nils.
  {:edges => edges + new_edges + remaining_edges.flatten(1).reject {|a| a.nil?},
   :done => done}
end

memoize(:provider_of, "providers.cache")
memoize(:requirements_of, "requirements.cache")
memoize(:graph_requirements_of, "recursive_requirements.cache")

def usage
  puts "Usage: #{$0} <packagename>"
  exit
end

if ARGV.length < 1 or ARGV[0] == '--help'
  usage
else
  pkgname = ARGV[0]
end

out = File.open(pkgname + '_requirements.gv', 'w')
retval = graph_requirements_of(pkgname, Set.new(), [])
edges = retval[:edges]

# Remove loops of a package depending on itself
edges = edges.reject {|e| e[0] == e[1] }

out.puts("digraph packages {")

edges.to_a.sort.each {|e|
  out.puts "\"#{e[0]}\" -> \"#{e[1]}\""
}

out.puts("}")
out.close

system("dot", "-Tpdf", "-o#{pkgname}_graph.pdf", "#{pkgname}_requirements.gv")

