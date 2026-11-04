#!/usr/bin/env bash
# Print comma-separated IPs for admin:whitelist:ip (stdout only).
set -euo pipefail

IPS=""

contains_ip() {
  local ip="$1"
  case ",${IPS}," in
    *,"${ip}",*) return 0 ;;
  esac
  return 1
}

add_ip() {
  local ip="${1:-}"
  ip="${ip// /}"
  [[ -z "$ip" ]] && return
  if contains_ip "$ip"; then
    return
  fi
  if [[ -n "$IPS" ]]; then
    IPS="${IPS},${ip}"
  else
    IPS="$ip"
  fi
}

# Loopback
add_ip "127.0.0.1"

# Docker host-gateway IPs often seen as client address from OpenResty
add_ip "172.17.0.1"
add_ip "192.168.65.1"

if [[ "$(uname -s)" == "Darwin" ]]; then
  for iface in en0 en1 en2; do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    add_ip "$ip"
  done
else
  if command -v ip >/dev/null 2>&1; then
    while read -r ip; do
      add_ip "$ip"
    done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1); exit}')"
    add_ip "$ip"
  fi
  if command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    add_ip "$ip"
  fi
fi

if [[ -n "${ADMIN_WHITELIST_IP_EXTRA:-}" ]]; then
  IFS=',' read -r -a extras <<< "$ADMIN_WHITELIST_IP_EXTRA"
  for ip in "${extras[@]}"; do
    add_ip "$ip"
  done
fi

echo "${IPS:-127.0.0.1}"
