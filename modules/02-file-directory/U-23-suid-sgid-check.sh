#!/bin/bash
# modules/02-file-directory-management/U-23-suid-sgid-check.sh
# DESC: SUID/SGID 설정 파일 점검

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-23"
MODULE_NAME="SUID/SGID 설정 파일 점검"
MODULE_CATEGORY="파일 및 디렉토리 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 일반적으로 허용되는 SUID/SGID 파일 (상대 경로 패턴)
ALLOWED_SUID_FILES=(
    # 기본 시스템 유틸리티
    "/usr/bin/sudo"
    "/usr/bin/su"
    "/usr/bin/passwd"
    "/usr/bin/chsh"
    "/usr/bin/chfn"
    "/usr/bin/newgrp"
    "/usr/bin/gpasswd"
    "/usr/bin/mount"
    "/usr/bin/umount"
    "/usr/bin/pkexec"
    
    # 패스워드 관리 (passwd 패키지)
    "/usr/bin/expiry"      # 패스워드 만료 정보 확인
    "/usr/bin/chage"       # 패스워드 aging 관리
    
    # SSH 관련
    "/usr/bin/ssh-agent"   # SSH 키 관리 에이전트
    "/usr/lib/openssh/ssh-keysign"
    
    # FUSE (선택적 - 환경에 따라)
    "/usr/bin/fusermount3" # FUSE 파일시스템 마운트 (gcsfuse, sshfs 등)
    "/usr/bin/fusermount"  # FUSE 구버전
    
    # PAM 인증
    "/usr/sbin/unix_chkpwd"
    "/usr/sbin/pam_extrausers_chkpwd" # PAM 추가 사용자 인증
    
    # D-Bus 및 PolicyKit
    "/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
    "/usr/lib/policykit-1/polkit-agent-helper-1"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    log_info "Step 1: SUID/SGID 파일 검색 중..."
    
    # SUID/SGID 파일 찾기 (주요 디렉토리만)
    local suid_files=$(find /usr /bin /sbin -user root -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)
    
    if [ -z "$suid_files" ]; then
        log_success "✓ SUID/SGID 파일 없음"
        return 0
    fi
    
    local suid_count=$(echo "$suid_files" | wc -l)
    log_info "발견된 SUID/SGID 파일: $suid_count개"
    
    # 파일 목록 저장
    FOUND_SUID_FILES="$suid_files"
    
    return 1
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략 (검증 전용 모듈)"
}

# 3. 설정 적용 (검증 및 보고만)
apply_hardening() {
    log_info "SUID/SGID 파일 분석 중..."
    
    if [ -z "$FOUND_SUID_FILES" ]; then
        log_info "검사할 파일이 없습니다"
        return 0
    fi
    
    local unknown_count=0
    local known_count=0
    
    # 파일 분류
    local unknown_files=""
    
    echo "$FOUND_SUID_FILES" | while read filepath; do
        local perms=$(stat -c "%a %U:%G" "$filepath" 2>/dev/null)
        local is_known=false
        
        # 허용 목록 확인
        for allowed in "${ALLOWED_SUID_FILES[@]}"; do
            if [ "$filepath" = "$allowed" ]; then
                is_known=true
                break
            fi
        done
        
        if [ "$is_known" = true ]; then
            log_success "✓ [허용] $filepath ($perms)"
        else
            log_warning "⚠ [검토필요] $filepath ($perms)"
            echo "$filepath" >> /tmp/unknown_suid_files.txt
        fi
    done
    
    # 요약
    if [ -f /tmp/unknown_suid_files.txt ]; then
        unknown_count=$(wc -l < /tmp/unknown_suid_files.txt)
        
        if [ "$unknown_count" -gt 0 ]; then
            log_warning ""
            log_warning "========================================="
            log_warning "검토가 필요한 SUID/SGID 파일: $unknown_count개"
            log_warning "========================================="
            log_warning ""
            log_warning "다음 파일들을 수동으로 검토하세요:"
            cat /tmp/unknown_suid_files.txt | while read file; do
                log_warning "  $file"
            done
            log_warning ""
            log_warning "제거 방법:"
            log_warning "  sudo chmod -s <파일명>"
            log_warning ""
            log_warning "특정 그룹만 사용하도록 제한:"
            log_warning "  sudo chgrp <그룹명> <파일명>"
            log_warning "  sudo chmod 4750 <파일명>"
            log_warning ""
        fi
        
        rm -f /tmp/unknown_suid_files.txt
    fi
    
    log_success "SUID/SGID 파일 분석 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 생략 (검증 전용 모듈)"
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "SUID/SGID 파일이 없습니다"
        exit 0
    fi
    
    # 백업 생략 (검증 전용)
    
    # 분석 수행
    if ! apply_hardening; then
        log_error "분석 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== SUID/SGID 파일 점검 완료 ==="
    log_info "이 모듈은 SUID/SGID 파일을 검증만 합니다."
    log_info "자동으로 제거하지 않으므로 수동 검토가 필요합니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 모든 SUID 파일 찾기"
    log_info "  find / -user root -type f -perm -4000 -ls 2>/dev/null"
    log_info ""
    log_info "  # 모든 SGID 파일 찾기"
    log_info "  find / -user root -type f -perm -2000 -ls 2>/dev/null"
    log_info ""
}

# 스크립트 실행
main "$@"