#!/bin/bash
# modules/02-file-directory-management/U-26-dev-file-check.sh
# DESC: /dev 디렉토리 내 불필요한 device 파일 점검

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-26"
MODULE_NAME="/dev 디렉토리 내 불필요한 device 파일 점검"
MODULE_CATEGORY="파일 및 디렉토리 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    log_info "Step 1: /dev 내 일반 파일 검색 중..."
    
    # /dev 내 일반 파일 찾기 (character/block device가 아닌 것)
    # 현대 시스템에서는 udev가 자동 관리하므로 일반 파일이 있으면 의심
    local regular_files=$(find /dev -type f 2>/dev/null)
    
    if [ -z "$regular_files" ]; then
        log_success "✓ /dev 내 불필요한 일반 파일 없음"
        return 0
    fi
    
    local file_count=$(echo "$regular_files" | wc -l)
    log_warning "/dev 내 일반 파일 발견: $file_count개"
    
    echo "$regular_files" | while read file; do
        local size=$(stat -c "%s" "$file" 2>/dev/null)
        local perms=$(stat -c "%a" "$file" 2>/dev/null)
        log_warning "  $file (크기: $size bytes, 권한: $perms)"
    done
    
    # 파일 목록 저장
    FOUND_REGULAR_FILES="$regular_files"
    
    return 1
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 생략 (/dev는 백업하지 않음)"
}

# 3. 설정 적용
apply_hardening() {
    log_info "불필요한 파일 처리 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 파일 삭제 시뮬레이션"
        if [ -n "$FOUND_REGULAR_FILES" ]; then
            echo "$FOUND_REGULAR_FILES" | while read file; do
                log_info "[DRY RUN] 삭제할 파일: $file"
            done
        fi
        return 0
    fi
    
    if [ -z "$FOUND_REGULAR_FILES" ]; then
        log_info "처리할 파일이 없습니다"
        return 0
    fi
    
    local removed_count=0
    local skip_count=0
    
    # 안전한 파일은 건너뛰기 (예: 일부 시스템 파일)
    local safe_patterns=(
        "/dev/shm/"
        "/dev/mqueue/"
        "/dev/hugepages/"
        "/dev/pts/"
        "/dev/.udev/"
        "/dev/log"
        "/dev/xconsole"
    )
    
    echo "$FOUND_REGULAR_FILES" | while read file; do
        local is_safe=false
        
        # 안전 패턴 확인
        for pattern in "${safe_patterns[@]}"; do
            if [[ "$file" == *"$pattern"* ]]; then
                is_safe=true
                log_info "⏭ [보존] $file (시스템 파일)"
                skip_count=$((skip_count + 1))
                break
            fi
        done
        
        # 안전하지 않은 파일 삭제
        if [ "$is_safe" = false ]; then
            if [ "${AUTO_REMOVE:-false}" = true ]; then
                if rm -f "$file" 2>/dev/null; then
                    log_success "✓ [삭제] $file"
                    removed_count=$((removed_count + 1))
                else
                    log_error "✗ [실패] $file 삭제 실패"
                fi
            else
                log_warning "⚠ [확인필요] $file"
                echo "$file" >> /tmp/dev_files_to_review.txt
            fi
        fi
    done
    
    # 수동 검토 필요 파일 목록
    if [ -f /tmp/dev_files_to_review.txt ]; then
        local review_count=$(wc -l < /tmp/dev_files_to_review.txt)
        
        if [ "$review_count" -gt 0 ]; then
            log_warning ""
            log_warning "========================================="
            log_warning "수동 검토가 필요한 파일: $review_count개"
            log_warning "========================================="
            log_warning ""
            log_warning "다음 파일들을 검토 후 수동 삭제하세요:"
            cat /tmp/dev_files_to_review.txt | while read file; do
                log_warning "  $file"
            done
            log_warning ""
            log_warning "삭제 방법:"
            log_warning "  sudo rm /dev/<파일명>"
            log_warning ""
            log_warning "자동 삭제 (주의!):"
            log_warning "  sudo AUTO_REMOVE=true ./kisa-hardening.sh -m U-26"
            log_warning ""
        fi
        
        rm -f /tmp/dev_files_to_review.txt
    fi
    
    if [ "$removed_count" -gt 0 ]; then
        log_success "$removed_count개 파일 삭제됨"
    fi
    
    log_success "처리 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    # 일반 파일 재확인
    local remaining_files=$(find /dev -type f 2>/dev/null | grep -v -E "(shm|mqueue|hugepages|pts|.udev|log|xconsole)")
    
    if [ -z "$remaining_files" ]; then
        log_success "✓ /dev 내 불필요한 파일 없음"
        return 0
    else
        local count=$(echo "$remaining_files" | wc -l)
        log_warning "⚠ /dev 내 $count개 파일이 남아있음 (수동 검토 필요)"
        return 1
    fi
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
        log_error "처리 실패"
        exit 1
    fi
    
    # 드라이런 모드에서는 검증 스킵
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 검증 단계 생략"
        log_success "[$MODULE_ID] $MODULE_NAME - 완료 (드라이런)"
        exit 0
    fi
    
    # 설정 검증
    validate_settings
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== /dev 디렉토리 점검 완료 ==="
    log_info "현대 Linux는 udev가 device 파일을 자동 관리합니다."
    log_info "/dev 내 일반 파일은 보안 위험이 될 수 있습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # /dev 내 일반 파일 찾기"
    log_info "  find /dev -type f -ls 2>/dev/null"
    log_info ""
    log_info "  # /dev 내 device 파일 통계"
    log_info "  ls -l /dev | wc -l"
    log_info ""
}

# 스크립트 실행
main "$@"
