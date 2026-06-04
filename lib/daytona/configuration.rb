# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  # Configuration options for initializing the Daytona client.
  #
  # Configuration can be provided directly or via environment variables:
  # - DAYTONA_API_KEY: API key for authentication
  # - DAYTONA_JWT_TOKEN: JWT token for authentication (alternative to API key)
  # - DAYTONA_ORGANIZATION_ID: Organization ID (required with JWT token)
  # - DAYTONA_API_URL: API URL (defaults to https://app.daytona.io/api)
  # - DAYTONA_TARGET: Target runner location for the Sandbox
  #
  # @example Using API key
  #   config = Daytona::Configuration.new(api_key: "your-api-key")
  #
  # @example Using JWT token
  #   config = Daytona::Configuration.new(
  #     jwt_token: "your-jwt-token",
  #     organization_id: "your-org-id"
  #   )
  #
  # @example Using environment variables
  #   # Set DAYTONA_API_KEY in environment
  #   config = Daytona::Configuration.new
  class Configuration
    DEFAULT_API_URL = "https://app.daytona.io/api"

    # @return [String, nil] API key for authentication
    attr_accessor :api_key

    # @return [String, nil] JWT token for authentication
    attr_accessor :jwt_token

    # @return [String, nil] Organization ID for JWT-based authentication
    attr_accessor :organization_id

    # @return [String] URL of the Daytona API
    attr_accessor :api_url

    # @return [String, nil] Target runner location for the Sandbox
    attr_accessor :target

    # Initialize a new Configuration
    #
    # @param api_key [String, nil] API key for authentication
    # @param jwt_token [String, nil] JWT token for authentication
    # @param organization_id [String, nil] Organization ID for JWT auth
    # @param api_url [String, nil] URL of the Daytona API
    # @param target [String, nil] Target runner location
    # @param server_url [String, nil] Deprecated: use api_url instead
    def initialize(
      api_key: nil,
      jwt_token: nil,
      organization_id: nil,
      api_url: nil,
      target: nil,
      server_url: nil
    )
      # Handle deprecated server_url
      if server_url
        warn "[DEPRECATION] `server_url` is deprecated. Please use `api_url` instead."
        api_url ||= server_url
      end

      @api_key = api_key || ENV.fetch("DAYTONA_API_KEY", nil)
      @jwt_token = jwt_token || ENV.fetch("DAYTONA_JWT_TOKEN", nil)
      @organization_id = organization_id || ENV.fetch("DAYTONA_ORGANIZATION_ID", nil)
      @api_url = api_url || ENV.fetch("DAYTONA_API_URL", DEFAULT_API_URL)
      @target = target || ENV.fetch("DAYTONA_TARGET", nil)
    end

    # Check if configuration has valid authentication credentials
    #
    # @return [Boolean] true if api_key or jwt_token is present
    def authenticated?
      !@api_key.nil? || !@jwt_token.nil?
    end

    # Get the authentication token (API key or JWT token)
    #
    # @return [String, nil] The authentication token
    def auth_token
      @api_key || @jwt_token
    end

    # Check if using JWT authentication
    #
    # @return [Boolean] true if using JWT token
    def jwt_auth?
      @api_key.nil? && !@jwt_token.nil?
    end

    # Validate the configuration
    #
    # @raise [ConfigurationError] if configuration is invalid
    def validate!
      unless authenticated?
        raise ConfigurationError, "API key or JWT token is required. " \
                                  "Set DAYTONA_API_KEY or DAYTONA_JWT_TOKEN environment variable, " \
                                  "or pass api_key: or jwt_token: to Configuration.new"
      end

      if jwt_auth? && @organization_id.nil?
        raise ConfigurationError, "Organization ID is required when using JWT authentication. " \
                                  "Set DAYTONA_ORGANIZATION_ID environment variable, " \
                                  "or pass organization_id: to Configuration.new"
      end

      true
    end

    # Convert configuration to a hash
    #
    # @return [Hash] Configuration as a hash
    def to_h
      {
        api_key: @api_key,
        jwt_token: @jwt_token,
        organization_id: @organization_id,
        api_url: @api_url,
        target: @target,
      }
    end
  end
end
