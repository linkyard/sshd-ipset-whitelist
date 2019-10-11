#!/bin/bash
set -e

apply_ipset() {
  local ipsetName="${1}"
  local ipsetKind="${2}"
  local ipsetFamily="${3}"
  local ipsetSource="${4}"

  local targetSet="${ipsetName}"
  if [ "$(ipset list -n | grep --count "${ipsetName}")" -eq 1 ]; then    
    targetSet="tmp_${ipsetName}"
    echo "using temporary set ${targetSet}"
  fi
  set -x
  ipset create "${targetSet}" "${ipsetKind}" family "${ipsetFamily}"
  { set +x; } 2>/dev/null

  if [ -r "${ipsetSource}" ]; then
    echo "reading contents of ${ipsetName} from file ${ipsetSource}"
    while IFS= read -r ip; do ipset -A "${targetSet}" "$ip"; done < "${ipsetSource}"
  else 
    echo "reading contents of ${ipsetName} from variable"
    for ip in ${ipsetSource}; do ipset -A "${targetSet}" "$ip"; done
  fi

  if [ "${ipsetName}" != "${targetSet}" ]; then
    echo "swapping temporary set ${targetSet} and ${ipsetName}"
    set -x
    ipset swap "${targetSet}" "${ipsetName}"
    ipset destroy "${targetSet}"
    { set +x; } 2>/dev/null
  fi
}

remove_ipset() {
  if [ "$(ipset list -n | grep --count "${1}")" -eq 1 ]; then  
    set -x
    ipset destroy "${1}"
    { set +x; } 2>/dev/null
  fi
}

apply_iptables() {
  local ipsetName="${1}"
  local family="${2}"

  _IPTABLES="iptables"
  if [ "${family}" = "inet6" ]; then
    _IPTABLES="ip6tables"
  fi

  set +e
  if [ "$(${_IPTABLES} -n -L INPUT | grep ACCEPT | grep --count "ctstate RELATED,ESTABLISHED$")" -eq 0 ]; then
    set -x
    ${_IPTABLES} -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    { set +x; } 2>/dev/null
  fi
  set -e

  if [ "$(${_IPTABLES} -n -L INPUT | grep match-set | grep --count "${ipsetName}")" -eq 0 ]; then
    local dropRule
    set +e
    dropRule=$(${_IPTABLES} -n -L INPUT --line-numbers | grep DROP | grep "tcp dpt:22$")
    set -e

    if [ -z "${dropRule}" ]; then
      set -x
      ${_IPTABLES} -A INPUT -p tcp -m set --dport 22 --match-set "${ipsetName}" src -j ACCEPT
      ${_IPTABLES} -A INPUT -p tcp --dport 22 -j DROP
      { set +x; } 2>/dev/null
    else
      local lineNumber
      lineNumber="$(echo "${dropRule}" | awk '{print $1}')"
      set -x
      ${_IPTABLES} -I INPUT "${lineNumber}" -p tcp -m set --dport 22 --match-set "${ipsetName}" src -j ACCEPT
      { set +x; } 2>/dev/null
    fi

  fi
}

remove_iptables() {
  local ipsetName="${1}"
  local family="${2}"

  _IPTABLES="iptables"
  if [ "${family}" = "inet6" ]; then
    _IPTABLES="ip6tables"
  fi

  local rule
  set +e
  rule=$(${_IPTABLES} -n -L INPUT --line-numbers | grep ACCEPT | grep "match-set" | grep "src tcp dpt:22$" | grep "${ipsetName}")
  if [ -n "${rule}" ]; then
    set -x
    ${_IPTABLES} -D INPUT -p tcp -m set --dport 22 --match-set "${ipsetName}" src -j ACCEPT
    { set +x; } 2>/dev/null
  fi
  set -e
}

if [ -n "${WHITELISTED_IPV4_IPS}" ]; then
  apply_ipset "sshd-whitelist-ipv4-ips" "hash:ip" "inet" "${WHITELISTED_IPV4_IPS}"
  apply_iptables "sshd-whitelist-ipv4-ips" "inet"
else
  remove_iptables "sshd-whitelist-ipv4-ips" "inet"
  remove_ipset "sshd-whitelist-ipv4-ips"
fi

if [ -n "${WHITELISTED_IPV4_NETS}" ]; then
  apply_ipset "sshd-whitelist-ipv4-nets" "hash:net" "inet" "${WHITELISTED_IPV4_NETS}"
  apply_iptables "sshd-whitelist-ipv4-nets" "inet"
else
  remove_iptables "sshd-whitelist-ipv4-nets" "inet"
  remove_ipset "sshd-whitelist-ipv4-nets"
fi

if [ -n "${WHITELISTED_IPV6_IPS}" ]; then
  apply_ipset "sshd-whitelist-ipv6-ips" "hash:ip" "inet6" "${WHITELISTED_IPV6_IPS}"
  apply_iptables "sshd-whitelist-ipv6-ips" "inet6"
else
  remove_iptables "sshd-whitelist-ipv6-ips" "inet6"
  remove_ipset "sshd-whitelist-ipv6-ips"
fi

if [ -n "${WHITELISTED_IPV6_NETS}" ]; then
  apply_ipset "sshd-whitelist-ipv6-nets" "hash:net" "inet6" "${WHITELISTED_IPV6_NETS}"
  apply_iptables "sshd-whitelist-ipv6-nets" "inet6"
else
  remove_iptables "sshd-whitelist-ipv6-nets" "inet6"
  remove_ipset "sshd-whitelist-ipv6-nets"
fi

if [ -n "${WHITELISTED_COUNTRIES}" ]; then
  set +e
  existingSets="$(ipset -n list | grep "sshd-country-")"
  set -e
  for country in ${WHITELISTED_COUNTRIES}; do
    tmpFile=$(mktemp)
    set -x
    curl -sL "http://www.ipdeny.com/ipblocks/data/aggregated/${country}-aggregated.zone" -o "${tmpFile}"
    { set +x; } 2>/dev/null
    apply_ipset "sshd-country-ipv4-${country}" "hash:net" "inet" "${tmpFile}"
    apply_iptables "sshd-country-ipv4-${country}" "inet"
    rm "${tmpFile}"

    tmpFile=$(mktemp)
    set -x
    curl -sL "http://www.ipdeny.com/ipv6/ipaddresses/aggregated/${country}-aggregated.zone" -o "${tmpFile}"
    { set +x; } 2>/dev/null
    apply_ipset "sshd-country-ipv6-${country}" "hash:net" "inet6" "${tmpFile}"
    apply_iptables "sshd-country-ipv6-${country}" "inet6"
    rm "${tmpFile}"
  done
  for set in ${existingSets}; do
    found="false"
    for country in ${WHITELISTED_COUNTRIES}; do
      if [ "${set}" = "sshd-country-ipv6-${country}" ] || [ "${set}" = "sshd-country-ipv4-${country}" ]; then
        found="true"
        break
      fi
    done
    if [ "${found}" = "false" ]; then
      family="inet"
      if [ "$(echo "${set}" | grep -c "ipv6")" -eq 1 ]; then
        family="inet6"
      fi
      remove_iptables "${set}" "${family}"
      remove_ipset "${set}"
    fi
  done
else
  ipSets="$(ipset -n list | grep "sshd-country-")"
  for set in ${ipSets}; do
    family="inet"
    if [ "$(echo "${set}" | grep -c "ipv6")" -eq 1 ]; then
      family="inet6"
    fi
    remove_iptables "${set}" "${family}"
    remove_ipset "${set}"
  done
fi
