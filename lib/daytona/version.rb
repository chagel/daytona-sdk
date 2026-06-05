# frozen_string_literal: true

# Copyright 2025 Daytona Platforms Inc.
# SPDX-License-Identifier: Apache-2.0

module Daytona
  # Also sent to the toolbox daemon as X-Daytona-SDK-Version, which the daemon
  # uses to gate wire behavior — notably it only multiplexes a session
  # command's follow stream with the stdout/stderr demux prefixes (see
  # Util.demux) for versions >= 0.167.0. Keep this at/above that floor.
  VERSION = "1.0.0"
end
