
# 런북: 우리가 겪은 장애와 찾는 법

> 02 문서 8장의 **'좋은 런북'** 형식으로 씁니다.
>
> 새벽 당번이 이것만 보고 해결할 수 있게, **실제로 친 명령과 실제 출력**을 남깁니다.

---

## 공통 1차 확인

### Kubernetes 환경

```bash
kubectl -n soc get pods,svc,ingress,pvc,jobs

kubectl -n soc get events --sort-by=.lastTimestamp | tail -20
```

> 교안의 Kubernetes 공통 확인 명령이다. 이번 인프라 0단계에서는 실행하지 않았다.

### Docker Compose 로컬 환경

```powershell
# 컨테이너 상태 확인
docker compose ps -a

# 전체 컨테이너와 호스트 포트 확인
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# PostgreSQL 호스트 포트 매핑 확인
docker port edr-ai-triage-agent-postgres-1

# PostgreSQL SQL 응답 확인
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;"
```

---

## 장애 기록

### [0-2] PostgreSQL 5432 포트 충돌 (출제: 📘 · 진단: 🔍 · 복구까지 걸린 시간: 미측정)

| 항목 | 내용 |
|---|---|
| 실습 환경 | Windows 11 / Docker Desktop / Docker Compose |
| 대상 | PostgreSQL 16 |
| 출제 | 📘 문서 담당 |
| 진단 및 복구 | 🔍 기록 담당 |
| 방식 | 팀원이 전달한 시나리오를 개인 로컬 환경에서 재현 |
| 결과 | 컨테이너 실행 및 호스트 포트 매핑 복구 확인 |

---

#### 증상

PostgreSQL 컨테이너를 중지한 뒤, Alpine 임시 컨테이너가 Windows 호스트의 `127.0.0.1:5432` 포트를 점유하도록 설정했다.

이후 기존 PostgreSQL을 다시 시작하자 **Docker 네트워크 구성 단계에서 호스트 포트 바인딩 오류**가 발생했다.

**실제 오류 출력**

```text
Container edr-ai-triage-agent-postgres-1 Starting
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint edr-ai-triage-agent-postgres-1 (7399f56eeaa7b26af7a0ce77e98331f73446e4e14f14783cd5a546a409af66ae): Bind for 127.0.0.1:5432 failed: port is already allocated
```

**핵심 오류**

```text
Bind for 127.0.0.1:5432 failed: port is already allocated
```

**오류 메시지 해석**

| 메시지 | 의미 |
|---|---|
| `Error response from daemon` | Docker Engine이 오류 반환 |
| `failed to set up container networking` | 컨테이너 네트워크 구성 실패 |
| `driver failed programming external connectivity` | 외부 연결을 위한 네트워크 설정 실패 |
| `Bind for 127.0.0.1:5432 failed` | 호스트 IP·포트 바인딩 실패 |
| `port is already allocated` | 해당 포트가 이미 할당됨 |

**최초 판단**

PostgreSQL 자체의 SQL 실행 오류가 아니라, Docker가 컨테이너를 시작하면서 **호스트 포트 5432를 할당하지 못한 문제**로 판단했다.

---

#### 확인 명령과 출력

##### [1] 장애 발생 전 정상 상태 확인

**실행 명령**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-before-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**결과 해석**

- PostgreSQL 컨테이너 내부에서 SQL 실행 성공
- `soc` 사용자로 `soc` 데이터베이스 접근 성공
- 장애 주입 전 SQL 응답 정상
- 이 명령만으로 Windows 호스트의 5432 포트 연결까지 검증한 것은 아님

---

##### [2] PostgreSQL 컨테이너 중지

**실행 명령**

```powershell
docker compose stop postgres
```

**실제 출력**

```text
[+] stop 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Stopped 0.8s
```

**중지 상태 확인**

```powershell
docker compose ps -a
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS                     PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 33 minutes              127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 33 minutes              127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Exited (0) 5 seconds ago
```

**결과 해석**

- PostgreSQL은 `Exited (0)`으로 정상 종료
- OpenSearch와 Dashboards는 실행 상태 유지
- PostgreSQL 컨테이너만 중지
- 기존 데이터 Named Volume은 삭제하지 않음

---

##### [3] Alpine 컨테이너로 5432 포트 점유

**실행 명령**

```powershell
docker run -d --name edr-port-blocker -p 127.0.0.1:5432:5432 alpine:3.20 sh -c "sleep 3600"
```

**실제 출력**

