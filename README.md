# KISA 보안 가이드 자동화 스크립트

Ubuntu 24.04 환경에서 **2026 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드**에 따른 보안 점검 항목(67개)을 자동으로 적용하는 Shell Script 기반 도구입니다.

## 📋 프로젝트 구조

```
kisa-hardening/
├── README.md                      # 프로젝트 문서
├── kisa-items.csv                 # 전체 항목 목록 (67개)
├── kisa-hardening.sh              # 메인 실행 스크립트
├── config/
│   ├── settings.conf              # 전역 설정
│   └── modules.conf               # 모듈 활성화/비활성화 (자동 생성)
├── lib/
│   ├── common.sh                  # 공통 함수
│   ├── logging.sh                 # 로깅 함수
│   ├── backup.sh                  # 백업 함수
│   └── validation.sh              # 검증 및 보고서 생성 함수
├── modules/
│   ├── 01-account-management/     # 계정 관리 (13개 항목)
│   │   ├── U-01-root-remote-restriction.sh
│   │   ├── U-02-password-complexity.sh
│   │   └── ...
│   ├── 02-file-directory/         # 파일 및 디렉토리 관리 (20개 항목)
│   ├── 03-service-management/     # 서비스 관리 (30개 항목)
│   ├── 04-patch-management/       # 패치 관리 (2개 항목)
│   └── 05-log-management/         # 로그 관리 (2개 항목)
├── scripts/
│   └── generate-modules-conf.sh   # modules.conf 자동 생성 스크립트
├── checks/
│   ├── pre-check.sh               # 사전 점검
│   └── post-check.sh              # 사후 검증
├── reports/
│   └── templates/
│       └── report-template.html
└── logs/                          # 실행 로그 및 결과
    └── .gitkeep
```

## 🎯 주요 기능

### 1. 67개 KISA 보안 항목 자동 점검
- **계정 관리** (13개): Root 접근 제한, 비밀번호 정책, 계정 관리
- **파일 및 디렉토리** (20개): 권한 설정, 소유자 관리, 특수 파일 점검
- **서비스 관리** (30개): 불필요한 서비스 비활성화, 보안 설정
- **패치 관리** (2개): 보안 패치, NTP 설정
- **로그 관리** (2개): 로깅 설정, 로그 디렉토리 권한

### 2. 유연한 실행 모드
- **전체 실행**: 모든 활성화된 모듈 실행
- **카테고리별 실행**: 특정 카테고리만 선택 실행
- **모듈별 실행**: 개별 모듈 선택 실행
- **드라이런 모드**: 실제 적용 없이 시뮬레이션
- **대화형 모드**: 각 모듈마다 확인 후 실행

### 3. 자동 백업 및 복구
- 모든 변경 전 자동 백업
- 타임스탬프 기반 백업 관리
- 백업 manifest 생성
- 30일 보관 정책 (설정 가능)

### 4. 상세한 로깅 및 보고서
- 실시간 컬러 로그 출력
- 파일 기반 로그 저장
- HTML 보고서 자동 생성
- JSON 형식 결과 저장

### 5. CSV 기반 항목 관리
- `kisa-items.csv`에서 전체 67개 항목 관리
- `generate-modules-conf.sh`로 자동 config 생성
- CSV 파일에서 직접 진행률 확인

## 🚀 빠른 시작

### 1. 사전 요구사항
- Ubuntu 24.04 LTS
- Root 권한
- 최소 500MB 디스크 여유 공간

### 2. 설치

```bash
# 저장소 클론
git clone <repository-url>
cd kisa-hardening

# 실행 권한 부여
chmod +x kisa-hardening.sh
chmod +x scripts/*.sh
chmod +x lib/*.sh

# modules.conf 생성 (처음 한 번만)
./scripts/generate-modules-conf.sh
```

### 3. 기본 실행

```bash
# 드라이런 모드로 먼저 테스트
sudo ./kisa-hardening.sh --dry-run

# 전체 실행 (활성화된 모듈만)
sudo ./kisa-hardening.sh

# 대화형 모드
sudo ./kisa-hardening.sh --interactive
```

## 📖 사용법

### 명령어 옵션

```bash
# 도움말 표시
./kisa-hardening.sh --help

# 모듈 목록 표시
./kisa-hardening.sh --list

# 드라이런 (시뮬레이션)
./kisa-hardening.sh --dry-run

# 대화형 모드
./kisa-hardening.sh --interactive

# 특정 카테고리만 실행
./kisa-hardening.sh --category 01-account-management

# 여러 카테고리 실행
./kisa-hardening.sh --category 01,02

# 특정 모듈만 실행
./kisa-hardening.sh --module U-01,U-02

# 설정 검증만 수행
./kisa-hardening.sh --validate

# 보고서만 생성
./kisa-hardening.sh --report-only

# 백업 건너뛰기 (권장하지 않음)
./kisa-hardening.sh --skip-backup
```

