#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
#
# copyright 2025 <github.attic@typedef.net>, CC BY 4.0
#
# This is just a wrapper script for the containerized opencode cli.
#
# Remark: This wrapper was build an tested using podman as container
#  runtime.  It should work just fine with other "docker lookalike"
#  runtimes, like e.g. docker.  See $C[crt] configuration below.
#  The comments in this script always refer to podman however.
#
# Usage: ${IAM} [SOURCE-VOLUME|HOST-DIR[:OPTIONS]...] [OPENCODE-ARGV...]
#
# Leading `podman run --volume` "mount specification like" arguments are
# parsed and mounted into the containers `WORKDIR`, further arguments
# are passed through to the payload executable (opencode) verbatim.
#
# Examples:
#
# * Mount `~/projects/thisone` and `~/projects/anotherone` into the
#  containers `$PWD/thisone` and `$PWD/anotherone`:
#
#    ${IAM} ~/projects/thisone ~/projects/anotherone
#
# * Special case: same as before, but in addition mount the current $PWD
#  directly into the containers $PWD:
#
#    ${IAM} ~/projects/thisone ~/projects/anotherone .
#
# * Mount the current $PWD and some file directly into the containers
#  $PWD and pass some arguments to the payload executable:
#
#    cd ~/projects/thatone
#    ${IAM} . ~/some/additional/file:ro run 'explain this codebase'

#set -vx; set -o functrace

IAM="${0##*/}"; REALPWD="$(realpath -e "${PWD}")"

declare -A C=(
  # Some configuration knobs to twiddle with for the inclined

  # Container runtime: This wrapper was build an tested using podman
  # (https://github.com/containers/podman) as (high-level) container
  # runtime, but should run just fine with other "docker lookalike"
  # OCI runtimes, like e.g. docker (https://github.com/docker).
  # Default is 'podman'.
  [crt]='podman'
  #[crt]='docker'

  # The name prefix for containers and volumes: containers running with
  # the same name prefix share their runtime volumes.
  # The default name prefix is derived from the basename of this script.
  [name]="${IAM%.sh}"

  # Use host opencode configuration: if set to 'ro', 'rw', or 'O' and
  # $XDG_CONFIG_HOME/opencode exists on the host, mount it into the
  # container with the selected `--volume` option.  'O' is podman's
  # overlay mount mode: host files are visible and container writes
  # succeed, but changes are discarded with the container.
  # Note: 'O' is podman-specific; use 'ro' or 'rw' with docker.
  # Any other value (like e.g. 'volume') uses isolated configuration in
  # the $C[name]-config volume.
  # Default is 'O', use host configuration without modifying it.
  [use_xdg_config_home/opencode]='O'

  # Use host opencode auth.json: if set to 'ro' or 'rw' and
  # $XDG_DATA_HOME/opencode/auth.json exists on the host, mount it into
  # the container with the selected `--volume` option.
  # Any other value (like e.g. 'volume') uses an isolated auth.json in
  # the $C[name]-share volume.
  # Default is 'rw', use host auth.json read/write.
  [use_xdg_data_home/opencode/auth.json]='rw'

  # Use host vim configuration: if 'true' and some vim configuration can
  # be found on the host, mount it read-only into the container.
  [use_vim_configuration]='true'
)

# XDG base directories reminder
XDG_DATA_HOME="${XDG_DATA_HOME:-"${HOME}/.local/share"}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"${HOME}/.config"}"

vspec() {
  # $*: VSPEC associative arrays.  Print the "default" fields of each VSPEC
  # array in podman-run(1) `--volume` argument format to stdout.

  local ARGV; for ARGV in "${@}"; do
    declare -n ARRAY="${ARGV}"

    printf '%s:%s%s' \
      "${ARRAY[source-volorpath]:?}" \
      "${ARRAY[container-dir]:?}" \
      "${ARRAY[options]}"
  done
}

volume_exists() {
  # $1: volume name.  Return 0 if the volume $1 exists or 1 otherwise.
  # This is a cross container runtime version of `podman volume exists`.

  "${C[crt]}" volume inspect "${1:?}" >/dev/null 2>&1
}

