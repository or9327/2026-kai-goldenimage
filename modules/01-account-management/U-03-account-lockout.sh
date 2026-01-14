#!/bin/bash
# modules/01-account-management/U-03-account-lockout.sh
# DESC: 계정 잠금 임계값 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-03"
MODULE_NAME="계정 잠금 임계값 설정"
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
    
    # pam_tally2.so 또는 pam_faillock.so 확인 (Debian/Ubuntu)
    if [ -f /etc/pam.d/common-auth ]; then
        if grep -q "pam_faillock.so" /etc/pam.d/common-auth; then
            log_info "pam_faillock.so 모듈 발견"
            
            # deny, unlock_time 설정 확인
            local deny=$(grep "pam_faillock.so" /etc/pam.d/common-auth | grep -o "deny=[0-9]*" | cut -d'=' -f2 | head -1)
            local unlock_time=$(grep "pam_faillock.so" /etc/pam.d/common-auth | grep -o "unlock_time=[0-9]*" | cut -d'=' -f2 | head -1)
            
            log_info "현재 deny: ${deny:-없음}"
            log_info "현재 unlock_time: ${unlock_time:-없음}"
            
            if [ "$deny" != "10" ] || [ "$unlock_time" != "120" ]; then
                needs_update=true
            fi
        elif grep -q "pam_tally2.so" /etc/pam.d/common-auth; then
            log_info "pam_tally2.so 모듈 발견 (구버전)"
            needs_update=true
        else
            log_warning "계정 잠금 모듈이 설정되지 않음"
            needs_update=true
        fi
    else
        log_warning "/etc/pam.d/common-auth 파일을 찾을 수 없음"
        needs_update=true
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "이미 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/pam.d/common-auth ]; then
        backup_file "/etc/pam.d/common-auth" "$MODULE_ID"
    fi
    
    if [ -f /etc/pam.d/common-account ]; then
        backup_file "/etc/pam.d/common-account" "$MODULE_ID"
    fi
    
    # RHEL/CentOS 호환
    if [ -f /etc/pam.d/system-auth ]; then
        backup_file "/etc/pam.d/system-auth" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 계정 잠금 설정 시뮬레이션"
        return 0
    fi
    
    # libpam-modules 패키지 확인 (pam_faillock 포함)
    log_info "Step 1: 필요 패키지 확인 중..."
    
    if ! dpkg -l | grep -q libpam-modules; then
        log_info "libpam-modules 설치 중..."
        apt-get update -qq
        apt-get install -y libpam-modules
    else
        log_success "✓ libpam-modules 이미 설치됨"
    fi
    
    # Step 2: /etc/pam.d/common-auth 설정
    log_info "Step 2: /etc/pam.d/common-auth 설정 중..."
    
    if [ ! -f /etc/pam.d/common-auth ]; then
        log_error "/etc/pam.d/common-auth 파일이 없습니다"
        return 1
    fi
    
    # 기존 pam_tally2.so, pam_faillock.so 제거
    sed -i '/pam_tally2.so/d' /etc/pam.d/common-auth
    sed -i '/pam_faillock.so/d' /etc/pam.d/common-auth
    
    # 임시 파일에 새로운 PAM 설정 작성
    cat > /tmp/common-auth.new << 'PAMEOF'
#
# /etc/pam.d/common-auth - authentication settings common to all services
#
# This file is included from other service-specific PAM config files,
# and should contain a list of the authentication modules that define
# the central authentication scheme for use on the system
# (e.g., /etc/shadow, LDAP, Kerberos, etc.).  The default is to use the
# traditional Unix authentication mechanisms.

