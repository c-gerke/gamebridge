#!/usr/bin/env bash
# Test suite for install.sh
# Runs entirely in --dry-run mode — no root or real hardware needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL="$REPO_DIR/install.sh"
FIXTURES="$SCRIPT_DIR"

PASS=0
FAIL=0
TESTS_RUN=0

# ---------- helpers ----------

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local name="$1"
    shift
    if "$@"; then
        PASS=$((PASS + 1))
        echo "  PASS  $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL  $name"
    fi
}

assert_exit_code() {
    local expected="$1"
    shift
    local actual
    set +e
    "$@" > /dev/null 2>&1
    actual=$?
    set -e
    [[ "$actual" -eq "$expected" ]]
}

assert_output_contains() {
    local pattern="$1"
    shift
    local output
    set +e
    output=$("$@" 2>&1)
    set -e
    echo "$output" | grep -qF "$pattern"
}

# ---------- argument handling tests ----------

echo "=== Argument handling ==="

run_test "--help exits 0" \
    assert_exit_code 0 bash "$INSTALL" --help

run_test "--help shows usage" \
    assert_output_contains "Usage:" bash "$INSTALL" --help

run_test "no args exits non-zero" \
    assert_exit_code 1 bash "$INSTALL"

run_test "no args shows error about config" \
    assert_output_contains "Config file is required" bash "$INSTALL"

run_test "missing config file exits non-zero" \
    assert_exit_code 1 bash "$INSTALL" -c /nonexistent/file.yaml --dry-run

run_test "missing config file shows error" \
    assert_output_contains "Config file not found" bash "$INSTALL" -c /nonexistent/file.yaml --dry-run

run_test "unknown option exits non-zero" \
    assert_exit_code 1 bash "$INSTALL" --bogus

# ---------- config validation tests ----------

echo ""
echo "=== Config validation ==="

run_test "missing vlans field is caught" \
    assert_output_contains "Missing required key: vlans" \
    bash "$INSTALL" -c "$FIXTURES/missing_vlans.yaml" --dry-run

run_test "missing management sub-field is caught" \
    assert_output_contains "Missing required key: management.netmask" \
    bash "$INSTALL" -c "$FIXTURES/missing_mgmt_field.yaml" --dry-run

run_test "bridge defaults to br0 when omitted" \
    assert_output_contains "br0" \
    bash "$INSTALL" -c "$FIXTURES/no_bridge_field.yaml" --dry-run

# ---------- YAML dry-run output tests ----------

echo ""
echo "=== YAML dry-run output ==="

YAML_OUTPUT=$(bash "$INSTALL" -c "$FIXTURES/minimal.yaml" --dry-run 2>&1)

check_yaml_output() {
    echo "$YAML_OUTPUT" | grep -qF "$1"
}

run_test "YAML: management interface present" \
    check_yaml_output "auto eth0"

run_test "YAML: management IP configured" \
    check_yaml_output "address 192.168.1.10"

run_test "YAML: management netmask configured" \
    check_yaml_output "netmask 255.255.255.0"

run_test "YAML: management gateway configured" \
    check_yaml_output "gateway 192.168.1.1"

run_test "YAML: VLAN 10 interface created" \
    check_yaml_output "auto eth1.10"

run_test "YAML: VLAN 20 interface created" \
    check_yaml_output "auto eth1.20"

run_test "YAML: VLAN 30 interface created" \
    check_yaml_output "auto eth1.30"

run_test "YAML: VLAN interfaces set to manual" \
    check_yaml_output "iface eth1.10 inet manual"

run_test "YAML: bridge_ports lists all VLANs" \
    check_yaml_output "bridge_ports eth1.10 eth1.20 eth1.30"

run_test "YAML: ebtables default DROP policy" \
    check_yaml_output "ebtables -P FORWARD DROP"

run_test "YAML: ebtables flush FORWARD" \
    check_yaml_output "ebtables -F FORWARD"

run_test "YAML: ebtables rule for port 27014:27025" \
    check_yaml_output "ip-destination-port 27014:27025 -j ACCEPT"

run_test "YAML: ebtables rule for port 7777:7777" \
    check_yaml_output "ip-destination-port 7777:7777 -j ACCEPT"

run_test "YAML: bridge ifup in rc.local" \
    check_yaml_output "ifup br0"

run_test "YAML: SNAT MAC rewrite in rc.local" \
    check_yaml_output "/sys/class/net/br0/address"

run_test "YAML: rc.local shebang" \
    check_yaml_output "#!/bin/sh -e"

run_test "YAML: DRY RUN banner shown" \
    check_yaml_output "DRY RUN"

# ---------- non-YAML file rejected ----------

echo ""
echo "=== File extension validation ==="

# Create a temp .json file to verify it's rejected
TEMP_JSON=$(mktemp --suffix=.json)
echo '{}' > "$TEMP_JSON"

run_test "non-YAML extension is rejected" \
    assert_exit_code 1 bash "$INSTALL" -c "$TEMP_JSON" --dry-run

run_test "non-YAML error message is clear" \
    assert_output_contains "must be YAML" bash "$INSTALL" -c "$TEMP_JSON" --dry-run

rm -f "$TEMP_JSON"

# ---------- full example config test ----------

echo ""
echo "=== Full example config ==="

run_test "example config parses without error" \
    assert_exit_code 0 bash "$INSTALL" -c "$REPO_DIR/gamebridge.conf.example.yaml" --dry-run

FULL_OUTPUT=$(bash "$INSTALL" -c "$REPO_DIR/gamebridge.conf.example.yaml" --dry-run 2>&1)

check_full_output() {
    echo "$FULL_OUTPUT" | grep -qF "$1"
}

count_vlan_interfaces() {
    local count
    count=$(echo "$FULL_OUTPUT" | grep -c "^auto ens224\." 2>/dev/null || true)
    [[ "$count" -eq 36 ]]
}

count_ebtables_rules() {
    local count
    count=$(echo "$FULL_OUTPUT" | grep -c "ip-destination-port" 2>/dev/null || true)
    [[ "$count" -eq 45 ]]
}

run_test "example: all 36 VLAN interfaces created" \
    count_vlan_interfaces

run_test "example: all 45 ebtables port rules created" \
    count_ebtables_rules

run_test "example: management interface is ens192" \
    check_full_output "auto ens192"

run_test "example: trunk interface is ens224" \
    check_full_output "auto ens224.10"

# ---------- summary ----------

echo ""
echo "==============================="
echo "  $TESTS_RUN tests: $PASS passed, $FAIL failed"
echo "==============================="

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
