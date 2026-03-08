#!/usr/bin/env bash

if {{DEBUG}}; then
    set -x
fi

{{BASH_RLOCATION_FN}}

runfiles_export_envvars

set -o errexit -o nounset -o pipefail

source "$(rlocation "{{VENV}}")"/bin/activate

if [ -n "{{MAIN}}" ]; then
    exec "$(rlocation "{{VENV}}")"/bin/python {{INTERPRETER_FLAGS}} "$(rlocation "{{MAIN}}")" "$@"
fi

exec "$(rlocation "{{VENV}}")"/bin/python {{INTERPRETER_FLAGS}} "$@"
