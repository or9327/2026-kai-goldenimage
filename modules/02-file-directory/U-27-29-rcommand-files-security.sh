#!/bin/bash
# modules/02-file-directory-management/U-27-29-rcommand-files-security.sh
# DESC: r-command 관련 파일 보안 설정 (U-27, U-29)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-27-29"
MODULE_NAME="r-command 관련 파일 보안 설정"
MODULE_CATEGORY="파일 및 디렉토리 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# r-command 관련 파일 목록
RCOMMAND_FILES=(
    "/etc/hosts.equiv"
    "/root/.rhosts"
    "/etc/hosts.lpd"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local found_files=""
    
    # U-27: /etc/hosts.equiv, .rhosts 확인
    log_info "Step 1: r-command 파일 확인"
    
    for file in "${RCOMMAND_FILES[@]}"; do
        if [ -f "$file" ]; then
            log_warning "발견: $file"
            found_files="${found_files} ${file}"
            
            # + 옵션 확인
            if grep -q "^+" "$file" 2>/dev/null; then
                log_warning "  ⚠ '+' 옵션 발견 (모든 호스트 허용)"
            fi
            
            # 권한 확인
            local perms=$(stat -c "%a" "$file" 2>/dev/null)
            local owner=$(stat -c "%U" "$file" 2>/dev/null)
            
            if [ "$perms" != "600" ] || [ "$owner" != "root" ]; then
                log_warning "  현재 권한: $owner $perms (예상: root 600)"
                needs_update=true
            fi
        fi
    done
    
    # 사용자 홈 디렉토리의 .rhosts 확인
    if [ -d /home ]; then
        local user_rhosts=$(find /home -name ".rhosts" -type f 2>/dev/null)
        if [ -n "$user_rhosts" ]; then
            log_warning "사용자 .rhosts 파일 발견:"
            echo "$user_rhosts" | while read rhosts_file; do
                log_warning "  $rhosts_file"
                found_files="${found_files} ${rhosts_file}"
            done
            needs_update=true
        fi
    fi
    
    FOUND_FILES="$found_files"
    
    if [ -z "$found_files" ]; then
        log_success "✓ r-command 관련 파일 없음"
        return 0
    else
        log_warning "r-command 파일이 존재함 (보안 위험)"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -n "$FOUND_FILES" ]; then
        for file in $FOUND_FILES; do
            if [ -f "$file" ]; then
                backup_file "$file" "$MODULE_ID"
            fi
        done
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] r-command 파일 처리 시뮬레이션"
        if [ -n "$FOUND_FILES" ]; then
            for file in $FOUND_FILES; do
                log_info "[DRY RUN] $file 삭제 또는 보안 강화"
            done
        fi
        return 0
    fi
    
    if [ -z "$FOUND_FILES" ]; then
        log_info "처리할 파일이 없습니다"
        return 0
    fi
    
    local removed_count=0
    local secured_count=0
    
    # Step 1: r-command 파일 처리
    log_info "Step 1: r-command 파일 보안 처리"
    
    for file in $FOUND_FILES; do
        if [ ! -f "$file" ]; then
            continue
        fi
        
        # 옵션 1: 파일 삭제 (권장)
        if [ "${REMOVE_RCOMMAND_FILES:-true}" = true ]; then
            if rm -f "$file" 2>/dev/null; then
                log_success "✓ [삭제] $file"
                removed_count=$((removed_count + 1))
            else
                log_error "✗ [삭제 실패] $file"
            fi
        else
            # 옵션 2: 권한 강화
            log_info "[보안 강화] $file"
            
            # + 옵션 제거
            if grep -q "^+" "$file" 2>/dev/null; then
                sed -i '/^+/d' "$file"
                log_success "  ✓ '+' 옵션 제거"
            fi
            
            # 파일이 비어있으면 삭제
            if [ ! -s "$file" ]; then
                rm -f "$file"
                log_success "  ✓ 빈 파일 삭제"
                removed_count=$((removed_count + 1))
            else
                # 권한 강화
                chown root "$file" 2>/dev/null
                chmod 600 "$file" 2>/dev/null
                log_success "  ✓ 권한 변경: root 600"
                secured_count=$((secured_count + 1))
            fi
        fi
    done
    
    log_info "결과: 삭제 $removed_count개, 보안 강화 $secured_count개"
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # r-command 파일 재확인
    for file in "${RCOMMAND_FILES[@]}"; do
        if [ -f "$file" ]; then
            local perms=$(stat -c "%a" "$file" 2>/dev/null)
            local owner=$(stat -c "%U" "$file" 2>/dev/null)
            
            if [ "$perms" = "600" ] && [ "$owner" = "root" ]; then
                log_success "✓ $file: $owner $perms"
                
                # + 옵션 확인
                if grep -q "^+" "$file" 2>/dev/null; then
                    log_error "✗ $file: '+' 옵션 여전히 존재"
                    validation_failed=true
                fi
            else
                log_error "✗ $file: $owner $perms (예상: root 600)"
                validation_failed=true
            fi
        else
            log_success "✓ $file: 존재하지 않음 (안전)"
        fi
    done
    
    # 사용자 .rhosts 재확인
    local user_rhosts=$(find /home -name ".rhosts" -type f 2>/dev/null)
    if [ -n "$user_rhosts" ]; then
        log_warning "⚠ 사용자 .rhosts 파일 여전히 존재:"
        echo "$user_rhosts"
        validation_failed=true
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
    log_info "=== r-command 파일 보안 설정 완료 ==="
    log_info "r-command(rsh, rlogin, rcp)는 보안상 취약하므로 SSH 사용을 권장합니다."
    log_info ""
    log_info "처리된 항목:"
    log_info "  U-27: /etc/hosts.equiv, .rhosts 파일"
    log_info "  U-29: /etc/hosts.lpd 파일"
    log_info ""
    log_info "확인 명령어:"
    log_info "  ls -l /etc/hosts.equiv /etc/hosts.lpd /root/.rhosts 2>/dev/null"
    log_info "  find /home -name .rhosts 2>/dev/null"
    log_info ""
    log_info "참고:"
    log_info "  - r-command 서비스는 현대 시스템에서 사용하지 않습니다"
    log_info "  - SSH를 사용하세요"
    log_info ""
}

# 스크립트 실행
main "$@"