```text
Unable to find image 'alpine:3.20' locally
3.20: Pulling from library/alpine
25f1d6b1951a: Pull complete
3a030ca3f633: Download complete
d4050d56ebf2: Download complete
Digest: sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
Status: Downloaded newer image for alpine:3.20
5508dd2003e70d7d9e538ac74c62a381ce87fab7497bb68bec7b9b2f415109e5
```

**포트 점유 확인 명령**

```powershell
docker ps --filter "name=edr-port-blocker"
```

**실제 출력**

```text
CONTAINER ID   IMAGE         COMMAND                CREATED          STATUS          PORTS                      NAMES
5508dd2003e7   alpine:3.20   "sh -c 'sleep 3600'"   50 seconds ago   Up 49 seconds   127.0.0.1:5432->5432/tcp   edr-port-blocker
```

**결과 해석**

- Alpine 이미지 다운로드 성공
- `edr-port-blocker` 컨테이너 실행 성공
- `127.0.0.1:5432` 포트 매핑 확인
- Alpine 내부에서는 PostgreSQL을 실행하지 않음
- Docker의 호스트 포트 매핑만으로도 충돌 상황을 만들 수 있음

---

##### [4] PostgreSQL 재시작 및 장애 발생 확인

**실행 명령**

```powershell
docker compose up -d postgres 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-start-error.txt
```

**실제 출력**

```text
Container edr-ai-triage-agent-postgres-1 Starting
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint edr-ai-triage-agent-postgres-1 (7399f56eeaa7b26af7a0ce77e98331f73446e4e14f14783cd5a546a409af66ae): Bind for 127.0.0.1:5432 failed: port is already allocated
```

**장애 상태 확인 명령**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-failure-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS
edr-ai-triage-agent-dashboards-1   dashboards   Up 35 minutes
edr-ai-triage-agent-opensearch-1   opensearch   Up 35 minutes
edr-ai-triage-agent-postgres-1     postgres     Exited (128) 2 minutes ago
```

**포트 점유 확인 명령**

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-port-check.txt
```

**실제 출력**

```text
NAMES                              STATUS              PORTS
edr-port-blocker                   Up About a minute   127.0.0.1:5432->5432/tcp
edr-ai-triage-agent-dashboards-1   Up 35 minutes       127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   Up 35 minutes       127.0.0.1:9200->9200/tcp
```

**결과 해석**

- PostgreSQL 시작 실패
- PostgreSQL 상태가 `Exited (128)`로 변경
- Alpine 컨테이너는 계속 실행 중
- Alpine이 PostgreSQL의 호스트 포트 5432를 점유
- Docker 오류와 포트 점유 상태가 일치

**종료 상태 비교**

| 시점 | PostgreSQL 상태 | 의미 |
|---|---|---|
| 정상 중지 후 | `Exited (0)` | 정상 종료 |
| 포트 충돌 후 | `Exited (128)` | 시작 과정에서 실패 |

`Exited (128)`만으로 직접 원인을 확정하지 않고, Docker 오류와 포트 점유 결과를 함께 비교했다.

---

#### 원인

##### 직접 원인 — Docker 호스트 포트 5432 중복 점유

Alpine 임시 컨테이너가 PostgreSQL에서 사용해야 할 `127.0.0.1:5432` 포트를 먼저 점유했다.

그 결과 PostgreSQL을 다시 시작하려는 과정에서 Docker가 동일한 호스트 포트를 할당하지 못했다.

**장애 구조**

```text
Windows Host
127.0.0.1:5432
       |
       +---- Alpine (edr-port-blocker)
       |         |
       |         +-- 포트 할당 성공
       |
       +---- PostgreSQL
                 |
                 +-- 동일 포트 할당 요청
                 |
                 +-- Docker 네트워크 설정 실패
                 |
                 +-- 컨테이너 시작 실패
```

**원인 판단 근거**

| 증거 | 실제 결과 | 판단 |
|---|---|---|
| Alpine 컨테이너 | `Up` | 실행 중 |
| Alpine 포트 | `127.0.0.1:5432->5432/tcp` | 호스트 포트 점유 |
| PostgreSQL | `Exited (128)` | 시작 실패 |
| Docker 오류 | `port is already allocated` | 중복 포트 할당 실패 |
| OpenSearch | `Up` | 실행 유지 |
| Dashboards | `Up` | 실행 유지 |

**원인 판단**

