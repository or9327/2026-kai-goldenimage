#!/bin/bash
# modules/01-account-management/U-04-password-file-protection.sh
# DESC: 비밀번호 파일 보호

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-04"
MODULE_NAME="비밀번호 파일 보호"
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
    
    local needs_update=false
    
    # Step 1: /etc/passwd 파일에서 두 번째 필드가 'x'인지 확인
    log_info "Step 1: /etc/passwd 쉐도우 패스워드 사용 확인"
    
    if [ ! -f /etc/passwd ]; then
        log_error "/etc/passwd 파일을 찾을 수 없음"
        return 1
    fi
    
    # 비밀번호 필드에 'x'가 아닌 다른 값이 있는 계정 확인
    local non_shadow_accounts=$(awk -F: '$2 != "x" && $2 != "*" && $2 != "!" && $2 != "" {print $1}' /etc/passwd)
    
    if [ -n "$non_shadow_accounts" ]; then
        log_warning "쉐도우 패스워드를 사용하지 않는 계정 발견:"
        echo "$non_shadow_accounts" | while read account; do
            log_warning "  - $account"
        done
        needs_update=true
    else
        log_success "✓ 모든 계정이 쉐도우 패스워드 사용 중"
    fi
    
    # /etc/shadow 파일 존재 및 권한 확인
    if [ -f /etc/shadow ]; then
        local shadow_perm=$(stat -c "%a" /etc/shadow)
        log_info "/etc/shadow 권한: $shadow_perm"
        
        if [ "$shadow_perm" != "640" ] && [ "$shadow_perm" != "600" ]; then
            log_warning "/etc/shadow 권한이 640 또는 600이 아님: $shadow_perm"
            needs_update=true
        fi
    else
        log_warning "/etc/shadow 파일이 없음"
        needs_update=true
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "이미 보안 요구사항을 충족합니다"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    backup_file "/etc/passwd" "$MODULE_ID"
    
    if [ -f /etc/shadow ]; then
        backup_file "/etc/shadow" "$MODULE_ID"
    fi
    
    if [ -f /etc/group ]; then
        backup_file "/etc/group" "$MODULE_ID"
    fi
    
    if [ -f /etc/gshadow ]; then
        backup_file "/etc/gshadow" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 쉐도우 패스워드 적용 시뮬레이션"
        return 0
    fi
    
    # Step 2: pwconv 명령으로 쉐도우 패스워드 적용
    log_info "Step 2: pwconv 명령 실행 중..."
    
    # pwconv: /etc/passwd의 비밀번호를 /etc/shadow로 이동
    if command -v pwconv &>/dev/null; then
        pwconv
        log_success "✓ pwconv 실행 완료"
    else
        log_error "pwconv 명령을 찾을 수 없습니다"
        return 1
    fi
    
    # grpconv: /etc/group의 비밀번호를 /etc/gshadow로 이동
    if command -v grpconv &>/dev/null; then
        grpconv
        log_success "✓ grpconv 실행 완료"
    fi
    
    # Step 3: /etc/shadow 파일 권한 설정
    log_info "Step 3: /etc/shadow 파일 권한 설정 중..."
    
    if [ -f /etc/shadow ]; then
        chmod 640 /etc/shadow
        chown root:shadow /etc/shadow 2>/dev/null || chown root:root /etc/shadow
        log_success "✓ /etc/shadow 권한 설정 완료 (640)"
    else
        log_error "/etc/shadow 파일이 생성되지 않았습니다"
        return 1
    fi
    
    # /etc/gshadow 권한 설정
    if [ -f /etc/gshadow ]; then
        chmod 640 /etc/gshadow
        chown root:shadow /etc/gshadow 2>/dev/null || chown root:root /etc/gshadow
        log_success "✓ /etc/gshadow 권한 설정 완료 (640)"
    fi
    
    # /etc/passwd, /etc/group 권한 확인
    if [ -f /etc/passwd ]; then
        chmod 644 /etc/passwd
        chown root:root /etc/passwd
    fi
    
    if [ -f /etc/group ]; then
        chmod 644 /etc/group
        chown root:root /etc/group
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/passwd 검증 - 모든 계정이 'x' 사용하는지 확인
    log_info "검증 1: /etc/passwd 쉐도우 패스워드 사용"
    
    local non_shadow_accounts=$(awk -F: '$2 != "x" && $2 != "*" && $2 != "!" && $2 != "" {print $1}' /etc/passwd)
    
    if [ -z "$non_shadow_accounts" ]; then
        log_success "✓ 모든 계정이 쉐도우 패스워드 사용 (두 번째 필드: x)"
    else
        log_error "✗ 쉐도우 패스워드를 사용하지 않는 계정:"
        echo "$non_shadow_accounts" | while read account; do
            log_error "  - $account"
        done
        validation_failed=true
    fi
    
    # /etc/shadow 존재 및 권한 검증
    log_info "검증 2: /etc/shadow 파일 권한"
    
    if [ -f /etc/shadow ]; then
        local shadow_perm=$(stat -c "%a" /etc/shadow)
        local shadow_owner=$(stat -c "%U:%G" /etc/shadow)
        
        if [ "$shadow_perm" = "640" ] || [ "$shadow_perm" = "600" ]; then
            log_success "✓ /etc/shadow 권한: $shadow_perm (소유자: $shadow_owner)"
        else
            log_error "✗ /etc/shadow 권한: $shadow_perm (예상: 640 또는 600)"
            validation_failed=true
        fi
    else
        log_error "✗ /etc/shadow 파일이 없습니다"
        validation_failed=true
    fi
    
    # /etc/passwd 샘플 출력
    log_info "검증 3: /etc/passwd 샘플 (처음 3줄)"
    head -3 /etc/passwd | while read line; do
        log_info "  $line"
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
    log_info "=== 쉐도우 패스워드 적용 완료 ==="
    log_info "비밀번호 정보가 /etc/shadow로 이동되었습니다."
    log_info ""
    log_info "관련 파일 권한:"
    log_info "  /etc/passwd : 644 (root:root)"
    log_info "  /etc/shadow : 640 (root:shadow)"
    log_info "  /etc/group  : 644 (root:root)"
    log_info "  /etc/gshadow: 640 (root:shadow)"
    log_info ""
}

# 스크립트 실행
main "$@"
