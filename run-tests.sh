#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------
# HybrisMeter - the WHOLE test battery in one command. Never touches a real database.
#
#   ./run-tests.sh [--only db,be,live,svc,fe,installerapp,userapp] [--update-golden]
#
#   db      SQL tests on a DISPOSABLE database built from the sources (DB/SRC/hybrismeter/80_Tests/run-db-tests.sh)
#   be      BE/api pytest (mocked DB: unit + route security net, ~660 tests)
#   live    the real BE (uvicorn) started against that same disposable database: every GET endpoint with a real login
#           (web app) plus the installer-app flow (snapshot, refresh-key rotation, logout), then the end users' scope
#           (scenario 80_Tests/97.endUserScenario.sql + BE/api/tests/smoke_enduser.py) and the condominium
#           administrators' scope (98.condoAdminScenario.sql + smoke_condo.py)
#   svc     BE/consumption-service node tests (quiet window per building, schedule of the nightly run / full check);
#           its DB side (queue, triggers, procedures) is tested by the db level (96.test_consQueue.sql)
#   fe      FE type check (tsc --noEmit, a gate) + eslint (informational only: it has a large historical backlog)
#   installerapp  INSTALLERAPP (installer app) Android JVM unit tests (gradle testDebugUnitTest --offline). The instrumented tests
#           (androidTest) need a device/emulator and are NOT run here.
#   userapp USERAPP (end user Android app) JVM unit tests (gradle testDebugUnitTest --offline).
#
# Exit code 0 = every gate passed. The disposable database is dropped at the end. Connection settings of the test
# database server: HM_TEST_HOST / HM_TEST_PORT / HM_TEST_USER / HM_TEST_PASSWORD (default: localhost + BE/api/.env).
# --------------------------------------------------------------------------------------------------------------------
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBT="$ROOT/DB/SRC/hybrismeter/80_Tests"
BE="$ROOT/BE/api"
ONLY="db,be,live,svc,fe,installerapp,userapp"; UPDATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift;;
    --update-golden) UPDATE="--update-golden";;
    *) echo "unknown option: $1"; exit 2;;
  esac
  shift
done
want() { [[ ",$ONLY," == *",$1,"* ]]; }

