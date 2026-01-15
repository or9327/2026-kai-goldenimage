#!/bin/bash
# modules/03-service-management/U-56-57-ftpusers-security.sh
# DESC: ftpusers 파일 권한 및 root 차단 (U-56, U-57)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-56-57"
MODULE_NAME="ftpusers 파일 권한 및 root 차단"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# ftpusers 관련 파일 목록
declare -A FTPUSERS_FILES
FTPUSERS_FILES=(
    ["/etc/ftpusers"]="기본 FTP"
    ["/etc/ftpd/ftpusers"]="기본 FTP (ftpd)"
    ["/etc/vsftpd.ftpusers"]="vsFTPd"
    ["/etc/vsftpd/ftpusers"]="vsFTPd"
    ["/etc/vsftpd.user_list"]="vsFTPd user_list"
    ["/etc/vsftpd/user_list"]="vsFTPd user_list"
)

# ProFTPd 설정 파일
PROFTPD_CONF_FILES=(
    "/etc/proftpd.conf"
    "/etc/proftpd/proftpd.conf"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local found_files=0
    
    # ftpusers 파일 확인
    for file in "${!FTPUSERS_FILES[@]}"; do
        if [ -f "$file" ]; then
            found_files=$((found_files + 1))
            log_info "발견: $file (${FTPUSERS_FILES[$file]})"
            
            # U-56: 파일 권한 확인
            local owner=$(stat -c "%U" "$file")
            local perms=$(stat -c "%a" "$file")
            
            if [ "$owner" != "root" ] || [ "$perms" != "640" ]; then
                log_warning "$file: 권한 변경 필요 (현재: $owner $perms)"
                needs_update=true
            fi
            
            # U-57: root 계정 차단 확인
            if ! grep -q "^root" "$file" 2>/dev/null; then
                log_warning "$file: root 계정 차단 미설정"
                needs_update=true
            fi
        fi
    done
    
    # ProFTPd 설정 확인
    for conf_file in "${PROFTPD_CONF_FILES[@]}"; do
        if [ -f "$conf_file" ]; then
            log_info "발견: $conf_file (ProFTPd)"
            
            # 파일 권한 확인
            local owner=$(stat -c "%U" "$conf_file")
            local perms=$(stat -c "%a" "$conf_file")
            
            if [ "$owner" != "root" ] || [ "$perms" != "640" ]; then
                log_warning "$conf_file: 권한 변경 필요 (현재: $owner $perms)"
                needs_update=true
            fi
            
            # RootLogin 설정 확인
            if ! grep -q "^RootLogin off" "$conf_file" 2>/dev/null; then
                log_warning "$conf_file: RootLogin off 미설정"
                needs_update=true
            fi
        fi
    done
    
    if [ "$found_files" -eq 0 ]; then
        log_success "✓ FTP 관련 파일 없음"
        return 0
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ ftpusers 파일 보안 설정 완료"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    # ftpusers 파일 백업
    for file in "${!FTPUSERS_FILES[@]}"; do
        if [ -f "$file" ]; then
            backup_file "$file" "$MODULE_ID"
        fi
    done
    
    # ProFTPd 설정 백업
    for conf_file in "${PROFTPD_CONF_FILES[@]}"; do
        if [ -f "$conf_file" ]; then
            backup_file "$conf_file" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] ftpusers 파일 보안 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: ftpusers 파일 권한 및 root 차단 설정
    log_info "Step 1: ftpusers 파일 보안 설정 (U-56, U-57)"
    
    for file in "${!FTPUSERS_FILES[@]}"; do
        if [ -f "$file" ]; then
            # U-56: 소유자 및 권한 설정
            chown root:root "$file" 2>/dev/null
            chmod 640 "$file" 2>/dev/null
            log_success "✓ $file: root:root 640"
            
            # U-57: root 계정 차단 확인 및 추가
            if ! grep -q "^root" "$file" 2>/dev/null; then
                echo "root" >> "$file"
                log_success "✓ $file: root 계정 차단 추가"
                changes_made=true
            fi
            
            # 기본 시스템 계정도 차단 (권장)
            for account in bin daemon adm lp sync shutdown halt mail operator nobody; do
                if ! grep -q "^${account}$" "$file" 2>/dev/null; then
                    echo "$account" >> "$file"
                fi
            done
            
            log_success "✓ $file: 시스템 계정 차단 추가"
            changes_made=true
        fi
    done
    
    # Step 2: vsFTPd 설정 확인
    for vsftpd_conf in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        if [ -f "$vsftpd_conf" ]; then
            log_info "Step 2: vsFTPd 설정 확인"
            
            # userlist_enable 확인
            if ! grep -q "^userlist_enable" "$vsftpd_conf"; then
                echo "" >> "$vsftpd_conf"
                echo "# KISA U-56, U-57: Enable user list" >> "$vsftpd_conf"
                echo "userlist_enable=YES" >> "$vsftpd_conf"
                echo "userlist_deny=YES" >> "$vsftpd_conf"
                log_success "✓ userlist_enable=YES 설정"
                changes_made=true
            fi
            
            # vsFTPd 재시작
            if systemctl is-active --quiet vsftpd 2>/dev/null; then
                systemctl restart vsftpd 2>/dev/null
                log_success "✓ vsFTPd 서비스 재시작"
            fi
        fi
    done
    
    # Step 3: ProFTPd 설정
    for conf_file in "${PROFTPD_CONF_FILES[@]}"; do
        if [ -f "$conf_file" ]; then
            log_info "Step 3: ProFTPd 설정"
            
            # 파일 권한 설정
            chown root:root "$conf_file" 2>/dev/null
            chmod 640 "$conf_file" 2>/dev/null
            log_success "✓ $conf_file: root:root 640"
            
            # RootLogin off 설정
            if ! grep -q "^RootLogin off" "$conf_file"; then
                if grep -q "^RootLogin" "$conf_file"; then
                    sed -i 's/^RootLogin.*/RootLogin off/' "$conf_file"
                else
                    echo "" >> "$conf_file"
                    echo "# KISA U-57: Disable root login" >> "$conf_file"
                    echo "RootLogin off" >> "$conf_file"
                fi
                log_success "✓ RootLogin off 설정"
                changes_made=true
            fi
            
            # ProFTPd 재시작
            if systemctl is-active --quiet proftpd 2>/dev/null; then
                systemctl restart proftpd 2>/dev/null
                log_success "✓ ProFTPd 서비스 재시작"
            fi
        fi
    done
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # ftpusers 파일 검증
    for file in "${!FTPUSERS_FILES[@]}"; do
        if [ -f "$file" ]; then
            # 권한 확인
            local owner=$(stat -c "%U" "$file")
            local perms=$(stat -c "%a" "$file")
            
            if [ "$owner" = "root" ] && [ "$perms" = "640" ]; then
                log_success "✓ $file: root 640 (U-56)"
            else
                log_error "✗ $file: $owner $perms"
                validation_failed=true
            fi
            
            # root 차단 확인
            if grep -q "^root" "$file" 2>/dev/null; then
                log_success "✓ $file: root 계정 차단 (U-57)"
            else
                log_error "✗ $file: root 계정 차단 미설정"
                validation_failed=true
            fi
        fi
    done
    
    # ProFTPd 검증
    for conf_file in "${PROFTPD_CONF_FILES[@]}"; do
        if [ -f "$conf_file" ]; then
            # 권한 확인
            local owner=$(stat -c "%U" "$conf_file")
            local perms=$(stat -c "%a" "$conf_file")
            
            if [ "$owner" = "root" ] && [ "$perms" = "640" ]; then
                log_success "✓ $conf_file: root 640"
            else
                log_error "✗ $conf_file: $owner $perms"
                validation_failed=true
            fi
            
            # RootLogin 확인
            if grep -q "^RootLogin off" "$conf_file"; then
                log_success "✓ $conf_file: RootLogin off (U-57)"
            else
                log_error "✗ $conf_file: RootLogin off 미설정"
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
    log_info "=== ftpusers 파일 보안 설정 완료 ==="
    log_info "U-56: 파일 소유자 및 권한 설정"
    log_info "U-57: root 계정 FTP 접근 차단"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 파일 권한 확인"
    log_info "  ls -l /etc/ftpusers /etc/vsftpd/ftpusers /etc/vsftpd/user_list"
    log_info ""
    log_info "  # root 차단 확인"
    log_info "  grep '^root' /etc/ftpusers"
    log_info ""
    log_info "  # ProFTPd 설정 확인"
    log_info "  grep RootLogin /etc/proftpd/proftpd.conf"
    log_info ""
}

# 스크립트 실행
main "$@"
