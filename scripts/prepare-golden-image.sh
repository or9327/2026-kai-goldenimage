#!/bin/bash
# scripts/prepare-golden-image.sh
# DESC: 골든 이미지 생성 전 시스템 정리 및 초기화

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 확인 프롬프트
confirm() {
    local message="$1"
    read -p "$message (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# 메인 함수
main() {
    log_info "=============================================="
    log_info "  골든 이미지 준비 스크립트"
    log_info "=============================================="
    echo
    
    # Root 권한 확인
    if [ "$(id -u)" -ne 0 ]; then
        log_error "이 스크립트는 root 권한이 필요합니다"
        exit 1
    fi
    
    # 경고 메시지
    log_warning "이 스크립트는 시스템을 초기화합니다!"
    log_warning "골든 이미지 생성 직전에만 실행하세요"
    echo
    
    if ! confirm "계속하시겠습니까?"; then
        log_info "취소되었습니다"
        exit 0
    fi
    
    echo
    log_info "골든 이미지 준비 시작..."
    echo
    
    # 1. 타임존 설정
    set_timezone
    
    # 2. SSH 호스트 키 삭제 (필수)
    remove_ssh_host_keys
    
    # 3. Machine ID 초기화 (필수)
    reset_machine_id
    
    # 4. 네트워크 설정 초기화 (필수)
    reset_network_config
    
    # 5. 사용자 기록 삭제 (필수)
    clean_user_history
    
    # 6. 로그 파일 정리 (필수)
    clean_log_files
    
    # 7. 임시 파일 정리 (필수)
    clean_temp_files
    
    # 8. 패키지 캐시 정리 (권장)
    clean_package_cache
    
    # 9. 시스템 저널 정리 (권장)
    clean_system_journal
    
    # 10. Cloud-init 상태 초기화 (권장)
    reset_cloud_init
    
    # 11. GCP 특화 정리 (권장)
    clean_gcp_specific
    
    # 12. 보안 정리 (권장)
    clean_security_artifacts
    
    # 13. 디스크 공간 제로화 (선택적)
    if confirm "디스크 공간을 제로화하시겠습니까? (시간이 오래 걸림)"; then
        zero_free_space
    fi
    
    # 14. 최종 확인
    show_summary
    
    echo
    log_success "=============================================="
    log_success "  골든 이미지 준비 완료!"
    log_success "=============================================="
    echo
    log_info "다음 단계:"
    log_info "  1. 시스템 종료: sudo shutdown -h now"
    log_info "  2. GCP 콘솔에서 이미지 생성"
    log_info "  3. 생성된 이미지로 테스트 인스턴스 실행"
    echo
}

# 1. 타임존 설정
set_timezone() {
    log_info "[1/13] 타임존을 Asia/Seoul로 설정 중..."
    
    # 현재 타임존 확인
    local current_tz=$(timedatectl show --property=Timezone --value)
    
    if [ "$current_tz" = "Asia/Seoul" ]; then
        log_success "타임존이 이미 Asia/Seoul로 설정되어 있습니다"
    else
        timedatectl set-timezone Asia/Seoul
        log_success "타임존을 Asia/Seoul로 변경했습니다"
    fi
    
    # 확인
    log_info "현재 시간: $(date)"
}

# 2. SSH 호스트 키 삭제
remove_ssh_host_keys() {
    log_info "[2/13] SSH 호스트 키 삭제 중..."
    
    local key_count=0
    for key in /etc/ssh/ssh_host_*; do
        if [ -f "$key" ]; then
            rm -f "$key"
            key_count=$((key_count + 1))
        fi
    done
    
    if [ $key_count -gt 0 ]; then
        log_success "SSH 호스트 키 $key_count개 삭제됨"
        log_info "새 VM 부팅 시 자동으로 재생성됩니다"
    else
        log_info "삭제할 SSH 호스트 키가 없습니다"
    fi
}

# 3. Machine ID 초기화
reset_machine_id() {
    log_info "[3/13] Machine ID 초기화 중..."
    
    # /etc/machine-id
    if [ -f /etc/machine-id ]; then
        truncate -s 0 /etc/machine-id
        log_success "/etc/machine-id 초기화됨"
    fi
    
    # /var/lib/dbus/machine-id
    if [ -f /var/lib/dbus/machine-id ]; then
        rm -f /var/lib/dbus/machine-id
        ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
        log_success "/var/lib/dbus/machine-id 초기화됨"
    fi
}

# 4. 네트워크 설정 초기화
reset_network_config() {
    log_info "[4/13] 네트워크 설정 초기화 중..."
    
    # netplan persistent rules
    if [ -d /etc/netplan ]; then
        find /etc/netplan -name "*.yaml" -type f -exec rm -f {} \; 2>/dev/null || true
        log_success "Netplan 설정 삭제됨"
    fi
    
    # udev persistent net rules
    if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
        rm -f /etc/udev/rules.d/70-persistent-net.rules
        log_success "udev persistent net rules 삭제됨"
    fi
    
    # DHCP client ID
    rm -f /var/lib/dhcp/* 2>/dev/null || true
    rm -f /var/lib/dhclient/* 2>/dev/null || true
    
    log_success "네트워크 설정 초기화 완료"
}

# 5. 사용자 기록 삭제
clean_user_history() {
    log_info "[5/13] 사용자 기록 삭제 중..."
    
    local cleaned=0
    
    # root history
    if [ -f /root/.bash_history ]; then
        rm -f /root/.bash_history
        cleaned=$((cleaned + 1))
    fi
    
    # root SSH known_hosts
    if [ -f /root/.ssh/known_hosts ]; then
        rm -f /root/.ssh/known_hosts
        cleaned=$((cleaned + 1))
    fi
    
    # 모든 사용자 history
    for home_dir in /home/*; do
        if [ -d "$home_dir" ]; then
            rm -f "$home_dir/.bash_history" 2>/dev/null || true
            rm -f "$home_dir/.ssh/known_hosts" 2>/dev/null || true
            cleaned=$((cleaned + 1))
        fi
    done
    
    log_success "사용자 기록 $cleaned개 항목 삭제됨"
}

# 6. 로그 파일 정리
clean_log_files() {
    log_info "[6/13] 로그 파일 정리 중..."
    
    local cleaned_size=0
    
    # /var/log 로그 파일 정리
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    find /var/log -type f -name "*.log.*" -delete 2>/dev/null || true
    find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
    find /var/log -type f -name "*.1" -delete 2>/dev/null || true
    
    # 특정 로그 파일
    local log_files=(
        "/var/log/syslog"
        "/var/log/messages"
        "/var/log/auth.log"
        "/var/log/kern.log"
        "/var/log/daemon.log"
        "/var/log/apt/history.log"
        "/var/log/apt/term.log"
        "/var/log/dpkg.log"
        "/var/log/unattended-upgrades/unattended-upgrades.log"
        "/var/log/cloud-init.log"
        "/var/log/cloud-init-output.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            truncate -s 0 "$log_file"
        fi
    done
    
    log_success "로그 파일 정리 완료"
}

# 7. 임시 파일 정리
clean_temp_files() {
    log_info "[7/13] 임시 파일 정리 중..."
    
    # /tmp
    find /tmp -type f -delete 2>/dev/null || true
    find /tmp -mindepth 1 -type d -empty -delete 2>/dev/null || true
    
    # /var/tmp
    find /var/tmp -type f -delete 2>/dev/null || true
    find /var/tmp -mindepth 1 -type d -empty -delete 2>/dev/null || true
    
    # /var/cache
    rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
    rm -rf /var/cache/apt/*.bin 2>/dev/null || true
    
    log_success "임시 파일 정리 완료"
}

# 8. 패키지 캐시 정리
clean_package_cache() {
    log_info "[8/13] 패키지 캐시 정리 중..."
    
    if command -v apt-get &>/dev/null; then
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y
        log_success "APT 캐시 정리 완료"
    fi
    
    if command -v yum &>/dev/null; then
        yum clean all
        log_success "YUM 캐시 정리 완료"
    fi
}

# 9. 시스템 저널 정리
clean_system_journal() {
    log_info "[9/13] 시스템 저널 정리 중..."
    
    if command -v journalctl &>/dev/null; then
        # 저널 용량 확인
        local journal_size=$(journalctl --disk-usage | grep -oP '\d+\.\d+[GM]')
        
        # 저널 삭제
        journalctl --vacuum-time=1s 2>/dev/null || true
        journalctl --vacuum-size=1M 2>/dev/null || true
        
        log_success "시스템 저널 정리 완료 (이전 크기: $journal_size)"
    fi
}

# 10. Cloud-init 상태 초기화
reset_cloud_init() {
    log_info "[10/13] Cloud-init 상태 초기화 중..."
    
    if command -v cloud-init &>/dev/null; then
        cloud-init clean --logs --seed 2>/dev/null || true
        
        # cloud-init 디렉토리 정리
        rm -rf /var/lib/cloud/instances/* 2>/dev/null || true
        rm -rf /var/lib/cloud/instance 2>/dev/null || true
        rm -rf /var/lib/cloud/data/* 2>/dev/null || true
        
        log_success "Cloud-init 상태 초기화 완료"
    else
        log_info "Cloud-init이 설치되어 있지 않습니다"
    fi
}

# 11. GCP 특화 정리
clean_gcp_specific() {
    log_info "[11/13] GCP 특화 정리 중..."
    
    # Google Cloud Ops Agent 로그
    if [ -d /var/log/google-cloud-ops-agent ]; then
        find /var/log/google-cloud-ops-agent -type f -delete 2>/dev/null || true
        log_success "Ops Agent 로그 정리됨"
    fi
    
    # Google Guest Agent 상태
    if [ -d /var/lib/google ]; then
        find /var/lib/google -type f -name "*.state" -delete 2>/dev/null || true
        log_success "Guest Agent 상태 정리됨"
    fi
    
    log_success "GCP 특화 정리 완료"
}

# 12. 보안 정리
clean_security_artifacts() {
    log_info "[12/13] 보안 관련 정리 중..."
    
    # 임시 sudoers 파일 (테스트 계정 등)
    # 주의: 실제 사용 중인 sudoers 파일은 삭제하지 않음
    
    # 하드닝 스크립트 백업 정리 (선택적)
    if confirm "하드닝 스크립트 백업을 삭제하시겠습니까?"; then
        rm -rf /var/backups/kisa-hardening 2>/dev/null || true
        log_success "하드닝 스크립트 백업 삭제됨"
    fi
    
    log_success "보안 정리 완료"
}

# 13. 디스크 공간 제로화
zero_free_space() {
    log_info "[13/13] 디스크 공간 제로화 중 (시간이 오래 걸릴 수 있습니다)..."
    
    log_warning "이 작업은 디스크 I/O를 많이 사용합니다"
    
    # 빈 공간을 0으로 채움
    dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
    rm -f /EMPTY
    
    log_success "디스크 공간 제로화 완료"
}

# 최종 요약
show_summary() {
    echo
    log_info "=============================================="
    log_info "  최종 시스템 상태"
    log_info "=============================================="
    
    # 타임존
    log_info "타임존: $(timedatectl show --property=Timezone --value)"
    
    # SSH 호스트 키
    local key_count=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
    log_info "SSH 호스트 키: $key_count개 (0이어야 함)"
    
    # Machine ID
    local machine_id_size=$(stat -c%s /etc/machine-id 2>/dev/null || echo "0")
    log_info "Machine ID: $machine_id_size bytes (0이어야 함)"
    
    # 디스크 사용량
    log_info "디스크 사용량:"
    df -h / | tail -1
    
    echo
}

# 스크립트 실행
main "$@"