최초 장애는 PostgreSQL 내부 설정이나 SQL 실행 문제가 아니라 **Docker Engine의 호스트 포트 충돌**로 발생했다.

---

#### 조치

##### [1] 포트를 점유한 Alpine 컨테이너 제거

**실행 명령**

```powershell
docker rm -f edr-port-blocker
```

**실제 출력**

```text
edr-port-blocker
```

**포트 점유 해제 확인**

```powershell
docker ps --filter "publish=5432"
```

**실제 출력**

```text
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

**결과 해석**

- Alpine 임시 컨테이너 제거 성공
- 실행 중인 Docker 컨테이너 중 호스트 5432 포트 게시 대상이 더 이상 표시되지 않음

---

##### [2] PostgreSQL 1차 복구

**실행 명령**

```powershell
docker compose up -d postgres
```

**실제 출력**

```text
[+] up 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Started 0.3s
```

**SQL 정상 응답 확인**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-after-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**1차 복구 결과**

- PostgreSQL 컨테이너 시작 성공
- PostgreSQL 내부 SQL 실행 성공
- Alpine 컨테이너 제거 완료

그러나 추가 검증에서 **호스트 포트 매핑이 복구되지 않은 문제**를 발견했다.

---

##### [3] 1차 복구 후 포트 매핑 미복원 확인

**컨테이너 상태 확인**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-after-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS          PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 37 minutes   127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 37 minutes   127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Up 6 seconds    5432/tcp
```

**정상 상태와 비교**

```text
최초 정상 상태
127.0.0.1:5432->5432/tcp

1차 복구 상태
5432/tcp
```

**호스트 포트 매핑 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**실제 결과**

출력 없음.

**Compose 설정 확인**

```powershell
(docker compose config --format json | ConvertFrom-Json).services.postgres.ports |
    Format-List
```

**실제 출력**

```text
mode      : ingress
host_ip   : 127.0.0.1
target    : 5432
published : 5432
protocol  : tcp
```

**컨테이너에 저장된 포트 바인딩 설정 확인**

```powershell
docker inspect --format '{{json .HostConfig.PortBindings}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```json
{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}]}
```

**실제 네트워크 포트 정보 확인**

```powershell
docker inspect --format '{{json .NetworkSettings.Ports}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```json
{"5432/tcp":[]}
```

**설정과 실제 상태 비교**

| 확인 항목 | 실제 결과 | 해석 |
|---|---|---|
| Compose 설정 | `127.0.0.1:5432` | 원하는 설정 존재 |
| HostConfig.PortBindings | `127.0.0.1:5432` | 저장된 설정 존재 |
| NetworkSettings.Ports | `{"5432/tcp":[]}` | 실제 호스트 포트 매핑 없음 |
| docker port | 출력 없음 | 포트 매핑 미복원 |
| SELECT 1 | 성공 | 컨테이너 내부 DB 정상 |

**추가 문제 분석**

PostgreSQL 컨테이너를 다시 시작했을 때 SQL 실행은 성공했지만 호스트 포트 매핑이 복원되지 않았다.

설정 파일과 컨테이너에 저장된 포트 바인딩에는 `127.0.0.1:5432`가 존재했다.

그러나 `NetworkSettings.Ports`에는 호스트 포트 목록이 비어 있었다.

앞선 포트 바인딩 실패 이후 기존 컨테이너를 재시작한 과정과 관련됐을 가능성이 있지만, Docker 내부의 정확한 발생 원인까지 확정하지는 않았다.

---

##### [4] PostgreSQL Named Volume 확인

컨테이너 재생성 전 데이터 저장소의 연결 상태를 확인했다.

**실행 명령**

```powershell
docker inspect --format '{{range .Mounts}}{{println .Type .Name .Destination}}{{end}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
volume edr-ai-triage-agent_postgres-data /var/lib/postgresql/data
```

**결과 해석**

| 항목 | 실제 값 |
|---|---|
| 저장소 유형 | `volume` |
| 볼륨 이름 | `edr-ai-triage-agent_postgres-data` |
| 마운트 경로 | `/var/lib/postgresql/data` |

- PostgreSQL이 Docker Named Volume을 사용 중임을 확인
- 컨테이너와 데이터 저장소가 별도로 관리되는 구조
- 재생성 후 동일 볼륨을 다시 연결하는 방식으로 진행
- 실제 데이터 행의 유지 여부는 별도로 검증하지 않음

---

##### [5] PostgreSQL 컨테이너 재생성

기존 PostgreSQL 컨테이너를 재생성하여 Compose 포트 설정을 새로 적용했다.

**실행 명령**

```powershell
docker compose up -d --no-deps --force-recreate postgres
```

**실제 출력**

```text
[+] up 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Started 1.2s
```

**명령 옵션 설명**

| 옵션 | 의미 |
|---|---|
| `-d` | 백그라운드 실행 |
| `--no-deps` | 의존 서비스는 함께 시작하지 않음 |
| `--force-recreate` | 기존 컨테이너를 교체해 재생성 |
| `postgres` | PostgreSQL 서비스만 대상으로 지정 |

**조치 목적**

- 기존 컨테이너 교체
- Compose 포트 바인딩 설정 다시 적용
- PostgreSQL 서비스만 대상으로 작업
- Named Volume은 삭제하지 않음

---

##### [6] 최종 복구 검증

**호스트 포트 매핑 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
5432/tcp -> 127.0.0.1:5432
```

