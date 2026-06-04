# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

# Core requires
require_relative "daytona/version"
require_relative "daytona/errors"
require_relative "daytona/configuration"
require_relative "daytona/util"

# API layer
require_relative "daytona/api/http_client"

# Models
require_relative "daytona/models/resources"
require_relative "daytona/models/code_language"
require_relative "daytona/models/volume_mount"
require_relative "daytona/models/create_params"
require_relative "daytona/models/execute_response"

# Services
require_relative "daytona/services/base_service"
require_relative "daytona/services/file_system"
require_relative "daytona/services/git"
require_relative "daytona/services/process"
require_relative "daytona/services/code_interpreter"
require_relative "daytona/services/computer_use"
require_relative "daytona/services/lsp_server"
require_relative "daytona/services/volume_service"
require_relative "daytona/services/snapshot_service"

# Image builder
require_relative "daytona/image"

# Core classes
require_relative "daytona/sandbox"
require_relative "daytona/client"

# Daytona SDK for Ruby
#
# Ruby SDK for interacting with Daytona sandboxes - cloud development environments.
# Note: This is an unofficial, community-maintained SDK.
#
# @example Basic usage with API key
#   client = Daytona::Client.new(api_key: "your-api-key")
#   sandbox = client.create
#
#   # Execute commands
#   response = sandbox.process.exec("echo 'Hello, World!'")
#   puts response.result
#
#   # Work with files
#   sandbox.fs.upload_file("local.txt", "/home/user/remote.txt")
#
#   # Clean up
#   client.delete(sandbox)
#
# @example Using environment variables
#   # Set DAYTONA_API_KEY in your environment
#   client = Daytona::Client.new
#   sandbox = client.create(name: "my-sandbox")
#
# @see https://www.daytona.io/docs/sdk Daytona SDK Documentation
module Daytona
  class << self
    # @return [Configuration, nil] Global configuration
    attr_accessor :configuration

    # Configure the Daytona SDK globally
    #
    # @yield [config] Configuration block
    # @yieldparam config [Configuration] Configuration instance
    #
    # @example
    #   Daytona.configure do |config|
    #     config.api_key = "your-api-key"
    #     config.api_url = "https://custom.daytona.io/api"
    #   end
    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
      configuration
    end

    # Reset global configuration
    def reset_configuration!
      self.configuration = nil
    end
  end
end
