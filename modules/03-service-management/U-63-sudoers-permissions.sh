#!/bin/bash
# modules/03-service-management/U-63-sudoers-permissions.sh
# DESC: /etc/sudoers 파일 권한 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-63"
MODULE_NAME="/etc/sudoers 파일 권한 설정"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# sudoers 관련 파일
SUDOERS_FILES=(
    "/etc/sudoers"
    "/etc/sudoers.d"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # /etc/sudoers 확인
    if [ -f /etc/sudoers ]; then
        local owner=$(stat -c "%U" /etc/sudoers)
        local perms=$(stat -c "%a" /etc/sudoers)
        
        log_info "/etc/sudoers: $owner $perms"
        
        # 권한은 440 또는 640이 허용됨
        if [ "$owner" != "root" ] || ([ "$perms" != "440" ] && [ "$perms" != "640" ]); then
            log_warning "/etc/sudoers: 권한 변경 필요"
            needs_update=true
        fi
    else
        log_error "/etc/sudoers 파일 없음"
        return 1
    fi
    
    # /etc/sudoers.d 확인
    if [ -d /etc/sudoers.d ]; then
        local dir_perms=$(stat -c "%a" /etc/sudoers.d)
        log_info "/etc/sudoers.d: $dir_perms"
        
        if [ "$dir_perms" != "750" ] && [ "$dir_perms" != "755" ]; then
            log_warning "/etc/sudoers.d: 권한 변경 필요"
            needs_update=true
        fi
        
        # sudoers.d 내 파일 확인
        for file in /etc/sudoers.d/*; do
            if [ -f "$file" ]; then
                local file_perms=$(stat -c "%a" "$file")
                if [ "$file_perms" != "440" ] && [ "$file_perms" != "640" ]; then
                    log_warning "$file: 권한 변경 필요 ($file_perms)"
                    needs_update=true
                fi
            fi
        done
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ sudoers 파일 권한 올바름"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략 (권한만 변경)"
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] sudoers 파일 권한 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: /etc/sudoers 권한 설정
    log_info "Step 1: /etc/sudoers 권한 설정"
    
    if [ -f /etc/sudoers ]; then
        chown root:root /etc/sudoers 2>/dev/null
        chmod 440 /etc/sudoers 2>/dev/null
        log_success "✓ /etc/sudoers: root:root 440"
        changes_made=true
    fi
    
    # Step 2: /etc/sudoers.d 권한 설정
    if [ -d /etc/sudoers.d ]; then
        log_info "Step 2: /etc/sudoers.d 권한 설정"
        
        chown root:root /etc/sudoers.d 2>/dev/null
        chmod 750 /etc/sudoers.d 2>/dev/null
        log_success "✓ /etc/sudoers.d: root:root 750"
        
        # sudoers.d 내 파일 권한 설정
        for file in /etc/sudoers.d/*; do
            if [ -f "$file" ]; then
                chown root:root "$file" 2>/dev/null
                chmod 440 "$file" 2>/dev/null
                log_success "✓ $file: root:root 440"
            fi
        done
        
        changes_made=true
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
    
    # /etc/sudoers 검증
    if [ -f /etc/sudoers ]; then
        local owner=$(stat -c "%U" /etc/sudoers)
        local perms=$(stat -c "%a" /etc/sudoers)
        
        if [ "$owner" = "root" ] && ([ "$perms" = "440" ] || [ "$perms" = "640" ]); then
            log_success "✓ /etc/sudoers: root $perms"
        else
            log_error "✗ /etc/sudoers: $owner $perms"
            validation_failed=true
        fi
    fi
    
    # /etc/sudoers.d 검증
    if [ -d /etc/sudoers.d ]; then
        local dir_owner=$(stat -c "%U" /etc/sudoers.d)
        local dir_perms=$(stat -c "%a" /etc/sudoers.d)
        
        if [ "$dir_owner" = "root" ]; then
            log_success "✓ /etc/sudoers.d: root $dir_perms"
        else
            log_error "✗ /etc/sudoers.d: $dir_owner $dir_perms"
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
    
    # 백업 생략
    
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
    log_info "=== sudoers 파일 권한 설정 완료 ==="
    log_info "/etc/sudoers 파일의 권한이 보안 기준에 맞게 설정되었습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  ls -l /etc/sudoers"
    log_info "  ls -l /etc/sudoers.d/"
    log_info ""
}

# 스크립트 실행
main "$@"
