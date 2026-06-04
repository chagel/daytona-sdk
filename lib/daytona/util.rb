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
  end
end
