#!/usr/bin/env bash
#
# vpn-security-check.sh
#
# Sanity checks for the Gluetun/qBittorrent/Prowlarr stack (ClavicusVile).
# Verifies the VPN tunnel, DNS resolution, IPv6 exposure, and WebUI binding.
#
# Usage:
#   ./vpn-security-check.sh                 # standard checks (safe, non-disruptive)
#   ./vpn-security-check.sh --killswitch     # also test kill-switch behavior (pauses Gluetun briefly)
#
# Env:
#   GLUETUN_CONTAINER / QBIT_CONTAINER — override container names
#   WAIT_HEALTHY_SECS — seconds to wait for Gluetun healthy (default: 120; 0 skips wait)
#
# Exit code: 0 if all checks pass, 1 if any check fails.

set -uo pipefail

GLUETUN_CONTAINER="${GLUETUN_CONTAINER:-ClavicusVile-vpn}"
QBIT_CONTAINER="${QBIT_CONTAINER:-ClavicusVile}"
WAIT_HEALTHY_SECS="${WAIT_HEALTHY_SECS:-120}"
RUN_KILLSWITCH_TEST=false
GLUETUN_PAUSED=false

for arg in "$@"; do
    case "$arg" in
        --killswitch) RUN_KILLSWITCH_TEST=true ;;
    esac
done

PASS="\033[32mPASS\033[0m"
FAIL="\033[31mFAIL\033[0m"
WARN="\033[33mWARN\033[0m"
FAILURES=0

result() {
    # result <PASS|FAIL|WARN> <message>
    local status="$1"; shift
    case "$status" in
        PASS) echo -e "[$PASS] $*" ;;
        FAIL) echo -e "[$FAIL] $*"; FAILURES=$((FAILURES + 1)) ;;
        WARN) echo -e "[$WARN] $*" ;;
    esac
}

cleanup() {
    if $GLUETUN_PAUSED; then
        docker unpause "$GLUETUN_CONTAINER" >/dev/null 2>&1 || true
        GLUETUN_PAUSED=false
    fi
}
trap cleanup EXIT

echo "== VPN Security Check: $GLUETUN_CONTAINER =="
echo

# 0. Wait for Gluetun health (compose up returns before healthy)
if [[ "$WAIT_HEALTHY_SECS" -gt 0 ]]; then
    echo "Waiting up to ${WAIT_HEALTHY_SECS}s for Gluetun to become healthy..."
    deadline=$((SECONDS + WAIT_HEALTHY_SECS))
    health=""
    while (( SECONDS < deadline )); do
        health=$(docker inspect -f '{{.State.Health.Status}}' "$GLUETUN_CONTAINER" 2>/dev/null || echo "not found")
        if [[ "$health" == "healthy" ]]; then
            break
        fi
        sleep 2
    done
    echo
fi

# 1. Container running and healthy
health=$(docker inspect -f '{{.State.Health.Status}}' "$GLUETUN_CONTAINER" 2>/dev/null || true)
if [[ "$health" == "healthy" ]]; then
    result PASS "Gluetun container is running and healthy"
else
    result FAIL "Gluetun container is not healthy (status: ${health:-not found})"
    echo "Aborting remaining checks — fix Gluetun health first."
    exit 1
fi

# 2. Tunnel exit IP check (confirms egress via VPN, not host)
host_ip=$(curl -s --max-time 10 https://ifconfig.me || echo "unreachable")
tunnel_ip=$(docker exec "$GLUETUN_CONTAINER" wget -qO- --timeout=10 https://ifconfig.me 2>/dev/null || echo "unreachable")

if [[ "$tunnel_ip" == "unreachable" ]]; then
    result FAIL "Could not reach ifconfig.me from inside the tunnel"
elif [[ "$tunnel_ip" == "$host_ip" ]]; then
    result FAIL "Tunnel exit IP ($tunnel_ip) matches host IP — VPN is NOT tunneling traffic"
else
    result PASS "Tunnel exit IP ($tunnel_ip) differs from host IP ($host_ip)"
fi

# 3. DNS resolution through Gluetun's internal resolver
dns_test=$(docker exec "$GLUETUN_CONTAINER" nslookup cloudflare.com 127.0.0.1 2>&1 || true)
if echo "$dns_test" | grep -q "Address" && ! echo "$dns_test" | grep -qiE 'error|refused|timed out|can.t find'; then
    result PASS "DNS resolves correctly via Gluetun's internal resolver (127.0.0.1)"
else
    result FAIL "DNS resolution via Gluetun's internal resolver failed"
fi

# 4. resolv.conf nameserver sanity check
resolv_ns=$(docker exec "$GLUETUN_CONTAINER" cat /etc/resolv.conf 2>/dev/null | grep -m1 '^nameserver' || true)
if [[ "$resolv_ns" == "nameserver 127.0.0.1" ]]; then
    result PASS "resolv.conf points at Gluetun's internal resolver (127.0.0.1)"
else
    result FAIL "resolv.conf nameserver is unexpected: '${resolv_ns:-none found}'"
fi

# 5. IPv6 leak check — global IPv6 address should NOT be present inside the tunnel netns
ipv6_addrs=$(docker exec "$GLUETUN_CONTAINER" sh -c "ip -6 addr show scope global 2>/dev/null" || true)
if [[ -z "$ipv6_addrs" ]]; then
    result PASS "No global IPv6 address inside tunnel namespace (IPv6 leak surface closed)"
else
    result WARN "Global IPv6 address present inside tunnel namespace — check for IPv6 leak:"
    echo "$ipv6_addrs" | sed 's/^/       /'
fi

# 6. WebUI exposure — should be bound to 127.0.0.1 only, never 0.0.0.0
exposed=$(docker port "$GLUETUN_CONTAINER" 2>/dev/null | grep -v '127.0.0.1' || true)
if [[ -z "$exposed" ]]; then
    result PASS "All published ports are bound to 127.0.0.1 only (not exposed beyond localhost)"
else
    result FAIL "Some ports are published beyond 127.0.0.1:"
    echo "$exposed" | sed 's/^/       /'
fi

# 7. Optional: kill-switch test (disruptive — pauses Gluetun briefly)
if $RUN_KILLSWITCH_TEST; then
    echo
    echo "== Kill-switch test (pausing Gluetun for ~5s) =="
    docker pause "$GLUETUN_CONTAINER" >/dev/null
    GLUETUN_PAUSED=true
    sleep 2
    killswitch_result=$(timeout 5 docker exec "$QBIT_CONTAINER" wget -qO- --timeout=3 https://ifconfig.me 2>&1 || true)
    docker unpause "$GLUETUN_CONTAINER" >/dev/null
    GLUETUN_PAUSED=false

    if [[ -z "$killswitch_result" ]] || echo "$killswitch_result" | grep -qiE 'error|timed out|unreachable|killed'; then
        result PASS "qBittorrent traffic halts when tunnel drops (kill switch working)"
    else
        result FAIL "qBittorrent traffic still flowed with tunnel paused — kill switch NOT working"
    fi
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo -e "All checks passed. \033[32m✔\033[0m"
    exit 0
else
    echo -e "$FAILURES check(s) failed. \033[31m✘\033[0m"
    exit 1
fi
