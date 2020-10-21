# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'

$CFLAGS = '-Wall -Werror -I./webrtc -Wno-unused-function'
$CXXFLAGS = '-std=c++11 -Wall -Werror -I./webrtc'

$CC = 'gcc'
$CXX = 'g++'

dirs = %w[webrtc/common_audio/signal_processing webrtc/common_audio/third_party webrtc/common_audio/vad]

$srcs = [
  'webrtcvad.c',
  *dirs.map { |d| Dir.glob "#{$srcdir}/#{d}/*.c" }.flatten,
  "#{$srcdir}/webrtc/rtc_base/checks.cc"
]

$VPATH += dirs.map { |d| "$(srcdir)/#{d}" }
$VPATH << '$(srcdir)/webrtc/rtc_base'

if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
  $defs += %w[-D_WIN32 -DWEBRTC_WIN]
else
  $defs << '-DWEBRTC_POSIX'
end

create_makefile 'webrtcvad/webrtcvad'
