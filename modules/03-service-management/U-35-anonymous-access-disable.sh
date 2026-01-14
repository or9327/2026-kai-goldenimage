#!/bin/bash
# modules/03-service-management/U-35-anonymous-access-disable.sh
# DESC: Anonymous FTP/NFS/Samba 접근 비활성화

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-35"
MODULE_NAME="Anonymous 접근 비활성화"
MODULE_CATEGORY="서비스 관리"
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
    
    # FTP 계정 확인
    log_info "Step 1: FTP 익명 계정 확인"
    if getent passwd ftp >/dev/null 2>&1 || getent passwd anonymous >/dev/null 2>&1; then
        log_warning "ftp 또는 anonymous 계정 존재"
        needs_update=true
    else
        log_success "✓ FTP 익명 계정 없음"
    fi
    
    # vsFTPd 확인
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            if grep -q "^anonymous_enable=YES" "$vsftpd_conf"; then
                log_warning "vsFTPd: anonymous 접근 활성화됨"
                needs_update=true
            fi
        fi
    done
    
    # ProFTPd 확인
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ]; then
            if grep -q "^<Anonymous" "$proftpd_conf"; then
                log_warning "ProFTPd: anonymous 접근 활성화됨"
                needs_update=true
            fi
        fi
    done
    
    # NFS 확인
    if [ -f /etc/exports ]; then
        if grep -qE "anonuid|anongid" /etc/exports; then
            log_warning "NFS: 익명 접근 옵션 설정됨"
            needs_update=true
        fi
    fi
    
    # Samba 확인
    if [ -f /etc/samba/smb.conf ]; then
        if grep -q "guest ok.*=.*yes" /etc/samba/smb.conf; then
            log_warning "Samba: guest 접근 허용됨"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ Anonymous 접근이 비활성화됨"
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
        "/etc/exports"
        "/etc/samba/smb.conf"
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
        log_info "[DRY RUN] Anonymous 접근 비활성화 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: FTP 익명 계정 제거
    log_info "Step 1: FTP 익명 계정 처리"
    
    for account in ftp anonymous; do
        if getent passwd "$account" >/dev/null 2>&1; then
            if userdel "$account" 2>/dev/null; then
                log_success "✓ $account 계정 제거"
                changes_made=true
            else
                log_warning "⚠ $account 계정 제거 실패 (계속 진행)"
            fi
        fi
    done
    
    # Step 2: vsFTPd 설정
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            log_info "Step 2: vsFTPd anonymous 접근 비활성화"
            
            # anonymous_enable=NO 설정
            sed -i 's/^anonymous_enable=YES/anonymous_enable=NO/' "$vsftpd_conf"
            
            # 설정이 없으면 추가
            if ! grep -q "^anonymous_enable" "$vsftpd_conf"; then
                echo "anonymous_enable=NO" >> "$vsftpd_conf"
            fi
            
            log_success "✓ vsFTPd 설정 완료"
            changes_made=true
            
            # 서비스 재시작
            if systemctl is-active --quiet vsftpd 2>/dev/null; then
                systemctl restart vsftpd 2>/dev/null
                log_success "✓ vsftpd 서비스 재시작"
            fi
        fi
    done
    
    # Step 3: ProFTPd 설정
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ]; then
            log_info "Step 3: ProFTPd anonymous 접근 비활성화"
            
            # <Anonymous> 섹션 주석 처리
            sed -i '/<Anonymous/,/<\/Anonymous>/s/^/#/' "$proftpd_conf"
            
            log_success "✓ ProFTPd 설정 완료"
            changes_made=true
            
            # 서비스 재시작
            if systemctl is-active --quiet proftpd 2>/dev/null; then
                systemctl restart proftpd 2>/dev/null
                log_success "✓ proftpd 서비스 재시작"
            fi
        fi
    done
    
    # Step 4: NFS 설정
    if [ -f /etc/exports ]; then
        log_info "Step 4: NFS 익명 접근 비활성화"
        
        # anonuid, anongid 옵션 제거
        sed -i 's/,anonuid=[0-9]*//g' /etc/exports
        sed -i 's/,anongid=[0-9]*//g' /etc/exports
        sed -i 's/anonuid=[0-9]*,//g' /etc/exports
        sed -i 's/anongid=[0-9]*,//g' /etc/exports
        
        log_success "✓ NFS 설정 완료"
        changes_made=true
        
        # NFS 서비스 재시작
        if systemctl is-active --quiet nfs-server 2>/dev/null; then
            exportfs -ra 2>/dev/null
            log_success "✓ NFS 설정 다시 로드"
        fi
    fi
    
    # Step 5: Samba 설정
    if [ -f /etc/samba/smb.conf ]; then
        log_info "Step 5: Samba guest 접근 비활성화"
        
        # guest ok = yes를 no로 변경
        sed -i 's/guest ok.*=.*yes/guest ok = no/i' /etc/samba/smb.conf
        
        log_success "✓ Samba 설정 완료"
        changes_made=true
        
        # Samba 서비스 재시작
        if systemctl is-active --quiet smbd 2>/dev/null; then
            smbcontrol all reload-config 2>/dev/null
            log_success "✓ Samba 설정 다시 로드"
        fi
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
    
    # FTP 계정 확인
    for account in ftp anonymous; do
        if getent passwd "$account" >/dev/null 2>&1; then
            log_warning "⚠ $account 계정이 여전히 존재함"
        fi
    done
    
    # vsFTPd 확인
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            if grep -q "^anonymous_enable=NO" "$vsftpd_conf"; then
                log_success "✓ vsFTPd: anonymous 비활성화"
            else
                log_error "✗ vsFTPd: anonymous 여전히 활성화"
                validation_failed=true
            fi
        fi
    done
    
    # ProFTPd 확인
    for proftpd_conf in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        if [ -f "$proftpd_conf" ]; then
            if ! grep -q "^<Anonymous" "$proftpd_conf"; then
                log_success "✓ ProFTPd: anonymous 비활성화"
            else
                log_error "✗ ProFTPd: anonymous 여전히 활성화"
                validation_failed=true
            fi
        fi
    done
    
    # NFS 확인
    if [ -f /etc/exports ]; then
        if ! grep -qE "anonuid|anongid" /etc/exports; then
            log_success "✓ NFS: 익명 접근 옵션 제거됨"
        else
            log_error "✗ NFS: 익명 접근 옵션 여전히 존재"
            validation_failed=true
        fi
    fi
    
    # Samba 확인
    if [ -f /etc/samba/smb.conf ]; then
        if ! grep -q "guest ok.*=.*yes" /etc/samba/smb.conf; then
            log_success "✓ Samba: guest 접근 비활성화"
        else
            log_error "✗ Samba: guest 접근 여전히 허용"
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
    log_info "=== Anonymous 접근 비활성화 완료 ==="
    log_info "다음 서비스의 익명 접근이 비활성화되었습니다:"
    log_info "  - FTP (vsFTPd, ProFTPd)"
    log_info "  - NFS"
    log_info "  - Samba"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # FTP 계정 확인"
    log_info "  getent passwd ftp anonymous"
    log_info ""
    log_info "  # vsFTPd 설정 확인"
    log_info "  grep anonymous_enable /etc/vsftpd/vsftpd.conf"
    log_info ""
    log_info "  # NFS 설정 확인"
    log_info "  grep -E 'anonuid|anongid' /etc/exports"
    log_info ""
    log_info "  # Samba 설정 확인"
    log_info "  grep 'guest ok' /etc/samba/smb.conf"
    log_info ""
}

# 스크립트 실행
main "$@"
