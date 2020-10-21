# frozen_string_literal: true

dirs = %w[common_audio/signal_processing common_audio/third_party common_audio/vad]

c_srcs = [
  'ext/webrtcvad/webrtcvad.c',
  *dirs.map { |d| Dir.glob "ext/webrtcvad/webrtc/**/*.{c,h}" }.flatten,
  "ext/webrtcvad/webrtc/rtc_base/checks.cc"
]

Gem::Specification.new do |s|
  s.name = 'webrtcvad'
  s.required_ruby_version = '>= 2.4.0'
  s.version = '0.2.3'
  s.date = '2020-10-21'
  s.summary = 'WebRTC Voice Activity Detection library ruby wrapper'
  s.description = 'WebRTC Voice Activity Detection library ruby wrapper'
  s.authors = ['Ivan Razuvaev']
  s.email = 'i@orlando-labs.com'
  s.files = %w[lib/webrtcvad.rb] + c_srcs
  s.homepage = 'https://orlando-labs.com'
  s.license = 'MIT'
  s.extensions = %w[ext/webrtcvad/extconf.rb]
end