**컨테이너 실행 상태 확인**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-final-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS          PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 49 minutes   127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 49 minutes   127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Up 13 seconds   127.0.0.1:5432->5432/tcp
```

**SQL 재검증**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-final-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**Named Volume 재연결 확인**

```powershell
docker inspect --format '{{range .Mounts}}{{println .Type .Name .Destination}}{{end}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
volume edr-ai-triage-agent_postgres-data /var/lib/postgresql/data
```

---

##### [7] 장애 발생 전후 결과 비교

| 비교 항목 | 최초 정상 | 장애 발생 | 1차 복구 | 최종 복구 |
|---|---|---|---|---|
| PostgreSQL 상태 | Up | Exited (128) | Up | Up |
| 호스트 5432 포트 | PostgreSQL 사용 | Alpine 사용 | 매핑 없음 | PostgreSQL 사용 |
| docker port | 정상 매핑 | 시작 실패 | 출력 없음 | 정상 매핑 |
| SELECT 1 | 성공 | 미실행 | 성공 | 성공 |
| OpenSearch | Up | Up | Up | Up |
| Dashboards | Up | Up | Up | Up |
| Named Volume | 구성 존재 | 삭제하지 않음 | 연결 확인 | 동일 볼륨 확인 |

**비교 분석**

1. 정상 중지 시 PostgreSQL은 `Exited (0)`이었다.
2. Alpine이 포트를 점유한 상태에서 재시작하자 `Exited (128)` 및 포트 바인딩 오류가 발생했다.
3. Alpine을 제거한 뒤 PostgreSQL은 실행됐지만 호스트 포트 매핑이 복원되지 않았다.
4. `HostConfig.PortBindings`와 `NetworkSettings.Ports`를 비교해 저장된 설정과 실제 네트워크 상태가 다른 점을 확인했다.
5. PostgreSQL 컨테이너를 재생성한 후 호스트 포트 매핑과 SQL 응답이 정상화됐다.

**최종 판단**

PostgreSQL 5432 포트 충돌을 재현했고, 직접 원인을 제거한 뒤 추가로 발견한 포트 매핑 문제까지 복구했다.

최종적으로 다음 항목을 확인했다.

- PostgreSQL 컨테이너 `Up`
- 호스트 포트 `127.0.0.1:5432` 매핑 복원
- `SELECT 1` 성공
- 기존 Named Volume 재연결
- OpenSearch와 Dashboards 실행 상태 유지

단, Windows 호스트에서 PostgreSQL로 직접 TCP 접속하는 검증과 기존 데이터 행의 보존 여부는 별도로 수행하지 않았다.

---

#### 진단 후 나눔 (깨 보기 규칙 5~6번)

##### 진단자: 가장 오래 걸린 지점과 이유

- 실제 복구 시간: 미측정
- 가장 오래 걸린 지점에 대한 개인 회고: 작성 예정

**이번 실습에서 추가로 발견한 문제**

- 최초 포트 충돌 해결 후에도 호스트 포트 매핑이 복원되지 않았음
- PostgreSQL 내부 SQL은 성공했지만 외부 포트 연결 정보는 비어 있었음
- 설정과 실제 적용 상태를 비교하는 추가 진단이 필요했음

**학습한 점**

- 컨테이너가 `Up`이어도 모든 기능이 정상이라는 보장은 없음
- SQL 성공과 호스트 포트 연결은 별도 검증 대상
- 장애 원인 제거 후에도 실제 상태를 재검증해야 함
- 필요한 경우 컨테이너 재시작과 재생성의 차이를 고려해야 함

---

##### 출제자: 나라면 어디부터 봤을지

- 📘 문서 담당의 실제 의견: 아직 확인하지 않음
- 팀원과 진단 순서를 비교한 후 작성 예정

---

##### 다음에 같은 증상을 보면 처음 칠 명령

**[1] 컨테이너 상태 확인**

```powershell
docker compose ps -a
```

**[2] 포트 점유 현황 확인**

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**[3] PostgreSQL 호스트 포트 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**명령별 목적**

| 명령 | 확인 목적 |
|---|---|
| `docker compose ps -a` | PostgreSQL 실행·종료 상태 |
| `docker ps` | 다른 컨테이너의 포트 점유 |
| `docker port` | PostgreSQL의 실제 호스트 포트 매핑 |

위 순서는 이번 실습을 기반으로 작성한 제안이며, 팀원과 최종 합의한 내용은 아니다.

---

#### 재발 방지

##### [1] 호스트 포트 충돌 사전 확인

- Docker Compose에서 사용하는 호스트 포트를 확인한다.
- 동일한 포트를 다른 컨테이너가 사용 중인지 점검한다.
- `port is already allocated` 메시지가 발생하면 포트 중복 사용 여부를 우선 확인한다.

##### [2] Docker 오류와 PostgreSQL 내부 오류 구분

- Docker 네트워크 설정 단계에서 실패했는지 확인한다.
- PostgreSQL 내부에서 발생한 오류인지 구분한다.
- 컨테이너 종료 코드 하나만으로 원인을 단정하지 않는다.

##### [3] 복구 후 호스트 포트 매핑 검증

- `docker compose ps -a`로 실행 상태를 확인한다.
- `docker port`로 호스트 포트 매핑을 확인한다.
- 설정과 실제 상태가 다르면 `docker inspect`로 비교한다.

##### [4] PostgreSQL 정상 응답 검증

- `SELECT 1`로 컨테이너 내부 SQL 응답을 확인한다.
- 호스트에서 접속해야 한다면 TCP 연결도 별도 확인한다.

##### [5] 데이터 보존을 고려한 복구

- 컨테이너 재생성 전 Named Volume을 확인한다.
- 재생성 후 동일 볼륨이 연결됐는지 확인한다.
- `docker compose down -v` 사용에 주의한다.
- 필요한 경우 실제 데이터 조회로 보존 여부를 검증한다.

---

#### 고장 예상표와 비교

02 문서 9-2에서 예상했던 고장인가? 증상과 '처음 확인할 곳'은 맞았나?

**출제자가 예상한 장애**

```text
PostgreSQL이 사용하는 호스트 포트 5432를
다른 컨테이너가 먼저 점유하도록 만든다.