# here are the per-package modules (the "Primary" block)
auth	required			pam_faillock.so preauth audit deny=10 unlock_time=120
auth	[success=2 default=ignore]	pam_unix.so nullok
auth	[success=1 default=ignore]	pam_sss.so use_first_pass
# here's the fallback if no module succeeds
auth	[default=die]			pam_faillock.so authfail audit deny=10 unlock_time=120
auth	sufficient			pam_faillock.so authsucc audit deny=10 unlock_time=120
auth	requisite			pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
auth	required			pam_permit.so
PAMEOF
    
    # pam_sss.so가 실제로 있는지 확인하고 없으면 해당 줄 제거
    if [ ! -f /lib/*/security/pam_sss.so ] && [ ! -f /usr/lib/*/pam_sss.so ]; then
        log_info "pam_sss.so 없음 - 해당 라인 제거"
        sed -i '/pam_sss.so/d' /tmp/common-auth.new
        # success=2를 success=1로 변경 (pam_sss.so가 없으므로)
        sed -i 's/success=2/success=1/' /tmp/common-auth.new
    fi
    
    # 기존 파일 백업 및 교체
    cp /tmp/common-auth.new /etc/pam.d/common-auth
    rm -f /tmp/common-auth.new
    
    log_success "✓ /etc/pam.d/common-auth 설정 완료"
    
    # Step 3: /etc/pam.d/common-account 설정
    log_info "Step 3: /etc/pam.d/common-account 설정 중..."
    
    if [ ! -f /etc/pam.d/common-account ]; then
        log_warning "/etc/pam.d/common-account 파일이 없습니다"
    else
        # 기존 pam_faillock.so 제거
        sed -i '/pam_faillock.so/d' /etc/pam.d/common-account
        
        # pam_faillock.so 추가 (맨 끝에)
        if ! grep -q "^account.*required.*pam_faillock.so" /etc/pam.d/common-account; then
            echo "account required                        pam_faillock.so" >> /etc/pam.d/common-account
        fi
        
        log_success "✓ /etc/pam.d/common-account 설정 완료"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/pam.d/common-auth 검증
    if [ -f /etc/pam.d/common-auth ]; then
        # pam_faillock.so preauth 확인
        if grep -q "^auth.*required.*pam_faillock.so.*preauth" /etc/pam.d/common-auth; then
            log_success "✓ pam_faillock.so preauth 설정됨"
            
            # deny 값 확인
            local deny=$(grep "pam_faillock.so.*preauth" /etc/pam.d/common-auth | grep -o "deny=[0-9]*" | cut -d'=' -f2)
            if [ "$deny" = "10" ]; then
                log_success "✓ deny=10 설정됨"
            else
                log_error "✗ deny=${deny} (예상: 10)"
                validation_failed=true
            fi
            
            # unlock_time 값 확인
            local unlock_time=$(grep "pam_faillock.so.*preauth" /etc/pam.d/common-auth | grep -o "unlock_time=[0-9]*" | cut -d'=' -f2)
            if [ "$unlock_time" = "120" ]; then
                log_success "✓ unlock_time=120 설정됨"
            else
                log_error "✗ unlock_time=${unlock_time} (예상: 120)"
                validation_failed=true
            fi
        else
            log_error "✗ pam_faillock.so preauth 미설정"
            validation_failed=true
        fi
        
        # pam_faillock.so authfail 확인
        if grep -q "^auth.*required.*pam_faillock.so.*authfail" /etc/pam.d/common-auth; then
            log_success "✓ pam_faillock.so authfail 설정됨"
        else
            log_error "✗ pam_faillock.so authfail 미설정"
            validation_failed=true
        fi
    else
        log_error "✗ /etc/pam.d/common-auth 파일 없음"
        validation_failed=true
    fi
    
    # /etc/pam.d/common-account 검증
    if [ -f /etc/pam.d/common-account ]; then
        if grep -q "^account.*required.*pam_faillock.so" /etc/pam.d/common-account; then
            log_success "✓ pam_faillock.so (account) 설정됨"
        else
            log_warning "⚠ pam_faillock.so (account) 미설정"
        fi
    fi
    
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
    log_info "=== 계정 잠금 설정 완료 ==="
    log_info "로그인 실패 10회 시 계정 잠금 (120초)"
    log_info ""
    log_info "유용한 명령어:"
    log_info "  # 잠긴 사용자 확인"
    log_info "  sudo faillock --user username"
    log_info ""
    log_info "  # 사용자 잠금 해제"
    log_info "  sudo faillock --user username --reset"
    log_info ""
    log_info "  # 모든 사용자 잠금 해제"
    log_info "  sudo faillock --reset"
    log_info ""
}

# 스크립트 실행
main "$@"
