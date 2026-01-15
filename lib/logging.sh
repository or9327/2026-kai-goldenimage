#!/bin/bash
# lib/logging.sh
# 로깅 함수

log_to_file() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # LOG_FILE이 설정되어 있고 디렉토리가 존재하는 경우에만 파일에 기록
    if [ -n "$LOG_FILE" ]; then
        local log_dir=$(dirname "$LOG_FILE")
        if [ ! -d "$log_dir" ]; then
            mkdir -p "$log_dir" 2>/dev/null || true
        fi
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_to_file "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_to_file "SUCCESS" "$1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_to_file "WARNING" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log_to_file "ERROR" "$1"
}

log_section() {
    local title=$1
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $title"
    echo "═══════════════════════════════════════════════════════════════"
    log_to_file "SECTION" "$title"
}

# 간단한 요약 로그 (화면 전용)
log_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_to_file "SUMMARY" "$1"
}

# 진행 상황 표시 (화면 전용)
log_progress() {
    local current=$1
    local total=$2
    local message=$3
    echo -ne "\r${BLUE}[진행]${NC} [$current/$total] $message"
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
    log_to_file "PROGRESS" "[$current/$total] $message"
}

# 새 실행 시작 구분자 (파일 전용)
log_execution_start() {
    if [ -n "$LOG_FILE" ]; then
        echo "" >> "$LOG_FILE"
        echo "=================================================================================" >> "$LOG_FILE"
        echo "새 실행 시작: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
        echo "=================================================================================" >> "$LOG_FILE"
    fi
}