### 사용 예시

```bash
# 1. 계정 관리 항목만 드라이런
sudo ./kisa-hardening.sh -d -c 01-account-management

# 2. U-01, U-02 모듈만 실행
sudo ./kisa-hardening.sh -m U-01,U-02

# 3. 대화형 모드로 서비스 관리 점검
sudo ./kisa-hardening.sh -i -c 03-service-management

# 4. 전체 실행 후 보고서 확인
sudo ./kisa-hardening.sh
# 보고서: /var/log/kisa-hardening/reports/kisa-report-YYYYMMDD-HHMMSS.html
```

## ⚙️ 설정

### config/settings.conf

```bash
# 백업 설정
BACKUP_BASE_DIR="/root/kisa-backup"
BACKUP_RETENTION_DAYS=30

# 로그 설정
LOG_BASE_DIR="/var/log/kisa-hardening"
LOG_RETENTION_DAYS=90

# 보고서 설정
REPORT_BASE_DIR="/var/log/kisa-hardening/reports"
GENERATE_JSON_REPORT=true

# 실행 설정
STOP_ON_ERROR=false              # 오류 시 중단 여부
PARALLEL_EXECUTION=false         # 병렬 실행 (미구현)
```

### config/modules.conf

```bash
# CSV에서 자동 생성
./scripts/generate-modules-conf.sh

# 수동 편집
# U-01=enabled  # 활성화
# U-02=disabled # 비활성화
```

## 📝 모듈 추가 방법

### 1. CSV에 항목 추가

`kisa-items.csv`에 새 항목 추가:
```csv
1. 계정 관리,새로운 항목,상,U-XX,01-account-management
```

### 2. modules.conf 재생성

```bash
./scripts/generate-modules-conf.sh
```

### 3. 모듈 스크립트 작성

```bash
# 템플릿 복사
cp modules/01-account-management/U-01-root-remote-restriction.sh \
   modules/01-account-management/U-XX-new-item.sh

# 모듈 정보 수정
# DESC: 새로운 항목 설명
MODULE_ID="U-XX"
MODULE_NAME="새로운 항목"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="상"

# 로직 구현
# - check_current_status()
# - perform_backup()
# - apply_hardening()
# - validate_settings()
```

### 4. 테스트

```bash
# 드라이런으로 테스트
sudo ./kisa-hardening.sh -d -m U-XX

# 실제 실행
sudo ./kisa-hardening.sh -m U-XX
```

## 📊 진행 상황

### 현재 구현 현황

| 카테고리 | 완료 | 전체 | 진행률 |
|---------|-----|------|-------|
| 계정 관리 | 1 | 13 | 7.7% |
| 파일 및 디렉토리 | 0 | 20 | 0% |
| 서비스 관리 | 0 | 30 | 0% |
| 패치 관리 | 0 | 2 | 0% |
| 로그 관리 | 0 | 2 | 0% |
| **전체** | **1** | **67** | **1.5%** |

**진행률 확인**:
```bash
# CSV 기반 자동 진행률 계산
./scripts/check-progress.sh
```

자세한 항목 목록은 [kisa-items.csv](kisa-items.csv) 참조

## 🔧 트러블슈팅

### 문제: SSH 접속 불가

```bash
# 백업에서 복원
sudo cp /root/kisa-backup/TIMESTAMP/U-01/sshd_config.TIMESTAMP /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 문제: 모듈 실행 실패

```bash
# 로그 확인
tail -f /var/log/kisa-hardening/kisa-hardening-TIMESTAMP.log

# 특정 모듈만 드라이런
sudo ./kisa-hardening.sh -d -m U-XX
```

### 문제: 디스크 공간 부족

```bash
# 오래된 백업 정리
find /root/kisa-backup -type f -mtime +30 -delete

# 오래된 로그 정리
find /var/log/kisa-hardening -type f -mtime +90 -delete
```

## 🛡️ 보안 고려사항

1. **백업 필수**: 항상 백업을 생성하고 검증
2. **테스트 환경**: 프로덕션 적용 전 테스트 환경에서 검증
3. **단계적 적용**: 카테고리별로 나누어 적용
4. **롤백 계획**: 문제 발생 시 복구 절차 준비
5. **SSH 접속**: 최소 2개의 SSH 세션 유지

## 📚 참고 자료

- [KISA 보안 가이드 공식 문서](https://www.kisa.or.kr)
- [Ubuntu 24.04 보안 가이드](https://ubuntu.com/security)
- [CIS Ubuntu Benchmark](https://www.cisecurity.org)

## 🤝 기여 방법

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/new-module`)
3. Commit your changes (`git commit -am 'Add U-XX module'`)
4. Push to the branch (`git push origin feature/new-module`)
5. Create a new Pull Request

