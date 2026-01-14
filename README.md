kisa-hardening/
├── README.md
├── kisa-hardening.sh              # 메인 실행 스크립트
├── config/
│   ├── settings.conf              # 전역 설정
│   └── modules.conf               # 모듈 활성화/비활성화
├── lib/
│   ├── common.sh                  # 공통 함수
│   ├── logging.sh                 # 로깅 함수
│   ├── backup.sh                  # 백업 함수
│   └── validation.sh              # 검증 함수
├── modules/
│   ├── 01-account-management/
│   │   ├── U-01-root-remote-restriction.sh
│   │   ├── U-02-password-complexity.sh
│   │   ├── U-03-account-lockout.sh
│   │   └── ...
│   ├── 02-file-directory/
│   │   ├── U-10-file-permissions.sh
│   │   ├── U-11-owner-settings.sh
│   │   └── ...
│   ├── 03-service-management/
│   │   ├── U-20-unnecessary-services.sh
│   │   └── ...
│   ├── 04-patch-management/
│   ├── 05-log-management/
│   └── 06-network-security/
├── checks/
│   ├── pre-check.sh               # 사전 점검
│   └── post-check.sh              # 사후 검증
├── reports/
│   └── templates/
│       └── report-template.html
└── logs/
    └── .gitkeep