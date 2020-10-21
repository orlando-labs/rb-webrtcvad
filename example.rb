require 'wavefile'
require 'webrtcvad'
require 'optparse'

options = {
  threshold: 0.9,
  voting_pool_size: 10,
  window_duration_ms: 30,
  agressiveness: 3
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} -f WAV_FILE [options]"

  opts.on('-f', '--file WAV_FILE', 'Path to source file') do |wav_file|
    options[:file] = wav_file
  end

  opts.on('-v', '--voting-pool POOL_SIZE', Integer, "Number of last frames used to calculate consensus, default: #{options[:voting_pool]}") do |pool_size|
    unless pool_size.positive?
      puts "Invalid voting pool size."
      puts opts
      exit 1
    end
    options[:voting_pool_size] = pool_size
  end
  
  opts.on('-t', '--threshold THR', Float, "Voting majority threshold (0.0..1.0), default: #{options[:threshold]}") do |thr|
    unless (0.0..1.0).include? thr
      puts "Invalid threshold."
      puts opts
      exit 1
    end
    options[:threshold] = thr
  end

  opts.on('-a', '--agressiveness RAGE', (0..3).to_a.map(&:to_s), "Non-speech cutout agressiveness, default: #{options[:agressiveness]}") do |rage|
    options[:aggressiveness] = rage.to_i
  end

  opts.on('-w', '--window-duration MSEC', [10, 20, 30], "Size of floating window, 10, 20 or 30 ms, default: #{options[:window_duration_ms]}") do |window|
    options[:window_duration_ms] = window
  end
end

parser.parse! into: options

unless options[:file]
  puts "No input wavefile specified"
  puts parser
  exit 1
end

reader = WaveFile::Reader.new(options[:file])
puts "  Channels:              #{reader.native_format.channels}"
puts "  Bits per sample:       #{reader.native_format.bits_per_sample}"
puts "  Samples per second:    #{reader.native_format.sample_rate}"
puts "  Sample frame count:    #{reader.total_sample_frames}"
puts "  Bytes per second:      #{reader.native_format.byte_rate}"
puts "  Sample Format:         #{reader.format.sample_format}"

NON_SPEECH = 0
SPEECH = 1

pack_code = WaveFile::PACK_CODES[reader.format.sample_format][reader.format.bits_per_sample]

vad = WebRTC::Vad.new options[:aggressiveness]

marks = Array.new(reader.native_format.channels) { Array.new(options[:voting_pool_size]) { [0, NON_SPEECH] } }
fragments = Array.new(reader.native_format.channels) { Array.new }
offset = 0

window_duration_ms = 30
window_samples = reader.native_format.sample_rate * window_duration_ms / 1000
window_bytes = window_samples * reader.native_format.bits_per_sample / 8

current_state = Array.new(reader.native_format.channels) { :non_speech }

reader.each_buffer(window_samples*10) do |buffer|
  samples = 
  if reader.native_format.channels == 1
    [buffer.samples.pack(pack_code)]
  else
    :zip
      .to_proc[*samples]
      .map { |frames| frames.pack pack_code }
  end

  samples.each.with_index.with_object(Array.new(reader.native_format.channels) { nil }) do |(buf, channel), remaining|
    if remaining[channel]
      buf.prepend remaining[channel]
      remaining[channel] = nil
    end
    
    (0..buf.length).step(window_bytes).map.with_index do |window_start, i|
      if buf.length - window_start < window_bytes and not vad.valid_frame?(reader.native_format.sample_rate, (buf.length - window_start).div(2))
        remaining[channel] = buf[window_start..-1]
        next
      end
      marks[channel].rotate! 1
      marks[channel][-1] = [
        offset + i * window_duration_ms, #ms
        vad.classify(
          buf: buf, 
          sample_rate: reader.native_format.sample_rate,
          offset: window_start,
          samples_count: window_samples
        )
      ]

      speech_slice = marks[channel].map(&:last).sum.to_f / options[:voting_pool_size]
      if current_state[channel] == :non_speech and speech_slice >= options[:threshold]
        fragments[channel] << [marks[channel].first.first, nil]
        current_state[channel] = :speech
      elsif current_state[channel] == :speech and speech_slice < options[:threshold]
        fragments[channel][-1][1] = marks[channel].last.first #frags may overlap, it's ok
        current_state[channel] = :non_speech
      end
    end
  end
  
  offset += buffer.samples.count * 1000 / reader.native_format.sample_rate
end

# finalize open fragments
fragments.each_with_index { |list, chan| list.last[1] ||= marks[chan].last.first }

puts "Found fragments:"
fragments.each_with_index do |frags, chan|
  puts "  Channel ##{chan}: #{frags}"
end
