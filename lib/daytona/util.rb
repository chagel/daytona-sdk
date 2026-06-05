# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  # Internal helpers shared across services.
  module Util
    # The Daytona toolbox multiplexes a session command's stdout and stderr
    # into a single follow stream, tagging each run of bytes with a 3-byte
    # prefix. #demux splits a framed message back into [stdout, stderr].
    STDOUT_PREFIX = "\x01\x01\x01"
    STDERR_PREFIX = "\x02\x02\x02"
    PREFIX_LEN = STDOUT_PREFIX.bytesize

    # Split a multiplexed log message into its stdout and stderr parts.
    #
    # @param line [String] A raw (binary) message from the follow stream.
    # @return [Array(String, String)] [stdout, stderr]
    def self.demux(line)
      line = line.b
      out_parts = []
      err_parts = []
      state = nil
      pos = 0

      while pos < line.bytesize
        si = line.index(STDOUT_PREFIX, pos)
        ei = line.index(STDERR_PREFIX, pos)

        if si && (ei.nil? || si < ei)
          next_idx = si
          next_state = :stdout
        elsif ei
          next_idx = ei
          next_state = :stderr
        else
          case state
          when :stdout then out_parts << line[pos..]
          when :stderr then err_parts << line[pos..]
          end
          break
        end

        if pos < next_idx
          chunk = line[pos...next_idx]
          case state
          when :stdout then out_parts << chunk
          when :stderr then err_parts << chunk
          end
        end

        state = next_state
        pos = next_idx + PREFIX_LEN
      end

      [out_parts.join, err_parts.join]
    end

    # Stateful demultiplexer for the toolbox follow stream.
    #
    # The daemon tags runs of stdout/stderr with 3-byte prefixes, but a single
    # run can span multiple WebSocket frames: continuation frames carry no
    # prefix and must be attributed to the run still in progress, and a prefix
    # can itself be split across frames. #demux is stateless — fed a
    # continuation frame it resets to stdout and drops the leading bytes — so
    # large outputs (pi's message_update objects) get truncated. Demuxer keeps
    # the current stream and any partial trailing prefix across #feed calls.
    class Demuxer
      def initialize
        @stream = :stdout
        @pending = "".b
      end

      # Feed one frame's bytes; returns [stdout, stderr] for this frame.
      def feed(data)
        buf = @pending + data.to_s.b
        @pending = "".b
        out = "".b
        err = "".b
        pos = 0
        len = buf.bytesize

        while pos < len
          si = buf.index(STDOUT_PREFIX, pos)
          ei = buf.index(STDERR_PREFIX, pos)
          nxt = [ si, ei ].compact.min

          if nxt.nil?
            tail = buf.byteslice(pos, len - pos)
            hold = trailing_partial_prefix_len(tail)
            (@stream == :stderr ? err : out) << (hold.zero? ? tail : tail.byteslice(0, tail.bytesize - hold))
            @pending = tail.byteslice(tail.bytesize - hold, hold) if hold.positive?
            break
          end

          (@stream == :stderr ? err : out) << buf.byteslice(pos, nxt - pos) if nxt > pos
          @stream = nxt == si ? :stdout : :stderr
          pos = nxt + PREFIX_LEN
        end

        [ out, err ]
      end

      private

      # Length (0–2) of the trailing bytes that could be the start of a 3-byte
      # delimiter split across the frame boundary, to hold until the next feed.
      def trailing_partial_prefix_len(tail)
        n = tail.bytesize
        [ 2, n ].min.downto(1) do |k|
          chunk = tail.byteslice(n - k, k)
          return k if STDOUT_PREFIX.start_with?(chunk) || STDERR_PREFIX.start_with?(chunk)
        end
        0
      end
    end
  end
end
