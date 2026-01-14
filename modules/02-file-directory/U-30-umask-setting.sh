#!/bin/bash
# modules/02-file-directory-management/U-30-umask-setting.sh
# DESC: UMASK 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-30"
MODULE_NAME="UMASK 설정"
MODULE_CATEGORY="파일 및 디렉토리 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 권장 UMASK 값
RECOMMENDED_UMASK="022"

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # /etc/profile 확인
    if [ -f /etc/profile ]; then
        if grep -q "^umask ${RECOMMENDED_UMASK}" /etc/profile; then
            log_success "✓ /etc/profile: umask ${RECOMMENDED_UMASK}"
        else
            log_warning "/etc/profile: umask 설정 확인 필요"
            needs_update=true
        fi
    fi
    
    # /etc/login.defs 확인
    if [ -f /etc/login.defs ]; then
        if grep -q "^UMASK.*${RECOMMENDED_UMASK}" /etc/login.defs; then
            log_success "✓ /etc/login.defs: UMASK ${RECOMMENDED_UMASK}"
        else
            log_warning "/etc/login.defs: UMASK 설정 확인 필요"
            needs_update=true
        fi
    fi
    
    # /etc/bash.bashrc 확인 (Ubuntu)
    if [ -f /etc/bash.bashrc ]; then
        if grep -q "^umask ${RECOMMENDED_UMASK}" /etc/bash.bashrc; then
            log_success "✓ /etc/bash.bashrc: umask ${RECOMMENDED_UMASK}"
        else
            log_warning "/etc/bash.bashrc: umask 설정 확인 필요"
            needs_update=true
        fi
    fi
    
    # FTP 서비스 확인 (있으면)
    if [ -f /etc/vsftpd.conf ] || [ -f /etc/vsftpd/vsftpd.conf ]; then
        log_info "vsFTPd 설정 확인 필요"
        needs_update=true
    fi
    
    if [ -f /etc/proftpd.conf ] || [ -f /etc/proftpd/proftpd.conf ]; then
        log_info "ProFTPd 설정 확인 필요"
        needs_update=true
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ UMASK가 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    local files_to_backup=(
        "/etc/profile"
        "/etc/login.defs"
        "/etc/bash.bashrc"
        "/etc/vsftpd.conf"
        "/etc/vsftpd/vsftpd.conf"
        "/etc/proftpd.conf"
        "/etc/proftpd/proftpd.conf"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [ -f "$file" ]; then
            backup_file "$file" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] UMASK 설정 시뮬레이션"
        log_info "[DRY RUN] umask ${RECOMMENDED_UMASK}"
        return 0
    fi
    
    # Step 1: /etc/profile 설정
    log_info "Step 1: /etc/profile 설정 중..."
    
    if [ -f /etc/profile ]; then
        # 기존 umask 설정 제거
        sed -i '/^umask /d' /etc/profile
        
        # 새 설정 추가
        cat >> /etc/profile << EOF

# KISA Security Guide: U-30 - UMASK Setting
umask ${RECOMMENDED_UMASK}
export umask
EOF
        
        log_success "✓ /etc/profile 설정 완료"
    fi
    
    # Step 2: /etc/login.defs 설정
    log_info "Step 2: /etc/login.defs 설정 중..."
    
    if [ -f /etc/login.defs ]; then
        # 기존 UMASK 설정 제거
        sed -i '/^UMASK/d' /etc/login.defs
        
        # 새 설정 추가
        echo "" >> /etc/login.defs
        echo "# KISA Security Guide: U-30 - UMASK Setting" >> /etc/login.defs
        echo "UMASK ${RECOMMENDED_UMASK}" >> /etc/login.defs
        
        log_success "✓ /etc/login.defs 설정 완료"
    fi
    
    # Step 3: /etc/bash.bashrc 설정 (Ubuntu)
    if [ -f /etc/bash.bashrc ]; then
        log_info "Step 3: /etc/bash.bashrc 설정 중..."
        
        if ! grep -q "^umask ${RECOMMENDED_UMASK}" /etc/bash.bashrc; then
            sed -i '/^umask /d' /etc/bash.bashrc
            echo "" >> /etc/bash.bashrc
            echo "# KISA Security Guide: U-30 - UMASK Setting" >> /etc/bash.bashrc
            echo "umask ${RECOMMENDED_UMASK}" >> /etc/bash.bashrc
            
            log_success "✓ /etc/bash.bashrc 설정 완료"
        fi
    fi
    
    # Step 4: vsFTPd 설정
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            log_info "Step 4: vsFTPd UMASK 설정 중..."
            
            # 기존 local_umask 제거
            sed -i '/^local_umask=/d' "$vsftpd_conf"
            
            # 새 설정 추가
            echo "local_umask=${RECOMMENDED_UMASK}" >> "$vsftpd_conf"
            
            log_success "✓ $vsftpd_conf 설정 완료"
            
            # 서비스 재시작
            if systemctl is-active --quiet vsftpd; then
                systemctl restart vsftpd 2>/dev/null
                log_success "✓ vsftpd 서비스 재시작"
            fi
        fi
    done
    
    # Step 5: ProFTPd 설정
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ]; then
            log_info "Step 5: ProFTPd UMASK 설정 중..."
            
            # 기존 Umask 제거
            sed -i '/^Umask /d' "$proftpd_conf"
            
            # 새 설정 추가
            echo "Umask ${RECOMMENDED_UMASK}" >> "$proftpd_conf"
            
            log_success "✓ $proftpd_conf 설정 완료"
            
            # 서비스 재시작
            if systemctl is-active --quiet proftpd; then
                systemctl restart proftpd 2>/dev/null
                log_success "✓ proftpd 서비스 재시작"
            fi
        fi
    done
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/profile 검증
    if [ -f /etc/profile ]; then
        if grep -q "^umask ${RECOMMENDED_UMASK}" /etc/profile; then
            log_success "✓ /etc/profile: umask ${RECOMMENDED_UMASK}"
        else
            log_error "✗ /etc/profile: umask 설정 오류"
            validation_failed=true
        fi
    fi
    
    # /etc/login.defs 검증
    if [ -f /etc/login.defs ]; then
        if grep -q "^UMASK.*${RECOMMENDED_UMASK}" /etc/login.defs; then
            log_success "✓ /etc/login.defs: UMASK ${RECOMMENDED_UMASK}"
        else
            log_error "✗ /etc/login.defs: UMASK 설정 오류"
            validation_failed=true
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
    log_info "=== UMASK 설정 완료 ==="
    log_info "기본 파일 생성 권한: 644 (umask 022)"
    log_info "기본 디렉토리 생성 권한: 755 (umask 022)"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 현재 umask 확인"
    log_info "  umask"
    log_info ""
    log_info "  # 설정 파일 확인"
    log_info "  grep umask /etc/profile"
    log_info "  grep UMASK /etc/login.defs"
    log_info ""
    log_info "참고:"
    log_info "  - 새 세션부터 적용됨"
    log_info "  - 022: owner(rw), group(r), other(r)"
    log_info ""
}

# 스크립트 실행
main "$@"
