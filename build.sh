#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
# copyright 2023 <github.attic@typedef.net>, CC BY 4.0

declare -A C=(
  # Container runtime: some "docker lookalike" OCI runtime
  [crt]='podman'
  #[crt]='docker'

  # Version of the Containerfile and build.sh script
  [containerversion]='0.6'
)

command -v npm >&- || npm() {
  "${C[crt]}" run --rm node:current-alpine npm "${@}"
}

currentnpmversion() { npm view "${1:?}" version; }

PAYLOADVERSION="$(currentnpmversion opencode-ai)"
#PAYLOADVERSION='1.4.6'     # some fixed version if need be
ARGV+=( '--build-arg' "PAYLOADVERSION=${PAYLOADVERSION}" )

IMAGE='opencode'
TAGS=( "${C[containerversion]}-oc${PAYLOADVERSION:?}" 'latest' )

[ -n "${IMAGE}" ] && {
  for TAG in "${TAGS[@]:-latest}"; do
    ARGV+=( '-t' "${IMAGE}:${TAG}" )
  done
}

# non OCI compliant image format stuff
#ARGV+=( '--format' 'docker' )

"${C[crt]}" build ${ARGV:+"${ARGV[@]}"} "${@}" "${0%/*}"

