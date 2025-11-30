#!/usr/bin/env bash
#==============================================================================
# Configuration Parser Helper Functions
#==============================================================================
# Purpose: Provide centralized configuration parsing functionality for deployment scripts
#
# Usage:
# source scripts/helpers/config-parser.sh
# value=$(parse_config "/path/to/config.json" ".path.to.value")
# get_infra_value "resourceType.property"
#==============================================================================

#------------------------------------------------------------------------------
# Parse configuration value from JSON file using jq
#------------------------------------------------------------------------------
parse_config() {
    local config_file="$1"
    local json_path="$2"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    local value
    value=$(jq -r "$json_path" "$config_file" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$value" = "null" ]; then
        echo "ERROR: Failed to parse '$json_path' from $config_file" >&2
        return 1
    fi
    
    echo "$value"
}

#------------------------------------------------------------------------------
# Get value from infrastructure configuration file
#------------------------------------------------------------------------------
get_infra_value() {
    local path="$1"
    local env="${ENV:-dev}"
    local infra_file="${SCRIPT_DIR}/../config/infra-${env}.json"
    
    if [ ! -f "$infra_file" ]; then
        echo "ERROR: Infrastructure file not found: $infra_file" >&2
        return 1
    fi
    
    parse_config "$infra_file" ".$path"
}

#------------------------------------------------------------------------------
# Get tenant-specific configuration value
#------------------------------------------------------------------------------
get_tenant_config() {
    local tenant="$1"
    local path="$2"
    local env="${ENV:-dev}"
    local tenant_config="${SCRIPT_DIR}/../config/${tenant}/parameters-${env}.json"
    
    if [ ! -f "$tenant_config" ]; then
        echo "ERROR: Tenant configuration file not found: $tenant_config" >&2
        return 1
    fi
    
    parse_config "$tenant_config" ".$path"
}

#------------------------------------------------------------------------------
# Update configuration file with new value
#------------------------------------------------------------------------------
update_config() {
    local config_file="$1"
    local json_path="$2"
    local new_value="$3"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Update the JSON file
    jq "$json_path = \"$new_value\"" "$config_file" > "$temp_file"
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$config_file"
        echo "Updated $config_file: $json_path = $new_value"
    else
        rm -f "$temp_file"
        echo "ERROR: Failed to update $config_file" >&2
        return 1
    fi
}

#------------------------------------------------------------------------------
# Validate required configuration values
#------------------------------------------------------------------------------
validate_config() {
    local config_file="$1"
    shift
    local required_paths=("$@")
    
    local missing_values=()
    
    for path in "${required_paths[@]}"; do
        local value=$(parse_config "$config_file" "$path")
        if [ $? -ne 0 ] || [ -z "$value" ] || [ "$value" = "null" ]; then
            missing_values+=("$path")
        fi
    done
    
    if [ ${#missing_values[@]} -gt 0 ]; then
        echo "ERROR: Missing required configuration values in $config_file:" >&2
        for missing in "${missing_values[@]}"; do
            echo "  - $missing" >&2
        done
        return 1
    fi
    
    return 0
}