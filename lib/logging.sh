#!/bin/bash
# lib/logging.sh
# 로깅 함수

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log_message "ERROR" "$1"
}

log_section() {
    local title=$1
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $title"
    echo "═══════════════════════════════════════════════════════════════"
    log_message "SECTION" "$title"
}