## 📄 라이선스

This project is licensed under the MIT License - see the LICENSE file for details.

## ✨ 작성자

LG CNS - Cloud Platform Team

## 📮 문의

프로젝트 관련 문의사항은 Issue를 통해 남겨주세요.

---

**주의**: 이 스크립트는 시스템의 중요한 보안 설정을 변경합니다. 반드시 테스트 환경에서 충분히 검증한 후 프로덕션에 적용하시기 바랍니다.

## ⚠️ 골든 이미지 부적합 항목

다음 항목들은 골든 이미지 단계에서 자동 적용하지 않습니다:

### U-06: 사용자 계정 su 기능 제한
- **이유**: 실제 사용자 계정이 없는 상태에서 wheel 그룹 설정 불가
- **적용 시점**: VM 배포 후 사용자 생성 시
- **적용 방법**: 
  ```bash
  # wheel 그룹 생성
  sudo groupadd wheel
  
  # PAM 설정
  echo "auth required pam_wheel.so use_uid" | sudo tee -a /etc/pam.d/su
  
  # su 권한 변경
  sudo chgrp wheel /usr/bin/su
  sudo chmod 4750 /usr/bin/su
  
  # 사용자 추가
  sudo usermod -G wheel username
  ```

### U-07: 불필요한 계정 제거
- **이유**: 환경마다 "불필요한 계정"의 정의가 다름
- **적용 시점**: VM 배포 후 보안 감사 시
- **적용 방법**: 
  ```bash
  # 계정 목록 확인
  cat /etc/passwd
  
  # 최근 로그인 확인
  last
  
  # 불필요한 계정 제거
  sudo userdel username
  ```

### U-08: 관리자 그룹 최소화
- **이유**: root 그룹에 포함할 사용자가 골든 이미지 단계에서는 없음
- **적용 시점**: VM 배포 후 사용자 생성 시
- **적용 방법**: 
  ```bash
  # root 그룹 멤버 확인
  grep "^root:" /etc/group
  
  # 불필요한 사용자 제거
  sudo gpasswd -d username root
  ```

### U-09: 불필요한 그룹 제거
- **이유**: 어떤 그룹이 "불필요"한지 환경별로 판단 필요
- **적용 시점**: VM 배포 후 보안 감사 시
- **적용 방법**: 
  ```bash
  # 그룹 목록 확인
  cat /etc/group
  
  # 그룹에 속한 파일 확인
  find / -group groupname 2>/dev/null
  
  # 불필요한 그룹 제거
  sudo groupdel groupname
  ```

### U-14: PATH 환경변수 설정
- **이유**: 사용자별 PATH는 사용자 생성 후 설정, 환경마다 필요 경로 상이
- **적용 시점**: VM 배포 후 사용자별 설정
- **적용 방법**: 
  ```bash
  # 전역 설정 (/etc/profile)
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  
  # 사용자별 설정 (~/.bashrc)
  PATH=$PATH:$HOME/bin
  ```

### U-15: 소유자 없는 파일 정리
- **이유**: 골든 이미지에는 해당 파일이 거의 없음, 배포 후 발생하는 문제
- **적용 시점**: VM 운영 중 정기 점검
- **적용 방법**: 
  ```bash
  # 소유자 없는 파일 찾기
  find / \( -nouser -o -nogroup \) -xdev -ls 2>/dev/null
  
  # 소유자 변경 또는 삭제
  sudo chown username:group filename
  sudo rm filename
  ```

### U-24: 사용자 홈 디렉터리 환경변수 파일 권한
- **이유**: 사용자 홈 디렉터리가 아직 없음
- **적용 시점**: VM 배포 후 사용자 생성 시
- **적용 방법**: 
  ```bash
  # 환경변수 파일 권한 설정
  chmod 644 ~/.bashrc ~/.bash_profile ~/.profile
  
  # 민감 파일 권한 강화
  chmod 600 ~/.netrc ~/.ssh/config
  ```


### U-25: world writable 파일 점검
- **이유**: /tmp 등 일부 디렉토리는 world writable이 필요, 파일 삭제는 위험
- **적용 시점**: VM 운영 중 정기 점검
- **적용 방법**: 
  ```bash
  # world writable 파일 찾기
  find / -type f -perm -2 -ls 2>/dev/null
  
  # 일반 사용자 쓰기 권한 제거
  sudo chmod o-w filename
  
  # 불필요한 파일 삭제
  sudo rm filename
  ```