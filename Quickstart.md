# KISA 보안 가이드 자동화 - 빠른 시작

## 📋 개요

이 프로젝트는 KISA (한국인터넷진흥원) Linux 보안 가이드를 Ubuntu 24.04 골든 이미지에 자동으로 적용하는 스크립트입니다.


## 🚀 빠른 시작 (5분)

### 1. 테스트 실행 (드라이런)
```bash
# 프로젝트 디렉토리로 이동
cd kisa-hardening

# 전체 모듈 드라이런
sudo DRY_RUN_MODE=true ./kisa-hardening.sh --all

# 또는 특정 카테고리만
sudo DRY_RUN_MODE=true ./kisa-hardening.sh -c 01-account-management
```

### 2. 실제 적용
```bash
# 모든 보안 설정 적용
sudo ./kisa-hardening.sh --all

# 진행률 확인
./scripts/check-progress.sh
```

### 3. 골든 이미지 생성
```bash
# 시스템 정리 및 초기화
sudo ./scripts/prepare-golden-image.sh

# 시스템 종료
sudo shutdown -h now

# GCP 콘솔에서 이미지 생성
```


## 🎯 사용 시나리오

### 시나리오 1: 새 골든 이미지 생성
```bash
# 1. 모든 보안 설정 적용
sudo ./kisa-hardening.sh --all

# 2. 골든 이미지 준비
sudo ./scripts/prepare-golden-image.sh

# 3. 종료 및 이미지 생성
sudo shutdown -h now
```

### 시나리오 2: 기존 서버 보안 강화
```bash
# 1. 드라이런으로 영향 확인
sudo DRY_RUN_MODE=true ./kisa-hardening.sh --all

# 2. 카테고리별 단계적 적용
sudo ./kisa-hardening.sh -c 01-account-management
sudo ./kisa-hardening.sh -c 03-service-management
sudo ./kisa-hardening.sh -c 04-patch-management

# 3. 검증
sudo ./kisa-hardening.sh --validate
```

### 시나리오 3: 특정 모듈만 적용
```bash
# SSH 보안 강화
sudo ./kisa-hardening.sh -m U-01  # root 원격 접속 제한

# 패스워드 정책
sudo ./kisa-hardening.sh -m U-02  # 패스워드 복잡도
sudo ./kisa-hardening.sh -m U-03  # 계정 잠금

# 서비스 비활성화
sudo ./kisa-hardening.sh -m U-52  # Telnet 차단
sudo ./kisa-hardening.sh -m U-58  # SNMP 비활성화
```

## ⚙️ 주요 옵션

### 실행 모드
```bash
# 일반 모드 (실제 적용)
sudo ./kisa-hardening.sh --all

# 드라이런 모드 (시뮬레이션)
sudo DRY_RUN_MODE=true ./kisa-hardening.sh --all

# 검증 모드 (설정 확인)
sudo ./kisa-hardening.sh --validate
```

### 백업 관리
```bash
# 백업 활성화 (기본)
sudo ./kisa-hardening.sh --all

# 백업 비활성화
sudo SKIP_BACKUP=true ./kisa-hardening.sh --all

# 백업 복원
sudo ./scripts/restore-backup.sh /var/backups/kisa-hardening/TIMESTAMP
```

### 환경 변수
```bash
# 사용자 정의 배너
CUSTOM_BANNER="회사명 보안 경고" sudo ./kisa-hardening.sh -m U-62

# DNS 자동 비활성화
AUTO_DISABLE_DNS=true sudo ./kisa-hardening.sh -m U-49

# FTP 자동 비활성화
AUTO_DISABLE_FTP=true sudo ./kisa-hardening.sh -m U-53
```

## 🔍 진행률 확인

```bash
# 전체 진행률
./scripts/check-progress.sh

# 카테고리별 상세
./scripts/check-progress.sh --detailed

# 미구현 모듈만
./scripts/check-progress.sh --pending
```

## 📋 수동 적용 필요 항목

다음 항목들은 환경별로 다르므로 수동 설정이 필요합니다:

### 골든 이미지 부적합
- **U-50, U-51**: DNS Zone Transfer/동적 업데이트 (DNS 서버 사용 시)
- **U-59, U-60, U-61**: SNMP 보안 설정 (SNMP 사용 시)
- **U-64**: OS/커널 패치 (지속적인 운영 작업)

### 환경별 설정 필요
- **네트워크 방화벽**: 조직별 정책
- **감사 로그**: 중앙 집중식 로깅
- **백업 정책**: 조직별 요구사항

상세 내용은 `README.md`의 "수동 적용이 필요한 항목" 참조

## ⚠️ 주의사항

### 운영 환경 적용 전
1. **테스트 환경에서 먼저 검증**
2. **드라이런 모드로 영향 확인**
3. **백업 필수**
4. **점진적 적용 (카테고리별)**

### 골든 이미지 생성 시
1. **prepare-golden-image.sh는 초기화 스크립트**
2. **운영 서버에서 절대 실행 금지**
3. **실행 후 즉시 종료 (재부팅 금지)**
4. **SSH 호스트 키 삭제됨 (정상)**

### 롤백
```bash
# 백업에서 복원
sudo ./scripts/restore-backup.sh /var/backups/kisa-hardening/TIMESTAMP

# 또는 수동 복원
sudo cp /var/backups/kisa-hardening/TIMESTAMP/etc/ssh/sshd_config /etc/ssh/
sudo systemctl restart sshd
```

## 🐛 문제 해결

### SSH 연결 불가
```bash
# 설정 확인
sudo grep -E "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config

# 백업에서 복원
sudo cp /var/backups/kisa-hardening/*/etc/ssh/sshd_config /etc/ssh/
sudo systemctl restart sshd
```

### 모듈 실행 실패
```bash
# 로그 확인
cat /var/log/kisa-hardening.log

# 개별 모듈 재실행
sudo ./kisa-hardening.sh -m U-XX

# 검증
sudo ./kisa-hardening.sh --validate
```

### 골든 이미지 문제
```bash
# SSH 호스트 키 재생성
sudo ssh-keygen -A

# Machine ID 재생성
sudo rm /etc/machine-id
sudo systemd-machine-id-setup

# cloud-init 로그 확인
sudo cat /var/log/cloud-init.log
```

## 📚 추가 리소스

- **상세 문서**: `README.md`
- **KISA 가이드**: https://www.kisa.or.kr/
- **Ubuntu 보안**: https://ubuntu.com/security
- **GCP 베스트 프랙티스**: https://cloud.google.com/compute/docs/images

## 🤝 기여

버그 리포트, 개선 제안 환영합니다!

## 📄 라이선스

MIT License

---

**마지막 업데이트**: 2026-01-15
**버전**: 1.0.0
**지원 OS**: Ubuntu 24.04 LTS
**지원 플랫폼**: Google Cloud Platform