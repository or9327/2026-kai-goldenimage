#!/bin/bash
# modules/01-account-management/U-12-session-timeout.sh
# DESC: Session Timeout 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-12"
MODULE_NAME="Session Timeout 설정"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 설정 값 (초 단위, 600초 = 10분)
TMOUT_VALUE=600

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # /etc/profile에서 TMOUT 설정 확인
    if [ -f /etc/profile ]; then
        if grep -q "^TMOUT=" /etc/profile && grep -q "^export TMOUT" /etc/profile; then
            local current_tmout=$(grep "^TMOUT=" /etc/profile | cut -d= -f2)
            log_info "/etc/profile의 TMOUT: $current_tmout"
            
            if [ "$current_tmout" != "$TMOUT_VALUE" ]; then
                needs_update=true
            fi
        else
            log_warning "/etc/profile에 TMOUT 설정이 없음"
            needs_update=true
        fi
    else
        log_warning "/etc/profile 파일이 없음"
        needs_update=true
    fi
    
    # /etc/bash.bashrc 확인 (Ubuntu/Debian)
    if [ -f /etc/bash.bashrc ]; then
        if ! grep -q "^TMOUT=" /etc/bash.bashrc; then
            log_warning "/etc/bash.bashrc에 TMOUT 설정이 없음"
            needs_update=true
        fi
    fi
    
    # csh 설정 확인
    if [ -f /etc/csh.cshrc ]; then
        if ! grep -q "^set autologout" /etc/csh.cshrc; then
            log_warning "/etc/csh.cshrc에 autologout 설정이 없음"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ Session Timeout이 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/profile ]; then
        backup_file "/etc/profile" "$MODULE_ID"
    fi
    
    if [ -f /etc/bash.bashrc ]; then
        backup_file "/etc/bash.bashrc" "$MODULE_ID"
    fi
    
    if [ -f /etc/csh.cshrc ]; then
        backup_file "/etc/csh.cshrc" "$MODULE_ID"
    fi
    
    if [ -f /etc/csh.login ]; then
        backup_file "/etc/csh.login" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] Session Timeout 설정 시뮬레이션"
        log_info "[DRY RUN] TMOUT=${TMOUT_VALUE} (10분)"
        return 0
    fi
    
    # Step 1: /etc/profile 설정 (sh, ksh, bash)
    log_info "Step 1: /etc/profile 설정 중..."
    
    if [ -f /etc/profile ]; then
        # 기존 TMOUT 설정 제거
        sed -i '/^TMOUT=/d' /etc/profile
        sed -i '/^export TMOUT/d' /etc/profile
        
        # 새 설정 추가
        cat >> /etc/profile << EOF

# KISA Security Guide: U-12 - Session Timeout
TMOUT=${TMOUT_VALUE}
export TMOUT
EOF
        
        log_success "✓ /etc/profile 설정 완료"
    else
        log_warning "/etc/profile 파일이 없습니다"
    fi
    
    # Step 2: /etc/bash.bashrc 설정 (Ubuntu/Debian의 bash 전역 설정)
    if [ -f /etc/bash.bashrc ]; then
        log_info "Step 2: /etc/bash.bashrc 설정 중..."
        
        # 기존 TMOUT 설정 제거
        sed -i '/^TMOUT=/d' /etc/bash.bashrc
        sed -i '/^export TMOUT/d' /etc/bash.bashrc
        
        # 새 설정 추가
        cat >> /etc/bash.bashrc << EOF

# KISA Security Guide: U-12 - Session Timeout
TMOUT=${TMOUT_VALUE}
export TMOUT
EOF
        
        log_success "✓ /etc/bash.bashrc 설정 완료"
    fi
    
    # Step 3: csh 설정
    if [ -f /etc/csh.cshrc ] || [ -f /etc/csh.login ]; then
        log_info "Step 3: csh 설정 중..."
        
        # autologout 값 (분 단위, 600초 = 10분)
        local autologout_minutes=$((TMOUT_VALUE / 60))
        
        if [ -f /etc/csh.cshrc ]; then
            sed -i '/^set autologout/d' /etc/csh.cshrc
            echo "set autologout=${autologout_minutes}" >> /etc/csh.cshrc
            log_success "✓ /etc/csh.cshrc 설정 완료"
        fi
        
        if [ -f /etc/csh.login ]; then
            sed -i '/^set autologout/d' /etc/csh.login
            echo "set autologout=${autologout_minutes}" >> /etc/csh.login
            log_success "✓ /etc/csh.login 설정 완료"
        fi
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/profile 검증
    if [ -f /etc/profile ]; then
        if grep -q "^TMOUT=${TMOUT_VALUE}" /etc/profile && grep -q "^export TMOUT" /etc/profile; then
            log_success "✓ /etc/profile: TMOUT=${TMOUT_VALUE}"
        else
            log_error "✗ /etc/profile: TMOUT 설정 오류"
            validation_failed=true
        fi
    fi
    
    # /etc/bash.bashrc 검증
    if [ -f /etc/bash.bashrc ]; then
        if grep -q "^TMOUT=${TMOUT_VALUE}" /etc/bash.bashrc; then
            log_success "✓ /etc/bash.bashrc: TMOUT=${TMOUT_VALUE}"
        else
            log_warning "⚠ /etc/bash.bashrc: TMOUT 미설정"
        fi
    fi
    
    # csh 검증
    local autologout_minutes=$((TMOUT_VALUE / 60))
    
    if [ -f /etc/csh.cshrc ]; then
        if grep -q "^set autologout=${autologout_minutes}" /etc/csh.cshrc; then
            log_success "✓ /etc/csh.cshrc: autologout=${autologout_minutes}"
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
    log_info "=== Session Timeout 설정 완료 ==="
    log_info "비활성 세션 자동 종료 시간: ${TMOUT_VALUE}초 (10분)"
    log_info ""
    log_info "설정 확인:"
    log_info "  # 현재 TMOUT 값 확인 (새 shell에서)"
    log_info "  echo \$TMOUT"
    log_info ""
    log_info "  # 설정 테스트"
    log_info "  bash -c 'echo \$TMOUT'"
    log_info ""
    log_info "참고:"
    log_info "  - 기존 로그인 세션에는 적용되지 않음"
    log_info "  - 새로 로그인하는 세션부터 적용됨"
    log_info "  - SSH 세션도 10분 비활성 시 자동 종료됨"
    log_info ""
}

# 스크립트 실행
main "$@"