PostgreSQL 시작 시 포트 충돌 오류가 발생한다.
```

**출제자가 예상한 오류**

```text
Bind for 127.0.0.1:5432 failed: port is already allocated
```

**실제 확인 결과**

- Alpine 컨테이너의 5432 포트 점유 확인
- PostgreSQL 재시작 실패 확인
- 출제자가 예상한 오류와 실제 오류 일치
- 1차 복구 후 호스트 포트 매핑이 복원되지 않는 추가 증상 발견

**예상과 실제 결과 비교**

| 비교 항목 | 실제 실습 결과 | 기존 고장 예상표와 비교 |
|---|---|---|
| 장애 유형 | PostgreSQL 5432 포트 충돌 | 기존 예상표 확인 필요 |
| 예상 오류 | `port is already allocated` | 출제자 예상과 일치 |
| 직접 원인 | Alpine의 5432 포트 점유 | 기존 예상표 확인 필요 |
| 처음 확인할 곳 | Docker 오류 및 포트 점유 | 기존 예상표 확인 필요 |
| 추가 발견 문제 | 1차 복구 후 포트 매핑 미복원 | 기존 예상표 확인 필요 |
| 최종 복구 | PostgreSQL 컨테이너 재생성 | 기존 예상표 확인 필요 |

**비교 결과**

출제자가 의도한 PostgreSQL 포트 충돌 장애는 실제로 재현됐다.

예상했던 오류 메시지와 실제 발생한 오류가 일치했다.

추가로, 포트 충돌 원인을 제거한 뒤에도 호스트 포트 매핑이 복구되지 않아 재검증과 컨테이너 재생성이 필요했다.

기존 02 문서 9-2의 개인 고장 예상표 원문과 비교한 결과는 아직 확인되지 않았다.
