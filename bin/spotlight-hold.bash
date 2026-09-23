#!/usr/bin/env bash
# Keep command output visible even when the chosen terminal lacks --hold.
# --hold-if N holds only when the command exits with N (ssh's own errors are 255),
# or when it could not start at all (126, 127).
hold_if=
if [ "$1" = --hold-if ]; then
  hold_if=$2
  shift 2
fi
trap : INT
"$@"
status=$?
case $status in "$hold_if" | 126 | 127) ;; *) [ -n "$hold_if" ] && exit "$status" ;; esac
printf '\nProcess exited (%s). Press Enter to close.\n' "$status"
IFS= read -r _
exit "$status"
