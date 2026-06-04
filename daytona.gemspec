# frozen_string_literal: true

require_relative "lib/daytona/version"

Gem::Specification.new do |spec|
  spec.name = "daytona"
  spec.version = Daytona::VERSION
  spec.authors = ["Luo Tao"]
  spec.email = ["luotao@example.com"]

  spec.summary = "Ruby SDK for Daytona (Unofficial)"
  spec.description = "Unofficial Ruby SDK for interacting with Daytona sandboxes - cloud development environments. Not affiliated with Daytona Platforms Inc."
  spec.homepage = "https://github.com/ya-luotao/daytona-sdk"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ya-luotao/daytona-sdk"
  spec.metadata["changelog_uri"] = "https://github.com/ya-luotao/daytona-sdk/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://www.daytona.io/docs/sdk"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"].reject { |f| File.directory?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "websocket-client-simple", "~> 0.8"

  # Development dependencies are in Gemfile
end
