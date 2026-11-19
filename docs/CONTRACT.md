# 도구 계약

> 1일차에 함께 정합니다. **혼자 바꾸지 않습니다.** 바꾸려면 상대에게 먼저 말하고, 이 표와 `src/soc/mocks.py`를 같이 고친 뒤 변경 이력에 적습니다.

🔍 기록 담당: 한지연  📘 문서 담당: 박소연  (둘 다 이름을 적으면 계약 성립)

## 도구 목록

| 도구 | 만드는 사람 | 입력 | 출력 (꼭 있어야 하는 칸) | 결과 개수 상한 | 실패하면 |
|---|---|---|---|---|---|
| `get_process_tree(host, pid)` | 🔍 | `host(str)`, `pid(int)` | `event_id`, `host`, `pid`, `process`, `ancestors`, `children` | 부모 최대 5단계 (자식 개수 상한 미정) | 대상 프로세스가 없으면 `process=None`, `ancestors=[]`, `children=[]`. 검색 오류는 예외 처리 |
| `get_process_activity(host, pid)` | 🔍 | `host(str)`, `pid(int)` | `event_id`, `host`, `pid`, `events` | 최대 50건 | 결과가 없으면 `events=[]`. 검색 오류는 예외 처리 |
| `get_host_timeline(host, around_ts, minutes)` | 🔍 | `host(str)`, `around_ts(str)`, `minutes(int=10)` | `event_id`, `host`, `from`, `to`, `events`, `truncated` | 최대 100건 | 결과가 없으면 `events=[]`, `truncated=False`. 검색 오류는 예외 처리 |
| `search_playbook(query, k)` | 📘 | `query(str)`, `k(int=3)` | `text`, `source`, `page`, `score` | 최대 5개 | 검색 결과가 없으면 `[]`. 검색 오류는 예외 처리 |
| `get_network_connections(host, minutes)` | 📘 (교차 작업) | `host(str)`, `minutes(int)` | `host`, `minutes`, `connections` (각 항목: `dst_ip`, `count`, `intervals_seconds`, `event_ids`) | 조회 최대 1,000건 | 결과가 없으면 `connections=[]`. 조회 오류는 예외 처리 |

## 꼭 합의할 것
- 🔍 텔레메트리 도구의 모든 결과에는 **`event_id`**가 있다. → 가드레일이 판정 근거를 추적하는 데 씁니다 (2일차 `G-1`).
- 📘 플레이북 검색 결과에는 **`source`(파일 이름)**가 있다. → 권고에 출처를 붙이는 데 씁니다.

## 변경 이력

| 바꾼 것 | 이유 | 둘 다 동의 |
|---|---|---|
| `get_network_connections` 추가 제안 | 반복적인 외부 IP 연결 횟수와 간격을 조사하기 위해 추가. D2-7 교차 작업 | 🔍 동의 |