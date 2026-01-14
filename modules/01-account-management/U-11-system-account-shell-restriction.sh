#!/bin/bash
# modules/01-account-management/U-11-system-account-shell-restriction.sh
# DESC: 불필요한 계정 shell 제한

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-11"
MODULE_NAME="불필요한 계정 shell 제한"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 로그인이 불필요한 시스템 계정 목록
SYSTEM_ACCOUNTS="daemon bin sys adm listen nobody nobody4 noaccess diag operator games gopher"

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    if [ ! -f /etc/passwd ]; then
        log_error "/etc/passwd 파일을 찾을 수 없음"
        return 1
    fi
    
    # Step 1: 로그인 가능한 시스템 계정 확인
    log_info "Step 1: 시스템 계정의 shell 확인 중..."
    
    local accounts_to_fix=""
    
    for account in $SYSTEM_ACCOUNTS; do
        if grep -q "^${account}:" /etc/passwd; then
            local shell=$(grep "^${account}:" /etc/passwd | cut -d: -f7)
            
            # /bin/false, /sbin/nologin, /usr/sbin/nologin이 아니면 변경 필요
            if [ "$shell" != "/bin/false" ] && \
               [ "$shell" != "/sbin/nologin" ] && \
               [ "$shell" != "/usr/sbin/nologin" ]; then
                log_warning "  $account: $shell (변경 필요)"
                accounts_to_fix="${accounts_to_fix} ${account}"
            fi
        fi
    done
    
    if [ -n "$accounts_to_fix" ]; then
        ACCOUNTS_TO_FIX="$accounts_to_fix"
        log_warning "설정 변경 필요"
        return 1
    else
        log_success "✓ 모든 시스템 계정이 적절한 shell을 사용 중"
        return 0
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    backup_file "/etc/passwd" "$MODULE_ID"
    
    if [ -f /etc/shadow ]; then
        backup_file "/etc/shadow" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] shell 변경 시뮬레이션"
        if [ -n "$ACCOUNTS_TO_FIX" ]; then
            for account in $ACCOUNTS_TO_FIX; do
                log_info "[DRY RUN] $account의 shell을 /usr/sbin/nologin으로 변경할 예정"
            done
        fi
        return 0
    fi
    
    if [ -z "$ACCOUNTS_TO_FIX" ]; then
        log_info "변경할 계정이 없습니다"
        return 0
    fi
    
    # Step 2: 시스템 계정에 nologin shell 설정
    log_info "Step 2: 시스템 계정 shell 변경 중..."
    
    # /usr/sbin/nologin 또는 /sbin/nologin 사용 (Ubuntu는 /usr/sbin/nologin)
    local nologin_shell="/usr/sbin/nologin"
    if [ ! -f "$nologin_shell" ]; then
        nologin_shell="/sbin/nologin"
    fi
    
    if [ ! -f "$nologin_shell" ]; then
        log_warning "nologin을 찾을 수 없음, /bin/false 사용"
        nologin_shell="/bin/false"
    fi
    
    log_info "사용할 shell: $nologin_shell"
    
    for account in $ACCOUNTS_TO_FIX; do
        if id "$account" &>/dev/null; then
            local old_shell=$(grep "^${account}:" /etc/passwd | cut -d: -f7)
            
            if usermod -s "$nologin_shell" "$account" 2>/dev/null; then
                log_success "✓ $account: $old_shell -> $nologin_shell"
            else
                log_error "✗ $account: shell 변경 실패"
                return 1
            fi
        fi
    done
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # 시스템 계정 shell 재확인
    log_info "검증: 시스템 계정 shell 확인"
    
    for account in $SYSTEM_ACCOUNTS; do
        if grep -q "^${account}:" /etc/passwd; then
            local shell=$(grep "^${account}:" /etc/passwd | cut -d: -f7)
            
            if [ "$shell" = "/bin/false" ] || \
               [ "$shell" = "/sbin/nologin" ] || \
               [ "$shell" = "/usr/sbin/nologin" ]; then
                log_success "✓ $account: $shell"
            else
                log_error "✗ $account: $shell (예상: nologin 또는 false)"
                validation_failed=true
            fi
        fi
    done
    
    if [ "$validation_failed" = true ]; then
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
    log_info "=== 시스템 계정 shell 제한 완료 ==="
    log_info "다음 시스템 계정들의 로그인이 제한되었습니다:"
    log_info "  daemon, bin, sys, adm, listen, nobody, operator, games, gopher 등"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 시스템 계정 shell 확인"
    log_info "  grep -E '^(daemon|bin|sys|adm|operator|games|gopher):' /etc/passwd | cut -d: -f1,7"
    log_info ""
}

# 스크립트 실행
main "$@"
