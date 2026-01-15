#!/bin/bash
# modules/03-service-management/U-53-54-ftp-service-check.sh
# DESC: FTP 서비스 점검 및 배너 설정 (U-53, U-54)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-53-54"
MODULE_NAME="FTP 서비스 점검 및 배너 설정"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# FTP 서비스 목록
FTP_SERVICES=(
    "vsftpd"
    "proftpd"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local ftp_found=false
    local active_ftp=""
    local needs_update=false
    
    # vsFTPd 확인
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "vsftpd"; then
        ftp_found=true
        
        if systemctl is-active --quiet vsftpd 2>/dev/null; then
            log_info "vsFTPd: 활성화됨"
            active_ftp="vsftpd"
            
            # 배너 확인 (U-53)
            for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
                if [ -f "$vsftpd_conf" ]; then
                    if grep -q "^ftpd_banner=" "$vsftpd_conf"; then
                        log_success "✓ vsFTPd: 배너 설정됨 (U-53)"
                    else
                        log_warning "vsFTPd: 배너 미설정 (U-53)"
                        needs_update=true
                    fi
                    break
                fi
            done
        else
            log_info "vsFTPd: 설치되었으나 비활성화됨"
        fi
    fi
    
    # ProFTPd 확인
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "proftpd"; then
        ftp_found=true
        
        if systemctl is-active --quiet proftpd 2>/dev/null; then
            log_info "ProFTPd: 활성화됨"
            active_ftp="proftpd"
            
            # 배너 확인 (U-53)
            for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
                if [ -f "$proftpd_conf" ]; then
                    if grep -q "ServerIdent" "$proftpd_conf"; then
                        log_success "✓ ProFTPd: ServerIdent 설정됨 (U-53)"
                    else
                        log_warning "ProFTPd: ServerIdent 미설정 (U-53)"
                        needs_update=true
                    fi
                    break
                fi
            done
        else
            log_info "ProFTPd: 설치되었으나 비활성화됨"
        fi
    fi
    
    # inetd/xinetd FTP 확인
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -q "^ftp"; then
            log_info "inetd: FTP 활성화됨"
            ftp_found=true
        fi
    fi
    
    if [ -f /etc/xinetd.d/ftp ]; then
        if grep -q "disable.*=.*no" /etc/xinetd.d/ftp; then
            log_info "xinetd: FTP 활성화됨"
            ftp_found=true
        fi
    fi
    
    FTP_FOUND="$ftp_found"
    ACTIVE_FTP="$active_ftp"
    
    if [ "$ftp_found" = false ]; then
        log_success "✓ FTP 서비스 미설치 (U-54)"
        return 0
    elif [ -z "$active_ftp" ]; then
        log_success "✓ FTP 서비스 비활성화됨 (U-54)"
        return 0
    elif [ "$needs_update" = false ]; then
        log_success "✓ FTP 배너 설정됨 (U-53)"
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
    log_info "FTP 서비스 분석 및 설정 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] FTP 서비스 설정 시뮬레이션"
        return 0
    fi
    
    if [ "$FTP_FOUND" = false ]; then
        log_info "FTP 서비스가 설치되어 있지 않습니다"
        return 0
    fi
    
    # FTP 서비스가 비활성화된 경우
    if [ -z "$ACTIVE_FTP" ]; then
        log_info "FTP 서비스가 비활성화되어 있습니다 (안전)"
        return 0
    fi
    
    local changes_made=false
    
    # U-53: 배너 설정
    log_info "Step 1: FTP 배너 설정 (U-53)"
    
    # vsFTPd 배너 설정
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ] && [ "$ACTIVE_FTP" = "vsftpd" ]; then
            if ! grep -q "^ftpd_banner=" "$vsftpd_conf"; then
                echo "" >> "$vsftpd_conf"
                echo "# KISA U-53: Hide FTP banner" >> "$vsftpd_conf"
                echo "ftpd_banner=FTP Server Ready" >> "$vsftpd_conf"
                log_success "✓ vsFTPd 배너 설정"
                changes_made=true
                
                # 서비스 재시작
                if systemctl is-active --quiet vsftpd 2>/dev/null; then
                    systemctl restart vsftpd 2>/dev/null
                    log_success "✓ vsFTPd 서비스 재시작"
                fi
            fi
            break
        fi
    done
    
    # ProFTPd 배너 설정
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ] && [ "$ACTIVE_FTP" = "proftpd" ]; then
            if ! grep -q "^ServerIdent" "$proftpd_conf"; then
                echo "" >> "$proftpd_conf"
                echo "# KISA U-53: Hide FTP banner" >> "$proftpd_conf"
                echo "ServerIdent off" >> "$proftpd_conf"
                log_success "✓ ProFTPd ServerIdent 설정"
                changes_made=true
                
                # 서비스 재시작
                if systemctl is-active --quiet proftpd 2>/dev/null; then
                    systemctl restart proftpd 2>/dev/null
                    log_success "✓ ProFTPd 서비스 재시작"
                fi
            fi
            break
        fi
    done
    
    # U-54: FTP 비활성화 권장
    if [ "${AUTO_DISABLE_FTP:-false}" = true ]; then
        log_info "Step 2: FTP 서비스 비활성화 (U-54)"
        
        # systemd 서비스 비활성화
        for service in "${FTP_SERVICES[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service" 2>/dev/null
                systemctl disable "$service" 2>/dev/null
                log_success "✓ $service 비활성화"
                changes_made=true
            fi
        done
        
        # inetd 설정 비활성화
        if [ -f /etc/inetd.conf ]; then
            sed -i '/^[^#].*^ftp/s/^/#/' /etc/inetd.conf
            if systemctl is-active --quiet inetd 2>/dev/null; then
                systemctl restart inetd 2>/dev/null
            fi
        fi
        
        # xinetd 설정 비활성화
        if [ -f /etc/xinetd.d/ftp ]; then
            sed -i 's/disable.*=.*no/disable = yes/' /etc/xinetd.d/ftp
            if systemctl is-active --quiet xinetd 2>/dev/null; then
                systemctl restart xinetd 2>/dev/null
            fi
        fi
    else
        log_warning ""
        log_warning "========================================="
        log_warning "FTP 서비스 사용 권장사항"
        log_warning "========================================="
        log_warning ""
        log_warning "FTP는 평문으로 통신하여 보안상 취약합니다."
        log_warning "SFTP 또는 FTPS 사용을 권장합니다."
        log_warning ""
        log_warning "FTP 비활성화 방법:"
        log_warning "  1. 수동 비활성화:"
        log_warning "     sudo systemctl stop $ACTIVE_FTP"
        log_warning "     sudo systemctl disable $ACTIVE_FTP"
        log_warning ""
        log_warning "  2. 자동 비활성화 (주의!):"
        log_warning "     sudo AUTO_DISABLE_FTP=true ./kisa-hardening.sh -m U-53"
        log_warning ""
    fi
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # vsFTPd 배너 검증
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            if grep -q "^ftpd_banner=" "$vsftpd_conf"; then
                log_success "✓ vsFTPd: 배너 설정됨 (U-53)"
            fi
        fi
    done
    
    # ProFTPd 배너 검증
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ]; then
            if grep -q "^ServerIdent" "$proftpd_conf"; then
                log_success "✓ ProFTPd: ServerIdent 설정됨 (U-53)"
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
    log_info "=== FTP 서비스 점검 완료 ==="
    log_info "U-53: FTP 배너 설정"
    log_info "U-54: FTP 서비스 비활성화 권장"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # FTP 서비스 상태"
    log_info "  systemctl status vsftpd proftpd"
    log_info ""
    log_info "  # 배너 설정 확인"
    log_info "  grep ftpd_banner /etc/vsftpd/vsftpd.conf"
    log_info "  grep ServerIdent /etc/proftpd/proftpd.conf"
    log_info ""
    log_info "보안 권장사항:"
    log_info "  - FTP 대신 SFTP 사용 권장"
    log_info "  - FTPS (FTP over SSL/TLS) 사용 고려"
    log_info ""
}

# 스크립트 실행
main "$@"
