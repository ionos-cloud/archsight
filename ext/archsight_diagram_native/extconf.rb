# frozen_string_literal: true

require "mkmf"

# The kernels are optional (lib/archsight/diagram/native.rb falls back to
# pure Ruby without them), so a machine that can't build them -- no C
# compiler, no Ruby headers -- or `ARCHSIGHT_DIAGRAM_NATIVE=0` gets a
# Makefile that builds nothing, instead of failing the whole gem install.
def skip_native(reason)
  message "archsight-diagram: #{reason}; using the pure-Ruby routing instead of the native kernels\n"
  File.write("Makefile", "all install clean distclean:\n\t@:\n")
  exit
end

skip_native("ARCHSIGHT_DIAGRAM_NATIVE=0 is set") if ENV["ARCHSIGHT_DIAGRAM_NATIVE"] == "0"

# The kernels must reproduce the pure-Ruby backend bit for bit (a
# last-ulp difference can flip a tie between two equally long candidate
# routes), so the arithmetic has to stay plain IEEE-754: no fused
# multiply-add contraction (clang contracts `a * b + c` by default on
# arm64) and no fast-math reassociation. `-O3` still auto-vectorizes the
# bounding-box prefilter loops with the target's baseline SIMD (SSE2 /
# NEON); `-march=native` is deliberately avoided so the build stays
# portable.
$CFLAGS << " -O3 -ffp-contract=off -fno-fast-math" # rubocop:disable Style/GlobalVars -- mkmf API

begin
  compiles = try_compile(File.read(File.join(__dir__, "archsight_diagram_native.c")))
rescue RuntimeError => e # mkmf's "You have to install development tools first."
  skip_native("no working C compiler (#{e.message.lines.first.strip})")
end
skip_native("the kernels don't compile here") unless compiles

create_makefile("archsight/diagram/archsight_diagram_native")
