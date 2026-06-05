# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

require "uri"
require "websocket-client-simple"

module Daytona
  module Services
    # Process execution for Sandbox
    #
    # Provides methods for executing commands and code within the Sandbox.
    #
    # @example
    #   # Execute a shell command
    #   response = sandbox.process.exec("ls -la")
    #   puts response.result
    #
    #   # Run Python code
    #   response = sandbox.process.code_run("print('Hello')", language: "python")
    #   puts response.result
    class Process < BaseService
      # Port the toolbox daemon's preview proxy listens on; the follow-logs
      # WebSocket is reached through the sandbox's preview URL for this port.
      WS_PORT = 2280

      # @param http_client [API::HttpClient] HTTP client
      # @param sandbox_id [String] Sandbox ID
      # @param get_toolbox_url [Proc] Function returning the toolbox base URL
      # @param get_preview_link [Proc, nil] Function (port) -> preview URL info,
      #   required only for #get_session_command_logs_async
      def initialize(http_client:, sandbox_id:, get_toolbox_url:, get_preview_link: nil)
        super(http_client: http_client, sandbox_id: sandbox_id, get_toolbox_url: get_toolbox_url)
        @get_preview_link = get_preview_link
      end

      # Execute a shell command
      #
      # @param command [String] Command to execute
      # @param cwd [String, nil] Working directory
      # @param env [Hash{String => String}, nil] Environment variables
      # @param timeout [Integer, nil] Command timeout in seconds
      # @return [Models::ExecuteResponse] Execution result with exit_code and output
      #
      # @example
      #   response = sandbox.process.exec("echo 'Hello, World!'")
      #   puts response.result  # => "Hello, World!\n"
      #   puts response.exit_code  # => 0
      #
      # @example With working directory and env
      #   response = sandbox.process.exec("npm test",
      #                                   cwd: "/home/user/project",
      #                                   env: { "NODE_ENV" => "test" })
      def exec(command, cwd: nil, env: nil, timeout: nil)
        body = { command: command }
        body[:cwd] = cwd if cwd
        body[:env] = env if env
        body[:timeout] = timeout if timeout

        # API endpoint is /process/execute (not /process/exec)
        response = toolbox_post("/process/execute", body: body, timeout: timeout || 120)
        Models::ExecuteResponse.from_hash(response)
      end

      # Run code in the Sandbox
      #
      # @param code [String] Code to execute
      # @param language [String] Programming language (python, javascript, typescript)
      # @param params [Hash, nil] Additional parameters
      # @param timeout [Integer, nil] Execution timeout
      # @return [Models::ExecuteResponse] Execution result
      #
      # @example
      #   response = sandbox.process.code_run("print('Hello')", language: "python")
      #   puts response.result
      def code_run(code, language: "python", params: nil, timeout: nil)
        body = {
          code: code,
          language: language,
        }
        body[:params] = params if params

        response = toolbox_post("/process/code-run", body: body, timeout: timeout || 120)
        Models::ExecuteResponse.from_hash(response)
      end

      # Create a new session
      #
      # @param session_id [String] Unique session identifier
      # @return [Hash] Session information
      #
      # @example
      #   session = sandbox.process.create_session("my-session")
      def create_session(session_id)
        # API endpoint is /process/session (singular, not /sessions)
        toolbox_post("/process/session", body: { sessionId: session_id })
      end

      # Get session information
      #
      # @param session_id [String] Session identifier
      # @return [Hash] Session information
      def get_session(session_id)
        toolbox_get("/process/session/#{session_id}")
      end

      # Execute command in a session
      #
      # @param session_id [String] Session identifier
      # @param request [Models::SessionExecuteRequest, Hash] Execution request
      # @param timeout [Integer, nil] Command timeout
      # @return [Models::SessionExecuteResponse] Execution response
      #
      # @example
      #   response = sandbox.process.execute_session_command("my-session", command: "ls -la")
      def execute_session_command(session_id, request, timeout: nil)
        body = request.is_a?(Hash) ? request : request.to_h
        response = toolbox_post("/process/session/#{session_id}/exec", body: body, timeout: timeout || 120)
        Models::SessionExecuteResponse.from_hash(response)
      end

      # Get command information from a session
      #
      # @param session_id [String] Session identifier
      # @param command_id [String] Command identifier
      # @return [Hash] Command information
      def get_session_command(session_id, command_id)
        toolbox_get("/process/session/#{session_id}/command/#{command_id}")
      end

      # Get command logs from a session
      #
      # @param session_id [String] Session identifier
      # @param command_id [String] Command identifier
      # @return [String] Command logs
      def get_session_command_logs(session_id, command_id)
        toolbox_get("/process/session/#{session_id}/command/#{command_id}/logs")
      end

      # List all sessions
      #
      # @return [Array<Hash>] List of sessions
      def list_sessions
        # Returns array of sessions directly (not wrapped in {"sessions": ...})
        toolbox_get("/process/session")
      end

      # Delete a session
      #
      # @param session_id [String] Session identifier
      def delete_session(session_id)
        toolbox_delete("/process/session/#{session_id}")
      end

      # Send input data to the stdin of a running session command.
      #
      # Use with a command started via {#execute_session_command} with
      # +runAsync: true+ to drive an interactive process (e.g. one reading
      # JSON-RPC from stdin).
      #
      # @param session_id [String] Session identifier
      # @param command_id [String] Command identifier (cmd_id from the exec response)
      # @param data [String] Bytes to write to the command's stdin
      # @return [Hash, nil] API response
      def send_session_command_input(session_id, command_id, data)
        toolbox_post(
          "/process/session/#{session_id}/command/#{command_id}/input",
          body: { data: data }
        )
      end

      # Stream a session command's logs as they are produced, demultiplexing
      # the combined follow stream into stdout/stderr callbacks. Blocks until
      # the command exits and the stream closes.
      #
      # Reaches the toolbox daemon's follow endpoint over a WebSocket via the
      # sandbox's preview URL for {WS_PORT}; +get_preview_link+ must have been
      # supplied when the service was constructed.
      #
      # @param session_id [String] Session identifier
      # @param command_id [String] Command identifier (cmd_id from the exec response)
      # @param on_stdout [Proc] Called with each stdout chunk (String)
      # @param on_stderr [Proc] Called with each stderr chunk (String)
      # @return [void]
      def get_session_command_logs_async(session_id, command_id, on_stdout:, on_stderr:)
        raise Daytona::DaytonaError, "get_preview_link is required for log streaming" unless @get_preview_link

        preview = @get_preview_link.call(WS_PORT)
        uri = URI.parse(preview_url(preview))
        uri.scheme = uri.scheme == "https" ? "wss" : "ws"
        uri.path = "/process/session/#{session_id}/command/#{command_id}/logs"
        uri.query = "follow=true"

        completion = Queue.new
        # The daemon only multiplexes this follow stream with the demux prefixes
        # Util.demux parses for clients advertising X-Daytona-SDK-Version
        # >= 0.167.0; below that it streams plain text and demux drops it.
        headers = {
          "Content-Type" => "text/plain",
          "Accept" => "text/plain",
          "X-Daytona-SDK-Version" => Daytona::VERSION
        }
        token = preview_token(preview)
        headers["X-Daytona-Preview-Token"] = token if token

        ws = WebSocket::Client::Simple.connect(uri.to_s, headers: headers)
        ws.on(:message) do |message|
          if message.type == :close
            ws.close
            completion.push(:close)
          else
            stdout, stderr = Util.demux(message.data.to_s)
            on_stdout.call(stdout) unless stdout.empty?
            on_stderr.call(stderr) unless stderr.empty?
          end
        end
        ws.on(:close) { completion.push(:close) }
        ws.on(:error) { |_e| completion.push(:error) }

        completion.pop
        nil
      end

      # Create a PTY (pseudo-terminal) session
      #
      # @param id [String] PTY session identifier
      # @param cwd [String, nil] Working directory
      # @param envs [Hash{String => String}, nil] Environment variables
      # @param pty_size [Hash, nil] PTY size { cols:, rows: }
      # @return [Hash] PTY session information
      #
      # @example
      #   pty = sandbox.process.create_pty_session("my-pty",
      #                                            cwd: "/home/user",
      #                                            pty_size: { cols: 80, rows: 24 })
      def create_pty_session(id, cwd: nil, envs: nil, pty_size: nil)
        body = { id: id }
        body[:cwd] = cwd if cwd
        body[:envs] = envs if envs
        body[:ptySize] = pty_size if pty_size

        toolbox_post("/pty", body: body)
      end

      # Connect to a PTY session (returns WebSocket URL)
      #
      # @param session_id [String] PTY session identifier
      # @return [String] WebSocket URL for PTY connection
      def connect_pty_session(session_id)
        ensure_toolbox_url!
        ws_url = @toolbox_url.sub(/^http/, "ws")
        "#{ws_url}/pty/#{session_id}/connect"
      end

      # List all PTY sessions
      #
      # @return [Array<Hash>] List of PTY sessions
      def list_pty_sessions
        response = toolbox_get("/pty")
        response["sessions"] || response[:sessions] || []
      end

      # Get PTY session information
      #
      # @param session_id [String] PTY session identifier
      # @return [Hash] PTY session information
      def get_pty_session_info(session_id)
        toolbox_get("/pty/#{session_id}")
      end

      # Kill a PTY session
      #
      # @param session_id [String] PTY session identifier
      def kill_pty_session(session_id)
        toolbox_delete("/pty/#{session_id}")
      end

      # Resize a PTY session
      #
      # @param session_id [String] PTY session identifier
      # @param pty_size [Hash] New size { cols:, rows: }
      def resize_pty_session(session_id, pty_size)
        toolbox_post("/pty/#{session_id}/resize", body: pty_size)
      end

      private

      # A preview link is a Hash from the REST API ({ "url", "token" }) — read
      # the URL tolerantly of string/symbol keys or an object response.
      def preview_url(preview)
        if preview.is_a?(Hash)
          preview["url"] || preview[:url]
        else
          preview.url
        end
      end

      def preview_token(preview)
        if preview.is_a?(Hash)
          preview["token"] || preview[:token]
        elsif preview.respond_to?(:token)
          preview.token
        end
      end
    end
  end
end
