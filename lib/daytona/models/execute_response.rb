# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  module Models
    # Response from command execution
    class ExecuteResponse
      # @return [Integer] Exit code of the command
      attr_reader :exit_code

      # @return [String] Output result (stdout)
      attr_reader :result

      # @return [ExecutionArtifacts] Execution artifacts (stdout and charts)
      attr_reader :artifacts

      def initialize(exit_code:, result:, artifacts: nil)
        @exit_code = exit_code
        @result = result
        @artifacts = artifacts || ExecutionArtifacts.new(stdout: result)
      end

      # Check if command was successful
      #
      # @return [Boolean]
      def success?
        @exit_code.zero?
      end

      # Create from API response hash
      #
      # @param data [Hash]
      # @return [ExecuteResponse]
      def self.from_hash(data)
        return nil if data.nil?

        new(
          exit_code: data["exitCode"] || data["exit_code"] || data[:exit_code] || 0,
          result: data["result"] || data[:result] || "",
          artifacts: ExecutionArtifacts.from_hash(data["artifacts"] || data[:artifacts])
        )
      end
    end

    # Execution artifacts containing stdout and chart data
    class ExecutionArtifacts
      # @return [String] Standard output from execution
      attr_reader :stdout

      # @return [Array<Hash>] Chart data extracted from execution
      attr_reader :charts

      def initialize(stdout: "", charts: [])
        @stdout = stdout
        @charts = charts || []
      end

      # Create from API response hash
      #
      # @param data [Hash]
      # @return [ExecutionArtifacts]
      def self.from_hash(data)
        return new if data.nil?

        new(
          stdout: data["stdout"] || data[:stdout] || "",
          charts: data["charts"] || data[:charts] || []
        )
      end
    end

    # Session execute request
    class SessionExecuteRequest
      # @return [String] Command to execute
      attr_accessor :command

      # @return [Boolean, nil] Whether to run async
      attr_accessor :run_async

      # @return [String, nil] Working directory
      attr_accessor :cwd

      # @return [Boolean, nil] Whether to enable PTY
      attr_accessor :pty

      # @return [Boolean, nil] Whether to suppress echoing of stdin (sent via
      #   Process#send_session_command_input) back into the command's output
      attr_accessor :suppress_input_echo

      def initialize(command:, run_async: nil, cwd: nil, pty: nil, suppress_input_echo: nil)
        @command = command
        @run_async = run_async
        @cwd = cwd
        @pty = pty
        @suppress_input_echo = suppress_input_echo
      end

      # Convert to hash for API requests
      #
      # @return [Hash]
      def to_h
        {
          command: @command,
          runAsync: @run_async,
          cwd: @cwd,
          pty: @pty,
          suppressInputEcho: @suppress_input_echo,
        }.compact
      end
    end

    # Session execute response
    class SessionExecuteResponse
      # @return [String] Command ID
      attr_reader :cmd_id

      # @return [String, nil] Output
      attr_reader :output

      # @return [Integer, nil] Exit code
      attr_reader :exit_code

      def initialize(cmd_id:, output: nil, exit_code: nil)
        @cmd_id = cmd_id
        @output = output
        @exit_code = exit_code
      end

      # Create from API response hash
      #
      # @param data [Hash]
      # @return [SessionExecuteResponse]
      def self.from_hash(data)
        return nil if data.nil?

        new(
          cmd_id: data["cmdId"] || data["cmd_id"] || data[:cmd_id],
          output: data["output"] || data[:output],
          exit_code: data["exitCode"] || data["exit_code"] || data[:exit_code]
        )
      end
    end
  end
end
