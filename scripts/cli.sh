#!/bin/bash
# This command is one entrypoint that delegates to the concrete scripts to make the docker interface nicer.
# It includes no business logic on its own, only argument parsing and delegation.
#
# Usage: cli.sh <command> [args...]
# 
# The command may be any executable *.sh file in this directory
# The rest of the args are passed untouched into the subprocess

set -o errexit -o nounset -o pipefail
# command -v shellcheck >/dev/null && shellcheck "$0"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

usage() {
    echo "Usage: $0: [-s signature] <command> [args]"
    exit 2
}

check() {
    if [ ! -f "$SCRIPT_DIR/$1" ]; then
        # If no file, return error so checks continue
        return 1
    fi
    if [ ! -x "$SCRIPT_DIR/$1" ]; then
        # If found but not executable, this is a dev error, and flag it rather than silently retrying, to help debug
        echo "Script not executable $1"
        exit 1
    fi
    EXEC_FILE="$SCRIPT_DIR/$1"
}

# Parse out the option flags
SIG=ecdsa
while getopts s: opt
do
    case $opt in
    s)    SIG="$OPTARG";;
    ?)   usage;;
    esac
done
shift $(($OPTIND - 1))

# Ensure there is at least one positional argument with the command name
if [ "$#" -eq 0 ]; then
    usage
fi
CMD="$1.sh"
shift

# Allow some generic ones over multiple modes. Try in this order:
# "$SIG/$1.sh"
# "$1.sh"

check "$SIG/$CMD" || check "$CMD" ||  (echo "Error: Command $CMD not found"  && exit 1)

# go to the top-level dir, above scripts, for standard location to run from
cd $SCRIPT_DIR/..

echo "Calling:" "$EXEC_FILE" "$@"
exec "$EXEC_FILE" "$@"
