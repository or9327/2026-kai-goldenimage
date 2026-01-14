#!/bin/bash
# modules/01-account-management/U-05-uid-zero-restriction.sh
# DESC: root 이외의 UID가 '0' 금지

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-05"
MODULE_NAME="root 이외의 UID가 '0' 금지"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    # /etc/passwd에서 UID가 0인 계정 찾기 (root 제외)
    log_info "Step 1: UID 0인 계정 검색 중..."
    
    if [ ! -f /etc/passwd ]; then
        log_error "/etc/passwd 파일을 찾을 수 없음"
        return 1
    fi
    
    # UID가 0인 계정 목록 (root 제외)
    # 형식: username:x:0:...
    local uid_zero_accounts=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
    
    if [ -n "$uid_zero_accounts" ]; then
        log_warning "UID 0을 가진 root 이외의 계정 발견:"
        echo "$uid_zero_accounts" | while read account; do
            local account_info=$(grep "^${account}:" /etc/passwd)
            log_warning "  - ${account}: ${account_info}"
        done
        
        # 전역 변수로 저장 (apply_hardening에서 사용)
        FOUND_UID_ZERO_ACCOUNTS="$uid_zero_accounts"
        
        log_warning "설정 변경 필요"
        return 1
    else
        log_success "✓ root만 UID 0을 사용하고 있음"
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
        log_info "[DRY RUN] UID 변경 시뮬레이션"
        if [ -n "$FOUND_UID_ZERO_ACCOUNTS" ]; then
            echo "$FOUND_UID_ZERO_ACCOUNTS" | while read account; do
                log_info "[DRY RUN] $account 계정의 UID를 변경할 예정"
            done
        fi
        return 0
    fi
    
    if [ -z "$FOUND_UID_ZERO_ACCOUNTS" ]; then
        log_info "변경할 계정이 없습니다"
        return 0
    fi
    
    # Step 1: UID 0인 계정의 UID 변경
    log_info "Step 1: UID 0 계정의 UID 변경 중..."
    
    # 사용 가능한 UID 찾기 (1000번대부터 시작)
    local next_uid=1000
    
    echo "$FOUND_UID_ZERO_ACCOUNTS" | while read account; do
        # 중복되지 않는 UID 찾기
        while getent passwd "$next_uid" >/dev/null 2>&1; do
            next_uid=$((next_uid + 1))
        done
        
        log_info "계정 '$account'의 UID를 0에서 $next_uid로 변경 중..."
        
        # usermod로 UID 변경
        if usermod -u "$next_uid" "$account" 2>/dev/null; then
            log_success "✓ $account: UID 0 -> $next_uid"
            
            # 해당 UID로 소유된 파일 소유자 변경
            log_info "  파일 소유자 업데이트 중..."
            find / -user 0 -not -user root -exec chown "$next_uid" {} \; 2>/dev/null &
            
            next_uid=$((next_uid + 1))
        else
            log_error "✗ $account: UID 변경 실패"
            return 1
        fi
    done
    
    # 백그라운드 작업 완료 대기
    wait
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # UID 0인 계정 재확인
    log_info "검증: UID 0 계정 확인"
    
    local uid_zero_accounts=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
    
    if [ -z "$uid_zero_accounts" ]; then
        log_success "✓ root만 UID 0을 사용하고 있음"
    else
        log_error "✗ 여전히 UID 0을 가진 계정이 존재:"
        echo "$uid_zero_accounts" | while read account; do
            log_error "  - $account"
        done
        validation_failed=true
    fi
    
    # root 계정 확인
    local root_uid=$(id -u root 2>/dev/null)
    if [ "$root_uid" = "0" ]; then
        log_success "✓ root 계정 UID: 0"
    else
        log_error "✗ root 계정 UID: $root_uid (예상: 0)"
        validation_failed=true
    fi
    
    # /etc/passwd 샘플 출력 (UID 0 계정만)
    log_info "UID 0 계정 목록:"
    awk -F: '$3 == 0 {print "  " $1 ":" $3}' /etc/passwd
    
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
    
    # 대화형 확인 (중요한 작업이므로)
    if [ "${INTERACTIVE:-false}" = true ] || [ "${DRY_RUN_MODE:-false}" = false ]; then
        log_warning ""
        log_warning "경고: UID 0을 가진 계정의 UID를 변경합니다."
        log_warning "이 작업은 다음과 같은 영향을 미칠 수 있습니다:"
        log_warning "  - 해당 계정의 슈퍼유저 권한 제거"
        log_warning "  - 파일 소유권 변경 필요"
        log_warning "  - 실행 중인 프로세스 영향 가능"
        log_warning ""
        
        if [ "${DRY_RUN_MODE:-false}" = false ]; then
            if ! confirm_action; then
                log_info "사용자가 작업을 취소했습니다"
                exit 0
            fi
        fi
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
    log_info "=== UID 0 제한 완료 ==="
    log_info "root 계정만 UID 0(슈퍼유저 권한)을 가집니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # UID 0 계정 확인"
    log_info "  awk -F: '\$3 == 0 {print \$1\":\"\$3}' /etc/passwd"
    log_info ""
    log_info "  # 특정 사용자 UID 확인"
    log_info "  id username"
    log_info ""
}

# 스크립트 실행
main "$@"
