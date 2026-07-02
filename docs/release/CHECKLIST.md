# 릴리스 체크리스트

릴리스마다 이 목록을 복사해 채운다. 상세 근거는 [RELEASE.md](./RELEASE.md).

## vX.Y.Z — YYYY-MM-DD

### 사전 점검
- [ ] `git switch main && git pull` — 최신 상태
- [ ] `tests/run.sh` 전체 green
- [ ] `shellcheck -x` 대상 스크립트 error 0
- [ ] `git status` clean (미커밋 없음)
- [ ] 버전 자리 결정 (MAJOR/MINOR/PATCH) — BREAKING 여부 확인

### 버전 기록
- [ ] `VERSION` 갱신
- [ ] `CHANGELOG.md` 최상단에 이번 버전 섹션 (사용자 관점 변경, why 위주)
- [ ] `docs/REQUIREMENTS.md`·`docs/MILESTONES.md` 해당 항목 상태 갱신 (있으면)

### 발행
- [ ] `git commit -m "chore: release vX.Y.Z"`
- [ ] `git tag -a vX.Y.Z -m "vX.Y.Z — 요약"`  (annotated)
- [ ] `git push origin main --tags`
- [ ] `gh release create vX.Y.Z --title vX.Y.Z --notes "<CHANGELOG 섹션>"`

### 배포 후 검증
- [ ] 격리 환경에서 `curl … bootstrap.sh | bash` 설치
- [ ] `spinner-to-kor status` — repo/설치본 버전 == 발행 버전
- [ ] `spinner-to-kor verify` — 6항목 ✓
- [ ] 기존 설치 머신에서 `spinner-to-kor update` → 버전 반영·사용자 hook 보존 확인

### 문제 시
- [ ] 롤백: `gh release delete vX.Y.Z --yes` + `gh release edit <직전> --latest`
- [ ] 원인 CHANGELOG/이슈 기록