parse_volumespec() {
  # Check if $1 is a podman-run(1) `--volume` "mount specification like
  # thing"; if so, return the `--volume` argument for this mount.
  #
  # Mount the desired volume or path into sub-directories of the
  # container `WORKDIR`; in case the desired path is $PWD or a file,
  # mount directly into the container `WORKDIR` instead.

  [[ -n "${1}" ]] || return 1

  declare -A VSPEC=(
    # everything up to the last `:` is considered a volume or a directory
    [volorpath]="${1%:*}"

    # everything after the last `:` are mount options
    [options]="$([[ "${1##*:}" != "${1}" ]] && echo ":${1##*:}")"

    [source-volorpath]=''

    # the container `WORKDIR` (i.e. payload $PWD)
    [container-dir]='/stage'
  )

  # check if $volorpath is a podman volume or a path
  if volume_exists "${VSPEC[volorpath]}"; then
    # this is a podman volume
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    VSPEC[container-dir]+="/${VSPEC[volorpath]}"

  elif [[ -d "${VSPEC[volorpath]}" || -f "${VSPEC[volorpath]}" ]]; then
    # this is a directory or a file
    VSPEC[volorpath]="$(realpath -e "${VSPEC[volorpath]}")"
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    # the "path is $PWD" exception
    [[ "${VSPEC[volorpath]}" != "${REALPWD}" ]] &&
      VSPEC[container-dir]+="/${VSPEC[volorpath]##*/}"

  else
    # it's neither a volume nor a directory or file
    return 1
  fi

  vspec VSPEC
}

# check positional parameters for podman-run(1) `--volume` "mount
# specification like things", prepare the `--volume` options
declare -a PMARGS_PRJVOLUMES
while [[ "${#}" -gt '0' && "${1:0:1}" != '-' ]]; do
  VOLUMESPEC="$(parse_volumespec "${1}")" || break
  PMARGS_PRJVOLUMES+=( '--volume' "${VOLUMESPEC}" )
shift; done

if (( ${#PMARGS_PRJVOLUMES[@]} )); then
  # show what will be mounted
  echo "${IAM}: [notice] will mount:" >&2
  for i in "${PMARGS_PRJVOLUMES[@]/#${HOME}/'~'}"; do
    [[ "${i}" != '--volume' ]] && echo "  ${i}"
  done |sort -t: -k1dr >&2
else
  # no plan to mount something in(to) the containers `WORKDIR`?
  echo "${IAM}: [warning] no persistent project directory mount given" >&2
fi


PMARGS_VOLUMES=(
  # opencode runtime data
  '--volume' "${C[name]}-share:/root/.local/share/opencode"
  '--volume' "${C[name]}-state:/root/.local/state/opencode"
  '--volume' "${C[name]}-cache:/root/.cache/opencode"
  '--volume' "${C[name]}-bun:/root/.bun"
)

# opencode configuration: use a dedicated volume or mount an existing
# $XDG_CONFIG_HOME/opencode configuration into the container
declare -A VSPEC=(
  [source-volorpath]="${C[name]}-config"
  [container-dir]='/root/.config/opencode'
)

[[ "${C[use_xdg_config_home/opencode]}" =~ ^(ro|rw|O)$ ]] && {
  [[ -d "${XDG_CONFIG_HOME}/opencode" ]] && {
    VSPEC[source-volorpath]="${XDG_CONFIG_HOME}/opencode"
    VSPEC[options]=":${BASH_REMATCH[0]}"
  }
}

PMARGS_VOLUMES+=( '--volume' "$(vspec VSPEC)" )

# opencode auth.json: if $XDG_DATA_HOME/opencode/auth.json exists,
# mount it into the container
[[ "${C[use_xdg_data_home/opencode/auth.json]}" =~ ^(ro|rw)$ ]] && {
  [[ -r "${XDG_DATA_HOME}/opencode/auth.json" ]] && {
    declare -A VSPEC=(
      [source-volorpath]="${XDG_DATA_HOME}/opencode/auth.json"
      [container-dir]='/root/.local/share/opencode/auth.json'
      [options]=":${BASH_REMATCH[0]}"
    )
    PMARGS_VOLUMES+=( '--volume' "$(vspec VSPEC)" )
  }
}

# vim configuration: if some vim configuration can be found, mount it
# into the container
[[ "${C[use_vim_configuration]}" = 'true' ]] && {
  [[ -f "${HOME}/.vimrc" ]] &&
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vimrc:/root/.vimrc:ro" )

  if [[ -d "${HOME}/.vim" ]]; then
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vim:/root/.vim:ro" )
  else
    [[ -d "${XDG_CONFIG_HOME}/vim" ]] &&
      PMARGS_VOLUMES+=( '--volume' "${XDG_CONFIG_HOME}/vim:/root/.vim:ro" )
  fi
}

PMARGV=(
  '--name' "${C[name]}-${SRANDOM}"
  '--interactive' '--tty' '--rm'
  '--network=host'
  ${PMARGS_VOLUMES:+"${PMARGS_VOLUMES[@]}"}
  ${PMARGS_PRJVOLUMES:+"${PMARGS_PRJVOLUMES[@]}"}
)

#echo '# debug:' "${C[crt]}" run "${PMARGV[@]}" opencode "${@}" >&2
"${C[crt]}" run "${PMARGV[@]}" opencode "${@}"
