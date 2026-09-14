#!/usr/bin/env bash
# Simulate a monitoring tool posting to an AAP 2.6 Event Stream.
#
#   Netcool   : ./send_test_event.sh netcool   <event-stream-url> <token>             [host] [path] [incident]
#   Dynatrace : ./send_test_event.sh dynatrace <event-stream-url> <user:password>     [host] [path]
#   Resolution: ./send_test_event.sh netcool-clear <event-stream-url> <token>         (should be ignored)
#
# Copy the event stream URL from Automation Decisions > Event Streams.
# Add -k to CURL_OPTS for a lab gateway with a self-signed certificate:  CURL_OPTS=-k ./send_test_event.sh ...
set -euo pipefail

kind=${1:?netcool | dynatrace | netcool-clear}
url=${2:?event stream URL}
secret=${3:?token (netcool) or user:password (dynatrace)}
host=${4:-}
path=${5:-}
incident=${6:-}
here=$(cd "$(dirname "$0")" && pwd)

case "$kind" in
  netcool)       file="$here/payloads/netcool_filesystem_alert.json" ;;
  netcool-clear) file="$here/payloads/netcool_resolution_ignored.json" ;;
  dynatrace)     file="$here/payloads/dynatrace_low_disk_problem.json" ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

payload=$(cat "$file")
# Optional overrides so the same payload can target any lab host/path.
if [[ -n "$host" ]]; then
  payload=$(printf '%s' "$payload" | sed -e "s/node01\(\.lab\.example\.com\)\{0,1\}/$host/g")
fi
if [[ -n "$path" ]]; then
  payload=$(printf '%s' "$payload" | sed -e "s#\"/var\"#\"$path\"#g" -e "s#system /var #system $path #g" -e "s#:/var:#:$path:#g")
fi
if [[ -n "$incident" ]]; then
  payload=$(printf '%s' "$payload" | sed -e "s/INC0010042/$incident/g")
fi

if [[ "$kind" == dynatrace ]]; then
  auth=(-u "$secret")
else
  auth=(-H "X-Event-Token: $secret")
fi

echo "POST $kind event to $url"
curl ${CURL_OPTS:-} -sS -w '\nHTTP %{http_code}\n' -X POST "$url" \
  -H 'Content-Type: application/json' "${auth[@]}" --data "$payload"
