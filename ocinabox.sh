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
  # the same name prefix share their runtime volumes.  The default name
  # prefix is derived from the basename of this script.
  [name]="${IAM%.sh}"

  # Use host configuration: if 'true' and $XDG_CONFIG_HOME/opencode
  # exists on the host, use it in the container.  If 'false', use
  # isolated configuration in the $C[name]-config volume.
  # Default is 'true', use host configuration.
  [use_xdg_config_home/opencode]='true'

  # Use host auth.json: if 'true' and $XDG_DATA_HOME/opencode/auth.json
  # exists on the host, use it in the container.  If 'false', use an
  # isolated auth.json in the $C[name]-share volume.
  # Default is 'true', use host auth.json.
  [use_xdg_data_home/opencode/auth.json]='true'

  # Use host vim configuration: if 'true' and some vim configuration can
  # be found on the host, use it in the container.
  [use_vim_configuration]='true'
)

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
    [conatainer-dir]='/stage'
  )

  # check if $volorpath is a podman volume or a path
  if "${C[crt]}" volume exists "${VSPEC[volorpath]}"; then
    # this is a podman volume
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    VSPEC[conatainer-dir]+="/${VSPEC[volorpath]}"

  elif [[ -d "${VSPEC[volorpath]}" || -f "${VSPEC[volorpath]}" ]]; then
    # this is a directory or a file
    VSPEC[volorpath]="$(realpath -e "${VSPEC[volorpath]}")"
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    # the "path is $PWD" exception
    [[ "${VSPEC[volorpath]}" != "${REALPWD}" ]] &&
      VSPEC[conatainer-dir]+="/${VSPEC[volorpath]##*/}"

  else
    # it's neither a volume nor a directory or file
    return 1
  fi

  printf '%s:%s%s' \
    "${VSPEC[source-volorpath]}" \
    "${VSPEC[conatainer-dir]}" \
    "${VSPEC[options]}"
}

# check positional parameters for podman-run(1) `--volume` "mount
# specification like things", prepare the `--volume` options
declare -a PMARGS_PRJVOLUMES
while [[ "${#}" -gt '0' && "${1:0:1}" != '-' ]]; do
  VOLUMESPEC="$(parse_volumespec "${1}")" || break
  PMARGS_PRJVOLUMES+=( '--volume' "${VOLUMESPEC}" )
shift; done

if [[ -n "${PMARGS_PRJVOLUMES}" ]]; then
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
  [conatainer-dir]='/root/.config/opencode'
)

[[ "${C[use_xdg_config_home/opencode]}" = 'true' ]] && {
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"${HOME}/.config"}"

  [ -d "${XDG_CONFIG_HOME}/opencode" ] && {
    VSPEC[source-volorpath]="${XDG_CONFIG_HOME}/opencode"
    VSPEC[options]=':ro'
  }
}

printf -v VOLUMESPEC '%s:%s%s' \
  "${VSPEC[source-volorpath]}" \
  "${VSPEC[conatainer-dir]}" \
  "${VSPEC[options]}"

PMARGS_VOLUMES+=( '--volume' "${VOLUMESPEC}" )

# opencode auth.json: if $XDG_DATA_HOME/opencode/auth.json exists,
# mount it into the container
[[ "${C[use_xdg_data_home/opencode/auth.json]}" = 'true' ]] && {
  XDG_DATA_HOME="${XDG_DATA_HOME:-"${HOME}/.local/share"}"

  AUTHJSON="${XDG_DATA_HOME}/opencode/auth.json"
  [ -r "${AUTHJSON}" ] && PMARGS_VOLUMES+=(
    #'--volume' "${AUTHJSON}:/root/.local/share/opencode/auth.json:ro"
    '--volume' "${AUTHJSON}:/root/.local/share/opencode/auth.json"
  )
}

# vim configuration: if some vim configuration can be found, mount it
# into the container
[[ "${C[use_vim_configuration]}" = 'true' ]] && {
  [[ -f "${HOME}/.vimrc" ]] &&
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vimrc:/root/.vimrc:ro" )

  if [[ -d "${HOME}/.vim" ]]; then
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vim:/root/.vim:ro" )
  else
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"${HOME}/.config"}"
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

"${C[crt]}" run "${PMARGV[@]}" opencode "${@}"

