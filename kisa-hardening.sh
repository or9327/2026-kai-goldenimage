#!/bin/bash
# kisa-hardening.sh
# KISA 보안 가이드 자동화 스크립트 (67개 항목)

set -euo pipefail

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설정 파일 먼저 로드 (LOG_FILE 변수 설정을 위해)
if [ -f "${SCRIPT_DIR}/config/settings.conf" ]; then
    source "${SCRIPT_DIR}/config/settings.conf"
else
    # 기본값 설정
    BACKUP_BASE_DIR="/root/kisa-backup"
    LOG_BASE_DIR="/var/log/kisa-hardening"
    REPORT_BASE_DIR="/var/log/kisa-hardening/reports"
fi

# 전역 변수 초기화
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
LOG_FILE="${LOG_BASE_DIR}/kisa-hardening-${TIMESTAMP}.log"
REPORT_FILE="${REPORT_BASE_DIR}/kisa-report-${TIMESTAMP}.html"

# 카운터 초기화
MODULE_SUCCESS_COUNT=0
MODULE_FAIL_COUNT=0
MODULE_SKIP_COUNT=0

# 라이브러리 로드 (LOG_FILE이 설정된 후)
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

# 실행 모드
DRY_RUN=false
INTERACTIVE=false
SELECTED_CATEGORIES=()
SELECTED_MODULES=()

# 사용법 출력
usage() {
    cat << EOF
사용법: $0 [옵션]

KISA 보안 가이드 자동화 스크립트 (Ubuntu 24.04)

옵션:
    -h, --help              도움말 표시
    -d, --dry-run           실제 적용 없이 시뮬레이션
    -i, --interactive       대화형 모드
    -c, --category CAT      특정 카테고리만 실행 (예: 01,02,03)
    -m, --module MOD        특정 모듈만 실행 (예: U-01,U-02)
    -l, --list              사용 가능한 모듈 목록 표시
    -r, --report-only       보고서만 생성 (적용 없음)
    -v, --validate          설정 검증만 수행
    --skip-backup           백업 생성 건너뛰기 (권장하지 않음)

예시:
    $0                                  # 전체 실행
    $0 -d                               # 드라이 런
    $0 -i                               # 대화형 모드
    $0 -c 01-account-management         # 카테고리 01만 실행
    $0 -m U-01,U-05                     # 모듈 U-01, U-05만 실행
    $0 --validate                       # 설정 검증만

카테고리:
    01-account-management    - 계정 관리
    02-file-directory        - 파일 및 디렉토리 관리
    03-service-management    - 서비스 관리
    04-patch-management      - 패치 관리
    05-log-management        - 로그 관리

EOF
    exit 0
}

# 모듈 목록 표시
list_modules() {
    echo "=== 사용 가능한 KISA 보안 모듈 ==="
    echo ""
    
    for category_dir in "${SCRIPT_DIR}/modules"/*; do
        if [ -d "$category_dir" ]; then
            category_name=$(basename "$category_dir")
            category_title=$(get_category_title "$category_name")
            
            echo "[$category_name] $category_title"
            
            for module in "$category_dir"/*.sh 2>/dev/null; do
                if [ -f "$module" ]; then
                    module_name=$(basename "$module" .sh)
                    module_desc=$(get_module_description "$module")
                    
                    # 모듈 활성화 상태 확인
                    if is_module_enabled "$module_name"; then
                        status="[활성]"
                    else
                        status="[비활성]"
                    fi
                    
                    echo "  $status $module_name - $module_desc"
                fi
            done
            echo ""
        fi
    done
}

# 사전 점검
pre_check() {
    log_section "사전 점검 시작"
    
    # 1. 실행 권한 확인
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 root 권한이 필요합니다."
        log_error "sudo로 실행해주세요: sudo $0"
        exit 1
    fi
    
    # 2. OS 버전 확인
    if ! check_ubuntu_version; then
        log_warning "지원되지 않는 Ubuntu 버전입니다. 계속 진행하시겠습니까?"
        if ! confirm_action; then
            exit 1
        fi
    fi
    
    # 3. 필수 명령어 확인
    check_required_commands
    
    # 4. 디스크 공간 확인
    check_disk_space
    
    # 5. 백업 디렉토리 생성
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    log_success "사전 점검 완료"
}

# 모듈 실행
execute_module() {
    local module_path=$1
    local module_name=$(basename "$module_path" .sh)
    
    log_section "모듈 실행: $module_name"
    
    # 모듈 활성화 확인
    if ! is_module_enabled "$module_name"; then
        log_info "모듈 비활성화됨: $module_name (건너뛰기)"
        MODULE_SKIP_COUNT=$((MODULE_SKIP_COUNT + 1))
        return 0
    fi
    
    # 드라이런 모드
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] $module_name 실행 시뮬레이션"
        export DRY_RUN_MODE=true
    fi
    
    # 대화형 모드
    if [ "$INTERACTIVE" = true ]; then
        log_info "모듈을 실행하시겠습니까? [y/N]"
        if ! confirm_action; then
            log_info "건너뛰기: $module_name"
            MODULE_SKIP_COUNT=$((MODULE_SKIP_COUNT + 1))
            return 0
        fi
    fi
    
    # 모듈 실행
    local start_time=$(date +%s)
    
    if bash "$module_path"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "모듈 완료: $module_name (${duration}초)"
        
        # 실행 결과 기록
        record_module_result "$module_name" "SUCCESS" "$duration"
    else
        local exit_code=$?
        log_error "모듈 실패: $module_name (종료 코드: $exit_code)"
        
        # 실행 결과 기록
        record_module_result "$module_name" "FAILED" "0" "$exit_code"
        
        # 실패 시 처리
        if [ "${STOP_ON_ERROR:-false}" = true ]; then
            log_error "오류로 인해 실행을 중단합니다."
            exit 1
        fi
    fi
}

# 카테고리별 모듈 실행
execute_category() {
    local category=$1
    local category_dir="${SCRIPT_DIR}/modules/${category}"
    
    if [ ! -d "$category_dir" ]; then
        log_error "카테고리를 찾을 수 없습니다: $category"
        return 1
    fi
    
    log_section "카테고리 실행: $category"
    
    # 모듈 정렬 후 실행
    for module in $(ls "$category_dir"/*.sh 2>/dev/null | sort); do
        execute_module "$module"
    done
}

# 전체 모듈 실행
execute_all() {
    log_section "전체 KISA 보안 가이드 적용 시작"
    
    # 카테고리 순서대로 실행
    for category_dir in $(ls -d "${SCRIPT_DIR}/modules"/*/ 2>/dev/null | sort); do
        category=$(basename "$category_dir")
        execute_category "$category"
    done
}

