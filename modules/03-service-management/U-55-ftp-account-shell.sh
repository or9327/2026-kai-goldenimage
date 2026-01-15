#!/bin/bash
# modules/03-service-management/U-55-ftp-account-shell.sh
# DESC: ftp 계정 shell 제한

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-55"
MODULE_NAME="ftp 계정 shell 제한"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 유효하지 않은 shell 목록
INVALID_SHELLS=(
    "/bin/false"
    "/usr/sbin/nologin"
    "/sbin/nologin"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    # ftp 계정 확인
    if ! grep -q "^ftp:" /etc/passwd; then
        log_success "✓ ftp 계정 없음"
        return 0
    fi
    
    local ftp_shell=$(grep "^ftp:" /etc/passwd | cut -d: -f7)
    log_info "ftp 계정 shell: $ftp_shell"
    
    # shell이 유효하지 않은 shell인지 확인
    local is_invalid=false
    for invalid_shell in "${INVALID_SHELLS[@]}"; do
        if [ "$ftp_shell" = "$invalid_shell" ]; then
            is_invalid=true
            break
        fi
    done
    
    if [ "$is_invalid" = true ]; then
        log_success "✓ ftp 계정 shell이 올바르게 설정됨"
        return 0
    else
        log_warning "ftp 계정 shell 변경 필요: $ftp_shell"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    backup_file "/etc/passwd" "$MODULE_ID"
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] ftp 계정 shell 변경 시뮬레이션"
        return 0
    fi
    
    # ftp 계정이 없으면 스킵
    if ! grep -q "^ftp:" /etc/passwd; then
        log_info "ftp 계정 없음 - 스킵"
        return 0
    fi
    
    # 선호하는 shell 선택
    local target_shell=""
    for shell in "${INVALID_SHELLS[@]}"; do
        if [ -f "$shell" ]; then
            target_shell="$shell"
            break
        fi
    done
    
    if [ -z "$target_shell" ]; then
        log_error "유효하지 않은 shell을 찾을 수 없음"
        return 1
    fi
    
    log_info "ftp 계정 shell을 $target_shell로 변경"
    
    # usermod 명령어로 shell 변경
    if usermod -s "$target_shell" ftp 2>/dev/null; then
        log_success "✓ ftp 계정 shell 변경 완료"
    else
        log_error "✗ ftp 계정 shell 변경 실패"
        return 1
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    # ftp 계정이 없으면 성공
    if ! grep -q "^ftp:" /etc/passwd; then
        log_success "✓ ftp 계정 없음"
        return 0
    fi
    
    local ftp_shell=$(grep "^ftp:" /etc/passwd | cut -d: -f7)
    
    # shell이 유효하지 않은 shell인지 확인
    local is_invalid=false
    for invalid_shell in "${INVALID_SHELLS[@]}"; do
        if [ "$ftp_shell" = "$invalid_shell" ]; then
            is_invalid=true
            log_success "✓ ftp 계정 shell: $ftp_shell"
            break
        fi
    done
    
    if [ "$is_invalid" = false ]; then
        log_error "✗ ftp 계정 shell이 여전히 유효함: $ftp_shell"
        return 1
    fi
    
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "이미 보안 요구사항을 충족합니다"
        exit 0
    fi
    
    # 백업 수행
    if [ "${SKIP_BACKUP:-false}" != true ]; then
        perform_backup
    fi
    
    # 설정 적용
    if ! apply_hardening; then
        log_error "설정 적용 실패"
        exit 1
    fi
    
    # 드라이런 모드에서는 검증 스킵
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 검증 단계 생략"
        log_success "[$MODULE_ID] $MODULE_NAME - 완료 (드라이런)"
        exit 0
    fi
    
    # 설정 검증
    if ! validate_settings; then
        log_error "설정 검증 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== ftp 계정 shell 제한 완료 ==="
    log_info "ftp 계정의 로그인이 제한되었습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  grep '^ftp:' /etc/passwd"
    log_info ""
}

# 스크립트 실행
main "$@"
