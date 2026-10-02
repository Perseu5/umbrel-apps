# Luma gets its own LAN address on a macvlan network (umbreld owns ports 80 and
# 443 on this device). Derive that network from the interface holding the
# default route, on every start, so it follows the device's current network.
luma_default_route="$(ip -4 route show default 2>/dev/null | head -n 1 || true)"
luma_lan_parent="$(awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}' <<< "${luma_default_route}")"
luma_lan_gateway="$(awk '{for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit }}' <<< "${luma_default_route}")"
luma_lan_cidr=""
if [[ -n "${luma_lan_parent}" ]]; then
  luma_lan_cidr="$(ip -4 -o addr show dev "${luma_lan_parent}" scope global 2>/dev/null | awk '{print $4; exit}' || true)"
fi
luma_lan_subnet="192.0.2.0/24"
luma_host_ip=""
if [[ "${luma_lan_cidr}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/([0-9]+)$ ]]; then
  luma_host_ip="${luma_lan_cidr%/*}"
  luma_prefix="${BASH_REMATCH[5]}"
  luma_address=$(( (BASH_REMATCH[1] << 24) | (BASH_REMATCH[2] << 16) | (BASH_REMATCH[3] << 8) | BASH_REMATCH[4] ))
  luma_network=$(( luma_address & ((0xFFFFFFFF << (32 - luma_prefix)) & 0xFFFFFFFF) ))
  luma_lan_subnet="$(( (luma_network >> 24) & 255 )).$(( (luma_network >> 16) & 255 )).$(( (luma_network >> 8) & 255 )).$(( luma_network & 255 ))/${luma_prefix}"
fi
export APP_LUMA_LAN_PARENT="${luma_lan_parent:-eth0}"
export APP_LUMA_LAN_GATEWAY="${luma_lan_gateway:-192.0.2.1}"
export APP_LUMA_LAN_SUBNET="${luma_lan_subnet}"
export APP_LUMA_HOST_IP="${luma_host_ip}"

# Luma's own configuration, written by the setup page with `luma setup
# production`. It is read line by line, never sourced: values are Compose
# env-file values (KEYCLOAK_SCOPES holds unquoted spaces). Only once setup has
# finished does the `luma` profile, and with it the whole stack, turn on.
luma_env_file="${EXPORTS_APP_DATA_DIR}/config/secrets/runtime.env"
if [[ -r "${luma_env_file}" && -f "${EXPORTS_APP_DATA_DIR}/umbrel/setup-complete.json" ]]; then
  while IFS= read -r luma_line || [[ -n "${luma_line}" ]]; do
    [[ "${luma_line}" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
    case "${BASH_REMATCH[1]}" in
      COMPOSE_*|APP_*|DEVICE_*|UMBREL_*|EXPORTS_*|NETWORK_IP|TOR_*|PATH|HOME) continue ;;
    esac
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
  done < "${luma_env_file}"
  export COMPOSE_PROFILES="luma"
fi
# Parse-time placeholders before setup; nothing uses them until the profile is on.
export LUMA_RELEASE_ID="${LUMA_RELEASE_ID:-not-set-up}"
export LUMA_DEVICE_EDGE_IPV4="${LUMA_DEVICE_EDGE_IPV4:-192.0.2.10}"