# 사후 검증
post_check() {
    log_section "사후 검증 시작"
    
    if [ -f "${SCRIPT_DIR}/checks/post-check.sh" ]; then
        bash "${SCRIPT_DIR}/checks/post-check.sh"
    fi
    
    log_success "사후 검증 완료"
}

# 보고서 생성
generate_report() {
    log_section "보고서 생성 중"
    
    # HTML 보고서 생성
    generate_html_report "$REPORT_FILE"
    
    # JSON 보고서 생성 (선택)
    if [ "${GENERATE_JSON_REPORT:-false}" = true ]; then
        generate_json_report "${REPORT_FILE%.html}.json"
    fi
    
    log_success "보고서 생성 완료: $REPORT_FILE"
}

# 메인 함수
main() {
    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -c|--category)
                IFS=',' read -ra SELECTED_CATEGORIES <<< "$2"
                shift 2
                ;;
            -m|--module)
                IFS=',' read -ra SELECTED_MODULES <<< "$2"
                shift 2
                ;;
            -l|--list)
                list_modules
                exit 0
                ;;
            -r|--report-only)
                REPORT_ONLY=true
                shift
                ;;
            -v|--validate)
                VALIDATE_ONLY=true
                shift
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            *)
                echo "알 수 없는 옵션: $1"
                usage
                ;;
        esac
    done
    
    # 헤더 출력
    print_header
    
    # 사전 점검
    pre_check
    
    # 검증만 수행
    if [ "${VALIDATE_ONLY:-false}" = true ]; then
        log_info "검증 모드 - 설정만 확인합니다"
        post_check
        exit 0
    fi
    
    # 보고서만 생성
    if [ "${REPORT_ONLY:-false}" = true ]; then
        log_info "보고서 생성 모드"
        generate_report
        exit 0
    fi
    
    # 실행 시작
    local start_time=$(date +%s)
    
    # 선택된 모듈 실행
    if [ ${#SELECTED_MODULES[@]} -gt 0 ]; then
        for module in "${SELECTED_MODULES[@]}"; do
            # U-01 형식의 모듈 ID로 파일 찾기
            module_path=$(find "${SCRIPT_DIR}/modules" -name "${module}-*.sh" | head -n1)
            if [ -n "$module_path" ] && [ -f "$module_path" ]; then
                execute_module "$module_path"
            else
                log_error "모듈을 찾을 수 없습니다: $module"
            fi
        done
    # 선택된 카테고리 실행
    elif [ ${#SELECTED_CATEGORIES[@]} -gt 0 ]; then
        for category in "${SELECTED_CATEGORIES[@]}"; do
            execute_category "$category"
        done
    # 전체 실행
    else
        execute_all
    fi
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # 사후 검증
    post_check
    
    # 보고서 생성
    generate_report
    
    # 요약 출력
    print_summary "$total_duration"
    
    log_success "KISA 보안 가이드 적용 완료"
}

# 스크립트 실행
main "$@"