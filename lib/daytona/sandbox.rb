# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  # Represents a Daytona Sandbox.
  #
  # A Sandbox is an isolated cloud development environment that can be used to
  # run code, execute commands, and manage files.
  #
  # @example Basic usage
  #   sandbox = client.create
  #
  #   # Execute commands
  #   response = sandbox.process.exec("echo 'Hello'")
  #   puts response.result
  #
  #   # Work with files
  #   sandbox.fs.upload_file("local.txt", "/home/user/remote.txt")
  #
  #   # Use git
  #   sandbox.git.clone("https://github.com/user/repo.git", "/home/user/repo")
  class Sandbox
    # @return [String] Unique identifier for the Sandbox
    attr_reader :id

    # @return [String] Name of the Sandbox
    attr_reader :name

    # @return [String] Organization ID of the Sandbox
    attr_reader :organization_id

    # @return [String] Snapshot used to create the Sandbox
    attr_reader :snapshot

    # @return [String] OS user running in the Sandbox
    attr_reader :user

    # @return [Hash{String => String}] Environment variables set in the Sandbox
    attr_reader :env

    # @return [Hash{String => String}] Custom labels attached to the Sandbox
    attr_reader :labels

    # @return [Boolean] Whether the Sandbox is publicly accessible
    attr_reader :public

    # @return [String] Target location of the runner
    attr_reader :target

    # @return [Integer] Number of CPUs allocated
    attr_reader :cpu

    # @return [Integer] Number of GPUs allocated
    attr_reader :gpu

    # @return [Integer] Memory allocated in GiB
    attr_reader :memory

    # @return [Integer] Disk space allocated in GiB
    attr_reader :disk

    # @return [String] Current state (started, stopped, error, etc.)
    attr_reader :state

    # @return [String, nil] Error message if in error state
    attr_reader :error_reason

    # @return [Boolean] Whether the error is recoverable
    attr_reader :recoverable

    # @return [Integer] Auto-stop interval in minutes
    attr_reader :auto_stop_interval

    # @return [Integer] Auto-archive interval in minutes
    attr_reader :auto_archive_interval

    # @return [Integer] Auto-delete interval in minutes
    attr_reader :auto_delete_interval

    # @return [Array] Volumes attached to the Sandbox
    attr_reader :volumes

    # @return [String] When the Sandbox was created
    attr_reader :created_at

    # @return [String] When the Sandbox was last updated
    attr_reader :updated_at

    # @return [Services::FileSystem] File system operations interface
    attr_reader :fs

    # @return [Services::Git] Git operations interface
    attr_reader :git

    # @return [Services::Process] Process execution interface
    attr_reader :process

    # @return [Services::ComputerUse] Desktop automation interface
    attr_reader :computer_use

    # @return [Services::CodeInterpreter] Code interpreter interface
    attr_reader :code_interpreter

    # Initialize a new Sandbox instance
    #
    # @param sandbox_data [Hash] Sandbox data from API
    # @param http_client [API::HttpClient] HTTP client for API calls
    # @param get_toolbox_url [Proc] Function to get toolbox URL
    def initialize(sandbox_data:, http_client:, get_toolbox_url:)
      @http_client = http_client
      @get_toolbox_url = get_toolbox_url
      @toolbox_url = nil

      process_sandbox_data(sandbox_data)
      initialize_services
    end

    # Refresh sandbox data from the API
    #
    # @example
    #   sandbox.refresh_data
    #   puts "State: #{sandbox.state}"
    def refresh_data
      response = @http_client.get("/sandbox/#{@id}")
      process_sandbox_data(response)
    end

    # Get the user's home directory path
    #
    # @return [String] Absolute path to user's home directory
    #
    # @example
    #   home = sandbox.get_user_home_dir
    #   puts "Home: #{home}"
    def get_user_home_dir
      ensure_toolbox_url!
      response = toolbox_get("/info/user-home-dir")
      response["dir"] || response[:dir]
    end

    # Get the working directory path
    #
    # @return [String] Absolute path to working directory
    #
    # @example
    #   workdir = sandbox.get_work_dir
    #   puts "Working directory: #{workdir}"
    def get_work_dir
      ensure_toolbox_url!
      response = toolbox_get("/info/work-dir")
      response["dir"] || response[:dir]
    end

    # Create a new LSP server instance
    #
    # @param language_id [String] Language server type (python, typescript, javascript)
    # @param path_to_project [String] Path to project root
    # @return [Services::LspServer] LSP server instance
    #
    # @example
    #   lsp = sandbox.create_lsp_server("python", "/home/user/project")
    def create_lsp_server(language_id, path_to_project)
      Services::LspServer.new(
        language_id: language_id,
        path_to_project: path_to_project,
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url
      )
    end

    # Set labels for the Sandbox
    #
    # @param labels [Hash{String => String}] Labels to set
    # @return [Hash{String => String}] Updated labels
    #
    # @example
    #   sandbox.set_labels("env" => "production", "team" => "backend")
    def set_labels(labels)
      string_labels = labels.transform_values { |v| v.is_a?(TrueClass) || v.is_a?(FalseClass) ? v.to_s.downcase : v.to_s }
      response = @http_client.put("/sandbox/#{@id}/labels", body: { labels: string_labels })
      @labels = response["labels"] || response[:labels] || string_labels
    end

    # Start the Sandbox
    #
    # @param timeout [Float] Maximum wait time in seconds (0 = no timeout)
    #
    # @raise [DaytonaError] If sandbox fails to start
    #
    # @example
    #   sandbox.start(timeout: 120)
    def start(timeout: 60)
      raise DaytonaError, "Timeout must be a non-negative number" if timeout.negative?

      start_time = Time.now
      @http_client.post("/sandbox/#{@id}/start", timeout: timeout.zero? ? nil : timeout)
      refresh_data

      remaining = timeout.zero? ? nil : [0.001, timeout - (Time.now - start_time)].max
      wait_for_start(timeout: remaining)
    end

    # Stop the Sandbox
    #
    # @param timeout [Float] Maximum wait time in seconds (0 = no timeout)
    #
    # @raise [DaytonaError] If sandbox fails to stop
    #
    # @example
    #   sandbox.stop(timeout: 60)
    def stop(timeout: 60)
      raise DaytonaError, "Timeout must be a non-negative number" if timeout.negative?

      start_time = Time.now
      @http_client.post("/sandbox/#{@id}/stop", timeout: timeout.zero? ? nil : timeout)
      refresh_data_safe

      remaining = timeout.zero? ? nil : [0.001, timeout - (Time.now - start_time)].max
      wait_for_stop(timeout: remaining)
    end

    # Delete the Sandbox
    #
    # @param timeout [Float] Request timeout in seconds
    #
    # @example
    #   sandbox.delete
    def delete(timeout: 60)
      @http_client.delete("/sandbox/#{@id}", timeout: timeout.zero? ? nil : timeout)
      refresh_data_safe
    end

    # Archive the Sandbox
    #
    # @example
    #   sandbox.archive
    def archive
      @http_client.post("/sandbox/#{@id}/archive")
      refresh_data
    end

    # Recover from a recoverable error
    #
    # @param timeout [Float] Maximum wait time in seconds
    def recover(timeout: 60)
      raise DaytonaError, "Timeout must be a non-negative number" if timeout.negative?

      start_time = Time.now
      @http_client.post("/sandbox/#{@id}/recover", timeout: timeout.zero? ? nil : timeout)
      refresh_data

      remaining = timeout.zero? ? nil : [0.001, timeout - (Time.now - start_time)].max
      wait_for_start(timeout: remaining)
    end

    # Wait for sandbox to reach started state
    #
    # @param timeout [Float, nil] Maximum wait time in seconds (nil = no timeout)
    #
    # @raise [DaytonaError] If sandbox fails to start or times out
    def wait_for_start(timeout: 60)
      start_time = Time.now

      until @state == "started"
        if timeout && (Time.now - start_time) >= timeout
          raise TimeoutError, "Sandbox #{@id} failed to start within #{timeout} seconds"
        end

        refresh_data

        return if @state == "started"

        if %w[error build_failed].include?(@state)
          raise DaytonaError, "Sandbox #{@id} failed to start with state: #{@state}, error: #{@error_reason}"
        end

        sleep 0.1
      end
    end

    # Wait for sandbox to reach stopped state
    #
    # @param timeout [Float, nil] Maximum wait time in seconds (nil = no timeout)
    #
    # @raise [DaytonaError] If sandbox fails to stop or times out
    def wait_for_stop(timeout: 60)
      start_time = Time.now

      until %w[stopped destroyed].include?(@state)
        if timeout && (Time.now - start_time) >= timeout
          raise TimeoutError, "Sandbox #{@id} failed to stop within #{timeout} seconds"
        end

        refresh_data_safe

        if %w[error build_failed].include?(@state)
          raise DaytonaError, "Sandbox #{@id} failed to stop with state: #{@state}, error: #{@error_reason}"
        end

        sleep 0.1
      end
    end

    # Set auto-stop interval
    #
    # @param interval [Integer] Minutes of inactivity before auto-stop (0 = disable)
    def set_autostop_interval(interval)
      raise DaytonaError, "Auto-stop interval must be a non-negative integer" if !interval.is_a?(Integer) || interval.negative?

      @http_client.put("/sandbox/#{@id}/autostop-interval", body: { interval: interval })
      @auto_stop_interval = interval
    end

    # Set auto-archive interval
    #
    # @param interval [Integer] Minutes before auto-archive (0 = max interval)
    def set_auto_archive_interval(interval)
      raise DaytonaError, "Auto-archive interval must be a non-negative integer" if !interval.is_a?(Integer) || interval.negative?

      @http_client.put("/sandbox/#{@id}/auto-archive-interval", body: { interval: interval })
      @auto_archive_interval = interval
    end

    # Set auto-delete interval
    #
    # @param interval [Integer] Minutes before auto-delete (negative = disable, 0 = immediate)
    def set_auto_delete_interval(interval)
      @http_client.put("/sandbox/#{@id}/auto-delete-interval", body: { interval: interval })
      @auto_delete_interval = interval
    end

    # Get preview link for a port
    #
    # @param port [Integer] Port number
    # @return [Hash] Preview link with url and token
    #
    # @example
    #   link = sandbox.get_preview_link(3000)
    #   puts "URL: #{link['url']}"
    def get_preview_link(port)
      @http_client.get("/sandbox/#{@id}/ports/#{port}/preview-url")
    end

    # Create SSH access token
    #
    # @param expires_in_minutes [Integer, nil] Token validity in minutes
    # @return [Hash] SSH access details
    def create_ssh_access(expires_in_minutes: nil)
      params = expires_in_minutes ? { expiresInMinutes: expires_in_minutes } : {}
      @http_client.post("/sandbox/#{@id}/ssh-access", body: params)
    end

    # Revoke SSH access token
    #
    # @param token [String] Token to revoke
    def revoke_ssh_access(token)
      @http_client.delete("/sandbox/#{@id}/ssh-access/#{token}")
    end

    # Validate SSH access token
    #
    # @param token [String] Token to validate
    # @return [Hash] Validation result
    def validate_ssh_access(token)
      @http_client.post("/sandbox/ssh-access/validate", body: { token: token })
    end

    # Refresh sandbox activity timestamp
    def refresh_activity
      @http_client.post("/sandbox/#{@id}/activity")
    end

    private

    def process_sandbox_data(data)
      # Guard against non-hash data (e.g., string or array responses)
      unless data.is_a?(Hash)
        raise DaytonaError, "Invalid sandbox data: expected Hash, got #{data.class}"
      end

      @id = data["id"] || data[:id]
      @name = data["name"] || data[:name]
      @organization_id = data["organizationId"] || data["organization_id"] || data[:organization_id]
      @snapshot = data["snapshot"] || data[:snapshot]
      @user = data["user"] || data[:user]
      @env = data["env"] || data[:env] || {}
      @labels = data["labels"] || data[:labels] || {}
      @public = data["public"] || data[:public]
      @target = data["target"] || data[:target]
      @cpu = data["cpu"] || data[:cpu]
      @gpu = data["gpu"] || data[:gpu]
      @memory = data["memory"] || data[:memory]
      @disk = data["disk"] || data[:disk]
      @state = data["state"] || data[:state]
      @error_reason = data["errorReason"] || data["error_reason"] || data[:error_reason]
      @recoverable = data["recoverable"] || data[:recoverable]
      @auto_stop_interval = data["autoStopInterval"] || data["auto_stop_interval"] || data[:auto_stop_interval]
      @auto_archive_interval = data["autoArchiveInterval"] || data["auto_archive_interval"] || data[:auto_archive_interval]
      @auto_delete_interval = data["autoDeleteInterval"] || data["auto_delete_interval"] || data[:auto_delete_interval]
      @volumes = data["volumes"] || data[:volumes] || []
      @created_at = data["createdAt"] || data["created_at"] || data[:created_at]
      @updated_at = data["updatedAt"] || data["updated_at"] || data[:updated_at]
    end

    def initialize_services
      @fs = Services::FileSystem.new(
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url
      )

      @git = Services::Git.new(
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url
      )

      @process = Services::Process.new(
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url,
        get_preview_link: method(:get_preview_link)
      )

      @computer_use = Services::ComputerUse.new(
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url
      )

      @code_interpreter = Services::CodeInterpreter.new(
        http_client: @http_client,
        sandbox_id: @id,
        get_toolbox_url: @get_toolbox_url
      )
    end

    def refresh_data_safe
      refresh_data
    rescue NotFoundError
      @state = "destroyed"
    end

    def ensure_toolbox_url!
      return if @toolbox_url

      @toolbox_url = @get_toolbox_url.call
      @toolbox_url = "#{@toolbox_url}/" unless @toolbox_url.end_with?("/")
      @toolbox_url = "#{@toolbox_url}#{@id}"
    end

    def toolbox_get(path)
      ensure_toolbox_url!
      url = "#{@toolbox_url}#{path}"

      # Create a new HTTP client for toolbox requests
      toolbox_client = API::HttpClient.new(
        base_url: @toolbox_url,
        api_key: @http_client.instance_variable_get(:@api_key),
        jwt_token: @http_client.instance_variable_get(:@jwt_token),
        organization_id: @http_client.instance_variable_get(:@organization_id)
      )
      toolbox_client.get(path)
    end
  end
end