envval() { grep "^$1=" "$BE/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
export HM_TEST_HOST="${HM_TEST_HOST:-localhost}" HM_TEST_PORT="${HM_TEST_PORT:-5432}"
export HM_TEST_USER="${HM_TEST_USER:-$(envval DB_USER)}" HM_TEST_PASSWORD="${HM_TEST_PASSWORD:-$(envval DB_PASSWORD)}"
LOGDIR="$(mktemp -d /tmp/hm_tests.XXXXXX)"
DB="hm_test_all_$(date +%Y%m%d_%H%M%S)_$$"
UVPID=""
RESULTS=(); FAILED=0
record() { RESULTS+=("$(printf '%-30s %-5s %s' "$1" "$2" "$3")"); [ "$2" = "ok" ] || [ "$2" = "info" ] || [ "$2" = "skip" ] || FAILED=1; }

cleanup() {
  [ -n "$UVPID" ] && kill "$UVPID" 2>/dev/null && wait "$UVPID" 2>/dev/null
  PGPASSWORD="$HM_TEST_PASSWORD" psql -h "$HM_TEST_HOST" -p "$HM_TEST_PORT" -U "$HM_TEST_USER" -d postgres -Atq \
    -c "drop database if exists $DB with (force)" >/dev/null 2>&1
}
trap cleanup EXIT

DB_OK=0
# ---------------------------------------------------------------------------------------------------------- db
if want db || want live; then
  echo "=== DB: SQL tests on the disposable database $DB ==="
  if "$DBT/run-db-tests.sh" --db "$DB" $UPDATE 2>&1 | tee "$LOGDIR/db.log" | grep -v -E '^$|^database kept'; [ "${PIPESTATUS[0]}" -eq 0 ]; then
    record "DB tests (SQL)" ok "$(grep -c ' ok ' "$LOGDIR/db.log") steps, see $LOGDIR/db.log"; DB_OK=1
  else
    record "DB tests (SQL)" FAIL "$(grep -m1 -E 'ERRORE:|ERROR:|BUILD FAILED|FAIL ' "$LOGDIR/db.log" | sed 's/^ *//' | cut -c1-200)"
  fi
fi

# ---------------------------------------------------------------------------------------------------------- be
if want be; then
  echo; echo "=== BE: pytest ==="
  if [ -x "$BE/venv/bin/python" ]; then
    if (cd "$BE" && venv/bin/python -m pytest tests -q > "$LOGDIR/be.log" 2>&1); then
      record "BE pytest" ok "$(tail -1 "$LOGDIR/be.log")"
    else
      record "BE pytest" FAIL "$(grep -m1 -E '^FAILED|^ERROR' "$LOGDIR/be.log" | cut -c1-200)"; tail -15 "$LOGDIR/be.log"
    fi
  else
    record "BE pytest" FAIL "BE/api/venv missing: run BE/api/setup.sh"
  fi
fi

# -------------------------------------------------------------------------------------------------------- live
if want live; then
  echo; echo "=== LIVE: the real BE against the disposable database ==="
  if [ "$DB_OK" -ne 1 ]; then
    record "BE live (web + installer)" FAIL "skipped: the disposable database is not ready"
  else
    PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1])")
    (cd "$BE" && DB_HOST="$HM_TEST_HOST" DB_PORT="$HM_TEST_PORT" DB_NAME="$DB" DB_USER="$HM_TEST_USER" DB_PASSWORD="$HM_TEST_PASSWORD" \
       exec venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" > "$LOGDIR/uvicorn.log" 2>&1) &
    UVPID=$!
    for _ in $(seq 1 60); do curl -s -o /dev/null "http://127.0.0.1:$PORT/openapi.json" && break; sleep 0.5; done
    if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/openapi.json"; then
      record "BE live (web + installer)" FAIL "the BE did not start, see $LOGDIR/uvicorn.log"
    else
      SMOKE="$BE/venv/bin/python $BE/tests/smoke_live.py --base http://127.0.0.1:$PORT"
      SMOKE_USER=hmtest_root SMOKE_PASSWORD='HmTest#2026' $SMOKE > "$LOGDIR/live_web.log" 2>&1; rc1=$?
      SMOKE_USER=hmtest_inst_a SMOKE_PASSWORD='HmTest#2026' $SMOKE --application 4 --allow-forbidden > "$LOGDIR/live_installer.log" 2>&1; rc2=$?
      grep -E "GET endpoints|FAIL" "$LOGDIR/live_web.log" | head -8
      grep -E "PASS|FAIL" "$LOGDIR/live_installer.log" | head -16
      [ "$rc1" -eq 0 ] && record "BE live: web GET endpoints" ok "$(grep 'GET endpoints' "$LOGDIR/live_web.log")" || record "BE live: web GET endpoints" FAIL "see $LOGDIR/live_web.log"
      [ "$rc2" -eq 0 ] && record "BE live: installer flow" ok "$(grep -c ' PASS' "$LOGDIR/live_installer.log") checks" || record "BE live: installer flow" FAIL "see $LOGDIR/live_installer.log"
      # end users (group 9) + staff scope: the scenario COMMITS on building 200, so it goes after everything else
      if PGPASSWORD="$HM_TEST_PASSWORD" psql -X -q -h "$HM_TEST_HOST" -p "$HM_TEST_PORT" -U "$HM_TEST_USER" -d "$DB" \
           -f "$DBT/97.endUserScenario.sql" > "$LOGDIR/live_enduser.log" 2>&1; then
        $BE/venv/bin/python $BE/tests/smoke_enduser.py --base "http://127.0.0.1:$PORT" >> "$LOGDIR/live_enduser.log" 2>&1; rc3=$?
        grep -E "^FAIL|^        -> |^END USER" "$LOGDIR/live_enduser.log" | head -20
        [ "$rc3" -eq 0 ] && record "BE live: end user scope" ok "$(grep 'END USER' "$LOGDIR/live_enduser.log")" || record "BE live: end user scope" FAIL "see $LOGDIR/live_enduser.log"
      else
        record "BE live: end user scope" FAIL "scenario 97 failed, see $LOGDIR/live_enduser.log"
      fi
      # condominium administrators (group 8): scenario 98 builds on 97
      if PGPASSWORD="$HM_TEST_PASSWORD" psql -X -q -h "$HM_TEST_HOST" -p "$HM_TEST_PORT" -U "$HM_TEST_USER" -d "$DB" \
           -f "$DBT/98.condoAdminScenario.sql" > "$LOGDIR/live_condo.log" 2>&1; then
        $BE/venv/bin/python $BE/tests/smoke_condo.py --base "http://127.0.0.1:$PORT" >> "$LOGDIR/live_condo.log" 2>&1; rc4=$?
        grep -E "^FAIL|^         -> |^CONDO ADMIN" "$LOGDIR/live_condo.log" | head -20
        [ "$rc4" -eq 0 ] && record "BE live: condo admin scope" ok "$(grep 'CONDO ADMIN' "$LOGDIR/live_condo.log")" || record "BE live: condo admin scope" FAIL "see $LOGDIR/live_condo.log"
      else
        record "BE live: condo admin scope" FAIL "scenario 98 failed, see $LOGDIR/live_condo.log"
      fi
    fi
    kill "$UVPID" 2>/dev/null; wait "$UVPID" 2>/dev/null; UVPID=""
  fi
fi

# --------------------------------------------------------------------------------------------------------- svc
if want svc; then
  echo; echo "=== SVC: consumption-service node tests ==="
  SVC="$ROOT/BE/consumption-service"
  if [ -d "$SVC/node_modules" ]; then
    if (cd "$SVC" && npm test > "$LOGDIR/svc.log" 2>&1); then
      record "SVC consumption-service" ok "$(grep -E '^ℹ pass' "$LOGDIR/svc.log" | sed 's/ℹ //') tests"
    else
      record "SVC consumption-service" FAIL "$(grep -m1 -E '✖' "$LOGDIR/svc.log" | cut -c1-200)"; tail -15 "$LOGDIR/svc.log"
    fi
  else
    record "SVC consumption-service" FAIL "BE/consumption-service/node_modules missing: npm install there"
  fi
fi

# ---------------------------------------------------------------------------------------------------------- fe
if want fe; then
  echo; echo "=== FE: type check + eslint ==="
  if [ -d "$ROOT/FE/node_modules" ]; then
    if (cd "$ROOT/FE" && npx tsc --noEmit > "$LOGDIR/fe_tsc.log" 2>&1); then record "FE type check (tsc)" ok ""; else record "FE type check (tsc)" FAIL "$(head -1 "$LOGDIR/fe_tsc.log" | cut -c1-200)"; head -8 "$LOGDIR/fe_tsc.log"; fi
    (cd "$ROOT/FE" && npx eslint > "$LOGDIR/fe_eslint.log" 2>&1)
    record "FE eslint (informational)" info "$(grep -E '^✖' "$LOGDIR/fe_eslint.log" || echo 'clean')"
  else
    record "FE checks" FAIL "FE/node_modules missing: run FE/setup.sh"
  fi
fi

# ------------------------------------------------------------------------------------------------------ installerapp
if want installerapp; then
  echo; echo "=== INSTALLERAPP: Android JVM unit tests ==="
  if [ -x "$ROOT/INSTALLERAPP/gradlew" ] && [ -f "$ROOT/INSTALLERAPP/local.properties" ]; then
    if (cd "$ROOT/INSTALLERAPP" && ./gradlew cleanTestDebugUnitTest testDebugUnitTest --offline > "$LOGDIR/installerapp.log" 2>&1); then
      n=$(cat "$ROOT"/INSTALLERAPP/app/build/test-results/testDebugUnitTest/*.xml | grep -o '<testsuite [^>]*tests="[0-9]*"' | grep -o 'tests="[0-9]*"' | tr -dc '0-9\n' | paste -sd+ | bc)
      record "INSTALLERAPP unit tests" ok "$n tests (androidTest not run: needs a device)"
    else
      record "INSTALLERAPP unit tests" FAIL "$(grep -m1 -E 'FAILED|error:|What went wrong' "$LOGDIR/installerapp.log" | cut -c1-200)"; tail -15 "$LOGDIR/installerapp.log"
    fi
  else
    record "INSTALLERAPP unit tests" skip "no gradle wrapper / Android SDK configured"
  fi
fi

# ------------------------------------------------------------------------------------------------------ userapp
if want userapp; then
  echo; echo "=== USERAPP: Android JVM unit tests ==="
  if [ -x "$ROOT/USERAPP/gradlew" ] && [ -f "$ROOT/USERAPP/local.properties" ]; then
    if (cd "$ROOT/USERAPP" && ./gradlew cleanTestDebugUnitTest testDebugUnitTest --offline > "$LOGDIR/userapp.log" 2>&1); then
      n=$(cat "$ROOT"/USERAPP/app/build/test-results/testDebugUnitTest/*.xml | grep -o '<testsuite [^>]*tests="[0-9]*"' | grep -o 'tests="[0-9]*"' | tr -dc '0-9\n' | paste -sd+ | bc)
      record "USERAPP unit tests" ok "$n tests"
    else
      record "USERAPP unit tests" FAIL "$(grep -m1 -E 'FAILED|error:|What went wrong' "$LOGDIR/userapp.log" | cut -c1-200)"; tail -15 "$LOGDIR/userapp.log"
    fi
  else
    record "USERAPP unit tests" skip "no gradle wrapper / Android SDK configured"
  fi
fi

echo; echo "=================== SUMMARY (logs: $LOGDIR) ==================="
printf '%s\n' "${RESULTS[@]}"
if [ "$FAILED" -eq 0 ]; then echo "ALL GATES PASSED"; else echo "SOME GATES FAILED"; fi
exit "$FAILED"
