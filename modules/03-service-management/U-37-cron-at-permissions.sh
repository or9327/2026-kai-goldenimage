#!/bin/bash
# modules/03-service-management/U-37-cron-at-permissions.sh
# DESC: cron/at 파일 권한 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-37"
MODULE_NAME="cron/at 파일 권한 설정"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# cron/at 관련 파일 및 권한 설정
# 형식: "파일경로:권한:설명"
declare -a CRON_AT_FILES=(
    "/usr/bin/crontab:750:crontab 명령어"
    "/usr/bin/at:750:at 명령어"
    "/etc/crontab:640:시스템 crontab"
    "/etc/cron.allow:640:cron 허용 목록"
    "/etc/cron.deny:640:cron 거부 목록"
    "/etc/at.allow:640:at 허용 목록"
    "/etc/at.deny:640:at 거부 목록"
    "/etc/cron.d:750:cron.d 디렉토리"
    "/etc/cron.daily:750:cron.daily 디렉토리"
    "/etc/cron.hourly:750:cron.hourly 디렉토리"
    "/etc/cron.monthly:750:cron.monthly 디렉토리"
    "/etc/cron.weekly:750:cron.weekly 디렉토리"
    "/var/spool/cron:750:cron spool 디렉토리"
    "/var/spool/cron/crontabs:750:crontabs 디렉토리"
    "/var/spool/at:750:at spool 디렉토리"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    for entry in "${CRON_AT_FILES[@]}"; do
        IFS=':' read -r filepath perms desc <<< "$entry"
        
        if [ ! -e "$filepath" ]; then
            continue
        fi
        
        local current_perms=$(stat -c "%a" "$filepath" 2>/dev/null)
        local current_owner=$(stat -c "%U" "$filepath" 2>/dev/null)
        
        if [ "$current_perms" != "$perms" ] || [ "$current_owner" != "root" ]; then
            log_warning "$filepath: $current_owner $current_perms (예상: root $perms)"
            needs_update=true
        fi
    done
    
    # SUID 비트 확인
    for cmd in /usr/bin/crontab /usr/bin/at; do
        if [ -f "$cmd" ]; then
            local perms=$(stat -c "%a" "$cmd")
            if [[ "$perms" =~ ^[4567] ]]; then
                log_warning "$cmd: SUID 비트 설정됨 (권장: 제거)"
                needs_update=true
            fi
        fi
    done
    
    if [ "$needs_update" = false ]; then
        log_success "✓ cron/at 파일 권한이 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략 (권한 설정만 수행)"
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] cron/at 권한 설정 시뮬레이션"
        return 0
    fi
    
    local success_count=0
    local skip_count=0
    
    # Step 1: 파일/디렉토리 권한 설정
    log_info "Step 1: cron/at 파일 및 디렉토리 권한 설정"
    
    for entry in "${CRON_AT_FILES[@]}"; do
        IFS=':' read -r filepath perms desc <<< "$entry"
        
        if [ ! -e "$filepath" ]; then
            skip_count=$((skip_count + 1))
            continue
        fi
        
        # 소유자 변경
        chown root:root "$filepath" 2>/dev/null || chown root "$filepath" 2>/dev/null
        
        # 권한 변경
        if chmod "$perms" "$filepath" 2>/dev/null; then
            log_success "✓ $filepath: root $perms"
            success_count=$((success_count + 1))
        else
            log_error "✗ $filepath: 권한 변경 실패"
        fi
    done
    
    # Step 2: cron spool 디렉토리 내 파일 권한 설정
    log_info "Step 2: cron 작업 파일 권한 설정"
    
    for spool_dir in /var/spool/cron /var/spool/cron/crontabs; do
        if [ -d "$spool_dir" ]; then
            find "$spool_dir" -type f -exec chown root {} \; 2>/dev/null
            find "$spool_dir" -type f -exec chmod 640 {} \; 2>/dev/null
            log_success "✓ $spool_dir 내 파일 권한 설정"
        fi
    done
    
    # Step 3: at spool 디렉토리 내 파일 권한 설정
    log_info "Step 3: at 작업 파일 권한 설정"
    
    for at_dir in /var/spool/at /var/spool/cron/atjobs; do
        if [ -d "$at_dir" ]; then
            find "$at_dir" -type f -exec chown root {} \; 2>/dev/null
            find "$at_dir" -type f -exec chmod 640 {} \; 2>/dev/null
            log_success "✓ $at_dir 내 파일 권한 설정"
        fi
    done
    
    # Step 4: SUID 비트 제거 (선택적)
    if [ "${REMOVE_CRON_SUID:-false}" = true ]; then
        log_info "Step 4: crontab/at SUID 비트 제거"
        
        for cmd in /usr/bin/crontab /usr/bin/at; do
            if [ -f "$cmd" ]; then
                chmod u-s "$cmd" 2>/dev/null
                log_success "✓ $cmd: SUID 제거"
            fi
        done
    else
        log_info "Step 4: SUID 비트 유지 (제거하려면 REMOVE_CRON_SUID=true 설정)"
    fi
    
    log_info "결과: 성공 $success_count개, 건너뜀 $skip_count개"
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # 주요 파일만 검증
    local critical_files=(
        "/usr/bin/crontab:750"
        "/usr/bin/at:750"
        "/etc/crontab:640"
    )
    
    for entry in "${critical_files[@]}"; do
        IFS=':' read -r filepath perms <<< "$entry"
        
        if [ ! -f "$filepath" ]; then
            continue
        fi
        
        local current_perms=$(stat -c "%a" "$filepath")
        local current_owner=$(stat -c "%U" "$filepath")
        
        # SUID 제거 여부에 따라 권한이 다를 수 있음
        if [ "$current_owner" = "root" ]; then
            log_success "✓ $filepath: $current_owner $current_perms"
        else
            log_error "✗ $filepath: $current_owner $current_perms (예상: root $perms)"
            validation_failed=true
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
    log_info "=== cron/at 파일 권한 설정 완료 ==="
    log_info "예약 작업 관련 파일의 보안이 강화되었습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # crontab 권한 확인"
    log_info "  ls -l /usr/bin/crontab /usr/bin/at"
    log_info ""
    log_info "  # cron 디렉토리 권한 확인"
    log_info "  ls -ld /etc/cron.* /var/spool/cron"
    log_info ""
    log_info "참고:"
    log_info "  - SUID 비트는 기본적으로 유지됩니다"
    log_info "  - 제거하려면: REMOVE_CRON_SUID=true ./kisa-hardening.sh -m U-37"
    log_info ""
}

# 스크립트 실행
main "$@"
