#!/usr/bin/env bash
#==============================================================================
# Logging Helper Functions
#==============================================================================
# Purpose: Provide centralized logging functionality for all deployment scripts
#
# Usage:
#   source scripts/helpers/logging.sh
#   setup_logging "script-name" "$ENVIRONMENT"
#   log_info "message"
#   log_success "message"
#   log_warning "message"
#   log_error "message"
#==============================================================================

#------------------------------------------------------------------------------
# Color codes for output (declare only if not already set)
#------------------------------------------------------------------------------
if [[ -z "${COLOR_RED:-}" ]]; then
    readonly COLOR_RED='\033[0;31m'
fi
if [[ -z "${COLOR_GREEN:-}" ]]; then
    readonly COLOR_GREEN='\033[0;32m'
fi
if [[ -z "${COLOR_YELLOW:-}" ]]; then
    readonly COLOR_YELLOW='\033[1;33m'
fi
if [[ -z "${COLOR_BLUE:-}" ]]; then
    readonly COLOR_BLUE='\033[0;34m'
fi
if [[ -z "${COLOR_RESET:-}" ]]; then
    readonly COLOR_RESET='\033[0m'
fi

#------------------------------------------------------------------------------
# Global variables
#------------------------------------------------------------------------------
LOG_FILE=""
LOG_DIR=""

#------------------------------------------------------------------------------
# Setup logging
#------------------------------------------------------------------------------
setup_logging() {
    local script_name="${1:-deployment}"
    local environment="${2:-dev}"
    
    # Get script directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOG_DIR="${script_dir}/../../logs"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Create log file with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    LOG_FILE="${LOG_DIR}/${script_name}-${environment}-${timestamp}.log"
    
    # Initialize log file
    {
        echo "=========================================="
        echo "Log File: $LOG_FILE"
        echo "Script: $script_name"
        echo "Environment: $environment"
        echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "User: $(whoami)"
        echo "Host: $(hostname)"
        echo "=========================================="
        echo ""
    } > "$LOG_FILE"
    
    # Export for use in other functions
    export LOG_FILE
    export LOG_DIR
    
    echo -e "${COLOR_BLUE}📝 Logging to: $LOG_FILE${COLOR_RESET}"
    echo ""
}

#------------------------------------------------------------------------------
# Log message to both console and file
#------------------------------------------------------------------------------
log_message() {
    local level="$1"
    local message="$2"
    local color="${3:-$COLOR_RESET}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file (without color codes)
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    # Log to console (with color)
    echo -e "${color}$message${COLOR_RESET}"
}

#------------------------------------------------------------------------------
# Log info message
#------------------------------------------------------------------------------
log_info() {
    log_message "INFO" "$1" "$COLOR_BLUE"
}

#------------------------------------------------------------------------------
# Log success message
#------------------------------------------------------------------------------
log_success() {
    log_message "SUCCESS" "$1" "$COLOR_GREEN"
}

#------------------------------------------------------------------------------
# Log warning message
#------------------------------------------------------------------------------
log_warning() {
    log_message "WARNING" "$1" "$COLOR_YELLOW"
}

#------------------------------------------------------------------------------
# Log error message
#------------------------------------------------------------------------------
log_error() {
    log_message "ERROR" "$1" "$COLOR_RED"
}

#------------------------------------------------------------------------------
# Log command execution
#------------------------------------------------------------------------------
log_command() {
    local command="$1"
    log_message "COMMAND" "Executing: $command" "$COLOR_BLUE"
    
    # Execute command and capture output
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        log_message "COMMAND" "✅ Command succeeded" "$COLOR_GREEN"
        return 0
    else
        local exit_code=$?
        log_message "COMMAND" "❌ Command failed with exit code: $exit_code" "$COLOR_RED"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Log authentication details
#------------------------------------------------------------------------------
log_auth_details() {
    if [[ -z "$LOG_FILE" ]]; then
        return 0
    fi
    
    local account_type=$(az account show --query user.type -o tsv 2>/dev/null || echo "unknown")
    local account_name=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
    local subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "unknown")
    local tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || echo "unknown")
    
    {
        echo "=========================================="
        echo "Azure Authentication Details"
        echo "=========================================="
        echo "Account Type: $account_type"
        
        if [[ "$account_type" == "servicePrincipal" ]]; then
            echo "App ID (Client ID): $account_name"
            local sp_name=$(az ad sp show --id "$account_name" --query displayName -o tsv 2>/dev/null || echo "N/A")
            echo "Service Principal Display Name: $sp_name"
            
            # Get additional SP details
            local sp_object_id=$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || echo "N/A")
            echo "Service Principal Object ID: $sp_object_id"
        elif [[ "$account_type" == "user" ]]; then
            echo "User Principal Name: $account_name"
            # Only try to get user object ID for actual user authentication (not service principal)
            # This command will fail with service principals, so we skip it
            if command -v az &>/dev/null && az account show --query user.type -o tsv 2>/dev/null | grep -q "^user$"; then
                local user_object_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "N/A")
                echo "User Object ID: $user_object_id"
            fi
        else
            echo "Account Name: $account_name"
        fi
        
        echo "Subscription Name: $subscription_name"
        echo "Subscription ID: $subscription_id"
        echo "Tenant ID: $tenant_id"
        echo "=========================================="
        echo ""
    } >> "$LOG_FILE"
}

#------------------------------------------------------------------------------
# Finalize logging
#------------------------------------------------------------------------------
finalize_logging() {
    local exit_code="${1:-0}"
    
    if [[ -n "$LOG_FILE" ]]; then
        {
            echo ""
            echo "=========================================="
            echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Exit Code: $exit_code"
            echo "=========================================="
        } >> "$LOG_FILE"
        
        if [[ $exit_code -eq 0 ]]; then
            log_success "✅ Script completed successfully"
        else
            log_error "❌ Script failed with exit code: $exit_code"
        fi
        
        log_info "📝 Full log available at: $LOG_FILE"
        echo ""
    fi
}

#------------------------------------------------------------------------------
# Export functions
#------------------------------------------------------------------------------
export -f setup_logging
export -f log_message
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_command
export -f log_auth_details
export -f finalize_logging
