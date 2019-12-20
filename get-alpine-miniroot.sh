#!/bin/bash
#set +x

arch="x86_64" # or x86, armhf, aarch64, ppc64le, s390x, armv7
miniroot_url=""
dl_filename=""
server_ip=""
filehash=""
dl_filehash=""
query_answer=""

readonly CONNECT_TIMEOUT=5

on_error() {
  printf "[ $(date +'%Y-%m-%dT%H:%M:%S')]: %s\n" "$@" >&2
}

check_http_srv() {
  local url
  local extargs
  local opt
  local OPTARG=""
  local OPTIND=
  declare -a extargs
  while getopts "u:x:" opt; do
    case "$opt" in
      u)  url="$OPTARG"  ;;
      x)  extargs+=("$OPTARG") ;;
    esac
  done
  shift $((OPTIND - 1))

  echo "url: $url"
  echo "extargs: ${extargs[@]}"
  curl -s --connect-timeout $CONNECT_TIMEOUT -I ${extargs[@]} "$url"
}

match() {
  local string
  local regex
  local opt
  local is_remote=0
  local OPTARG=""
  local OPTIND=

  while getopts "Rs:r:" opt; do
    case $opt in
      R) is_remote=1 ;;
      s) string="$OPTARG" ;;
      r) regex="$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))

  set -x
  if [[ "$is_remote" -eq 1 ]]; then
    set +x
    string=$(curl --connect-timeout $CONNECT_TIMEOUT -s "$string")
  fi

  if [[ "$string" =~ $regex ]]; then
    return 0
  else
    return 1
  fi
}

main() {
  local alpine_url="https://alpinelinux.org/downloads/"
  local version_string_regex="<p>Current Alpine Version <strong>([0-9]+).([0-9]+).([0-9]+)</strong>"
  local ipv4_digit_regex="([[:digit:]]{1,3}\.)+[[:digit:]]{1,3}"
  local sha256hash_regex="[0-9a-z]{64}"
  local domain_name="dl-cdn.alpinelinux.org"
  local common_name="default.ssl.fastly.net"
  local save_dir="./files"
  local arch="$arch"
  local BASH_REMATCH=

  local major
  local minor
  local build
  local dns_answer
  local remote_file_hash
  local local_file_hash

  # Determine current alpine version
  if ! check_http_srv -u "$alpine_url" >/dev/null; then
    on_error "Connection error to ${alpine_url}"
    exit 2
  fi

  if ! match -R -s "$alpine_url" -r "$version_string_regex"; then
    on_error "Unable to find version string"
    exit 3
  else
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    build="${BASH_REMATCH[3]}"
  fi

  # Download minirootfs
  ## determine server IP
  dns_answer=$(dig +short "$domain_name")
  echo "dns_answer:${dns_answer}"
  echo "regex:${ipv4_digit_regex}"
  if ! match -s "$dns_answer" -r "$ipv4_digit_regex"; then
    on_error "Can not resolve ${domain_name}"
    exit 4
  else
    server_ip="${BASH_REMATCH[0]}"
  fi

  ## Check file hash
  ### check server connectivity
  if ! check_http_srv -x "--resolve ${common_name}:443:${server_ip}" -x "Host:${domain_name}" -u "https://${common_name}/alpine/v${major}.${minor}/releases/${arch}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz.sha256" >/dev/null; then
    on_error "Connection error to https://${domain_name}"
    exit 5
  fi

  ### read published file hash
  remote_file_hash=$(curl --resolve "${common_name}:443:${server_ip}" -H "Host:${domain_name}" "https://${common_name}/alpine/v${major}.${minor}/releases/${arch}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz.sha256")
  if ! match -s "$remote_file_hash" -r "$sha256hash_regex"; then
    on_error "Can not read remote file hash"
    exit 6
  else
    remote_file_hash="${BASH_REMATCH[0]}"
  fi

  ### check if you already have current minirootfs file in local
  if [[ -f "${save_dir}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz" ]]; then
    local_file_hash=$(sha256sum "${save_dir}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz")
    if [[ "$remote_file_hash" -eq "$local_file_hash" ]]; then
      break # no need to download
    else # download
     curl --resolve "${common_name}:443:${server_ip}" -H "Host:${domain_name}" "https://${common_name}/alpine/v${major}.${minor}/releases/${arch}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz" -o "${save_dir}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz"
    fi
    #printf "File alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz exists\n"
  else #download
    curl --resolve "${common_name}:443:${server_ip}" -H "Host:${domain_name}" "https://${common_name}/alpine/v${major}.${minor}/releases/${arch}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz" -o "${save_dir}/alpine-minirootfs-${major}.${minor}.${build}-${arch}.tar.gz"
  fi
}

main
