#!/bin/bash
# modules/02-file-directory-management/U-16-22-system-file-permissions.sh
# DESC: 주요 시스템 파일 권한 설정 (U-16 ~ U-22)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-16-22"
MODULE_NAME="주요 시스템 파일 권한 설정"
MODULE_CATEGORY="파일 및 디렉토리 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 시스템 파일 권한 설정 목록
# 형식: "파일경로:소유자:그룹:권한:모듈ID:설명"
declare -a FILE_PERMISSIONS=(
    "/etc/passwd:root:root:644:U-16:패스워드 파일"
    "/etc/shadow:root:root:400:U-18:쉐도우 패스워드 파일"
    "/etc/hosts:root:root:644:U-19:호스트 파일"
    "/etc/rsyslog.conf:root:root:640:U-21:로그 설정파일"
    "/etc/syslog.conf:root:root:640:U-21:로그 설정파일(구버전)"
    "/etc/services:root:root:644:U-22:서비스 파일"
    "/etc/inetd.conf:root:root:600:U-20:inetd 설정파일"
    "/etc/xinetd.conf:root:root:600:U-20:xinetd 설정파일"
    "/etc/systemd/system.conf:root:root:600:U-20:systemd 설정파일"
)

# 디렉토리 권한 설정 목록
# 참고: KISA는 chmod -R 600을 권장하지만, 디렉토리는 실행 권한이 필요하므로 750 사용
declare -a DIR_PERMISSIONS=(
    "/etc/xinetd.d:root:root:750:U-20:xinetd 서비스 디렉토리"
    "/etc/systemd:root:root:750:U-20:systemd 서비스 디렉토리"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local checked_count=0
    local ok_count=0
    
    # 파일 권한 확인
    for entry in "${FILE_PERMISSIONS[@]}"; do
        IFS=':' read -r filepath owner group perms module_id desc <<< "$entry"
        
        if [ ! -f "$filepath" ]; then
            continue
        fi
        
        checked_count=$((checked_count + 1))
        
        local current_perms=$(stat -c "%a" "$filepath" 2>/dev/null)
        local current_owner=$(stat -c "%U" "$filepath" 2>/dev/null)
        local current_group=$(stat -c "%G" "$filepath" 2>/dev/null)
        
        if [ "$current_perms" = "$perms" ] && \
           [ "$current_owner" = "$owner" ] && \
           ([ "$current_group" = "$group" ] || [ "$group" = "*" ]); then
            ok_count=$((ok_count + 1))
        else
            log_warning "$filepath: $current_owner:$current_group $current_perms (예상: $owner:$group $perms)"
            needs_update=true
        fi
    done
    
    # 디렉토리 권한 확인
    for entry in "${DIR_PERMISSIONS[@]}"; do
        IFS=':' read -r dirpath owner group perms module_id desc <<< "$entry"
        
        if [ ! -d "$dirpath" ]; then
            continue
        fi
        
        checked_count=$((checked_count + 1))
        
        local current_perms=$(stat -c "%a" "$dirpath" 2>/dev/null)
        local current_owner=$(stat -c "%U" "$dirpath" 2>/dev/null)
        
        if [ "$current_perms" = "$perms" ] && [ "$current_owner" = "$owner" ]; then
            ok_count=$((ok_count + 1))
        else
            log_warning "$dirpath/: $current_owner:$current_group $current_perms (예상: $owner:$group $perms)"
            needs_update=true
        fi
    done
    
    log_info "점검 대상: $checked_count개 파일/디렉토리"
    log_info "정상: $ok_count개"
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 모든 시스템 파일 권한이 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    for entry in "${FILE_PERMISSIONS[@]}"; do
        IFS=':' read -r filepath owner group perms module_id desc <<< "$entry"
        
        if [ -f "$filepath" ]; then
            backup_file "$filepath" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 파일 권한 설정 시뮬레이션"
        return 0
    fi
    
    local success_count=0
    local skip_count=0
    local fail_count=0
    
    # 파일 권한 설정
    log_info "Step 1: 파일 권한 설정 중..."
    
    for entry in "${FILE_PERMISSIONS[@]}"; do
        IFS=':' read -r filepath owner group perms module_id desc <<< "$entry"
        
        if [ ! -f "$filepath" ]; then
            skip_count=$((skip_count + 1))
            continue
        fi
        
        # 소유자 변경
        if ! chown "$owner:$group" "$filepath" 2>/dev/null; then
            # 그룹이 없으면 소유자만 변경
            chown "$owner" "$filepath" 2>/dev/null
        fi
        
        # 권한 변경
        if chmod "$perms" "$filepath" 2>/dev/null; then
            log_success "✓ $filepath: $owner:$group $perms"
            success_count=$((success_count + 1))
        else
            log_error "✗ $filepath: 권한 변경 실패"
            fail_count=$((fail_count + 1))
        fi
    done
    
    # 디렉토리 권한 설정
    log_info "Step 2: 디렉토리 권한 설정 중..."
    
    for entry in "${DIR_PERMISSIONS[@]}"; do
        IFS=':' read -r dirpath owner group perms module_id desc <<< "$entry"
        
        if [ ! -d "$dirpath" ]; then
            skip_count=$((skip_count + 1))
            continue
        fi
        
        # 디렉토리 자체 권한 설정
        chown "$owner:$group" "$dirpath" 2>/dev/null || chown "$owner" "$dirpath" 2>/dev/null
        chmod "$perms" "$dirpath" 2>/dev/null
        
        # /etc/xinetd.d 하위 파일 권한 설정 (U-20)
        if [ "$dirpath" = "/etc/xinetd.d" ]; then
            find "$dirpath" -type f -exec chown root:root {} \; 2>/dev/null
            find "$dirpath" -type f -exec chmod 600 {} \; 2>/dev/null
            log_success "✓ $dirpath/ 및 하위 파일 권한 설정 (파일: 600)"
        # /etc/systemd 하위 파일 권한 설정 (U-20)
        elif [ "$dirpath" = "/etc/systemd" ]; then
            # 하위 디렉토리는 750, 파일은 600
            find "$dirpath" -type d -exec chmod 750 {} \; 2>/dev/null
            find "$dirpath" -type f -exec chown root:root {} \; 2>/dev/null
            find "$dirpath" -type f -exec chmod 600 {} \; 2>/dev/null
            log_success "✓ $dirpath/ 권한 설정 (디렉토리: 750, 파일: 600)"
        else
            log_success "✓ $dirpath/: $owner:$group $perms"
        fi
        
        success_count=$((success_count + 1))
    done
    
    # U-17: systemd 시작 스크립트 권한
    log_info "Step 3: systemd 시작 스크립트 권한 설정 중... (U-17)"
    
    if [ -d /etc/systemd/system ]; then
        # other-write 권한 제거
        find /etc/systemd/system -type f -exec chmod o-w {} \; 2>/dev/null
        find /etc/systemd/system -type f -exec chown root {} \; 2>/dev/null
        log_success "✓ /etc/systemd/system/ 스크립트 권한 설정"
        success_count=$((success_count + 1))
    fi
    
    log_info "결과: 성공 $success_count, 건너뜀 $skip_count, 실패 $fail_count"
    
    if [ "$fail_count" -gt 0 ]; then
        return 1
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    local validated_count=0
    
    # 주요 파일만 검증
    local critical_files=(
        "/etc/passwd:root:root:644"
        "/etc/shadow:root:shadow:640"
        "/etc/hosts:root:root:644"
    )
    
    for entry in "${critical_files[@]}"; do
        IFS=':' read -r filepath owner group perms <<< "$entry"
        
        if [ ! -f "$filepath" ]; then
            continue
        fi
        
        local current_perms=$(stat -c "%a" "$filepath")
        local current_owner=$(stat -c "%U" "$filepath")
        local current_group=$(stat -c "%G" "$filepath")
        
        if [ "$current_perms" = "$perms" ] && [ "$current_owner" = "$owner" ]; then
            log_success "✓ $filepath: $current_owner:$current_group $current_perms"
            validated_count=$((validated_count + 1))
        else
            log_error "✗ $filepath: $current_owner:$current_group $current_perms (예상: $owner:$group $perms)"
            validation_failed=true
        fi
    done
    
    if [ "$validation_failed" = true ]; then
        return 1
    fi
    
    log_info "검증 완료: $validated_count개 핵심 파일"
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
    log_info "=== 시스템 파일 권한 설정 완료 ==="
    log_info "다음 항목들이 적용되었습니다:"
    log_info "  U-16: /etc/passwd (644)"
    log_info "  U-17: systemd 시작 스크립트"
    log_info "  U-18: /etc/shadow (640)"
    log_info "  U-19: /etc/hosts (644)"
    log_info "  U-20: 서비스 설정파일 (systemd, xinetd)"
    log_info "  U-21: 로그 설정파일 (640)"
    log_info "  U-22: /etc/services (644)"
    log_info ""
    log_info "확인 명령어:"
    log_info "  ls -l /etc/passwd /etc/shadow /etc/hosts /etc/services"
    log_info ""
}

# 스크립트 실행
main "$@"