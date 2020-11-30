require 'wavefile'
require 'webrtcvad'
require 'optparse'
require 'stringio'

options = {
  threshold: 0.9,
  voting_pool_size: 10,
  window_duration_ms: 30,
  agressiveness: 3
}

Fragment = Struct.new :from, :to, :io, :writer

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
    options[:agressiveness] = rage.to_i
  end

  opts.on('-w', '--window-duration MSEC', [10, 20, 30], "Size of floating window, 10, 20 or 30 ms, default: #{options[:window_duration_ms]}") do |window|
    options[:window_duration_ms] = window
  end

  opts.on('-s', '--save_fragments [DIR]', 'Save detected voice fragments, defaults to current directory') do |output_dir|
    options[:output_dir] = output_dir || '.'
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

vad = WebRTC::Vad.new options[:agressiveness]

marks = Array.new(reader.native_format.channels) { Array.new(options[:voting_pool_size]) { [0, NON_SPEECH] } }
fragments = Array.new(reader.native_format.channels) { Array.new }
offset_ms = 0

bytes_per_sample = reader.native_format.bits_per_sample / 8
window_duration_ms = 30
window_samples = reader.native_format.sample_rate * window_duration_ms / 1000
window_bytes = window_samples * bytes_per_sample

current_state = Array.new(reader.native_format.channels) { :non_speech }

reader.each_buffer(window_samples*10) do |buffer|
  samples = 
  if reader.native_format.channels == 1
    [buffer.samples.pack(pack_code)]
  else
    :zip
      .to_proc[*buffer.samples]
      .map { |frames| frames.pack pack_code }
  end

  samples.each.with_index.with_object(Array.new(reader.native_format.channels) { nil }) do |(buf, channel), remaining|
    if remaining[channel]
      buf.prepend remaining[channel]
      remaining[channel] = nil
    end
    
    (0..buf.length).step(window_bytes).map.with_index do |window_start, i|
      remaining_samples = (buf.length - window_start).div(bytes_per_sample)
      current_window_samples = [window_samples, remaining_samples].min

      if buf.length - window_start < window_bytes and not vad.valid_frame?(reader.native_format.sample_rate, remaining_samples)
        remaining[channel] = buf[window_start..-1]
        next
      end
      marks[channel].rotate! 1
      marks[channel][-1] = [
        offset_ms + i * window_duration_ms, #ms
        vad.classify(
          buf: buf, 
          sample_rate: reader.native_format.sample_rate,
          offset: window_start,
          samples_count: current_window_samples
        )
      ]

      speech_slice = marks[channel].map(&:last).sum.to_f / options[:voting_pool_size]
      if current_state[channel] == :non_speech and speech_slice >= options[:threshold]
        fragment = Fragment.new marks[channel].first.first
        if options[:output_dir]
          fragment.io = StringIO.new
          fragment.writer = WaveFile::Writer.new(fragment.io, WaveFile::Format.new(:mono, :pcm_16, reader.native_format.sample_rate))
        end
        fragments[channel] << fragment
        current_state[channel] = :speech
      end
      
      if current_state[channel] == :speech
        if speech_slice < options[:threshold]
          fragments[channel].last.to = marks[channel].last.first #frags may overlap, it's ok
          fragments[channel].last.writer.close if fragments[channel].last.writer
          current_state[channel] = :non_speech
        elsif options[:output_dir]
          frames = buf[window_start, current_window_samples*bytes_per_sample].unpack pack_code
          buffer = WaveFile::Buffer.new(frames, WaveFile::Format.new(:mono, :pcm_16, reader.native_format.sample_rate))
          fragments[channel].last.writer.write buffer
        end
      end
    end
  end
  
  offset_ms += samples.first.size / bytes_per_sample * 1000 / reader.native_format.sample_rate
end

# finalize open fragments
fragments.each_with_index do |list, chan|
  next if list.last.to
  list.last.to = marks[chan].last.first
  list.last.writer.close if list.last.writer
end

puts "Found fragments:"
fragments.each_with_index do |frags, chan|
  print_data = frags.map do |frag|
    if frag.writer
      filename = "fragment-#{chan}-#{frag.from}-#{frag.to}.wav"
      frag.io.rewind
      File.open(File.join(options[:output_dir], filename), 'wb') do |f|
        f.puts(frag.io.read)
      end
      [frag.from, frag.to, filename]
    else
      [frag.from, frag.to]
    end
  end
  puts "Channel ##{chan}:"
  puts "  #{print_data}"
end
