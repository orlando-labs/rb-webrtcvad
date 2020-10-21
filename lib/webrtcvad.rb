# frozen_string_literal: true

require 'webrtcvad/webrtcvad'

module WebRTC
  class Vad
    def classify(buf:, sample_rate:, offset: 0, samples_count: (buf.size - offset).div(2))
      raise ArgumentError, 'Length exceeds buffer length' if samples_count > (buf.size - offset).div(2)

      process(sample_rate, buf, offset, samples_count)
    end
  end
end
