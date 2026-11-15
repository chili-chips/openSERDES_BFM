#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Regression, before a push (README.md, Self-test): every simulator target in
# full, and the 8b/10b proofs, about 12 minutes. A run marked known fails on
# an open simulator issue: it fails as known (its log shows SIG) without
# failing the list; a PASS is fine too ("known ... not hit"). Prints one line
# per run, logs in work/logs/regression/; exits 1 if a run fails otherwise.
# To add a simulator: a make target sim_<name>, and a line below.
#
# Usage: bash run-regression.sh [make variables]

set -u
cd "$(dirname "$0")"
LOG=work/logs/regression
mkdir -p $LOG
fails=0

run() {  # name, known issue ("" if none), its log signature, make target and variables
    local n=$1 k=$2 sig=$3 t0=$SECONDS r st
    shift 3
    if make --no-print-directory "$@" > $LOG/$n.log 2>&1; then st=PASS; else st=FAIL; fi
    r="$(grep -a -c ': PASS$' $LOG/$n.log) PASS, $(grep -a -c -E ': FAIL|no result' $LOG/$n.log) FAIL lines"
    case "$1" in formal) r=$(grep -a -o '[0-9]* proved, [0-9]* failed' $LOG/$n.log);; esac
    if [ $st = PASS ]; then [ -z "$k" ] || st="PASS (known $k not hit)"
    elif [ -n "$k" ] && grep -a -q -E "$sig" $LOG/$n.log; then st="known $k"
    else fails=$((fails + 1)); fi
    printf '%-16s %4d s  %-38s %s  (%s)\n' "$n" $((SECONDS - t0)) "$*" "$st" "$r"
}

JANUS_MODES="openCologne #12" JANUS_MODES_SIG="tb_modes.sv:294"
JANUS_RULES="openCologne #13" JANUS_RULES_SIG="ccfpga_serdes.BFM.sv:438"

run formal          "" "" formal "$@"
run verilator       "" "" sim_modes "$@"            # tb_modes in full, then tb_rules
run icarus          "" "" sim_icarus "$@"
run xsim            "" "" sim_xsim "$@"
run janushdl-modes  "$JANUS_MODES" "$JANUS_MODES_SIG" sim_janushdl RULES_RUNS= "$@"
run janushdl-rules  "$JANUS_RULES" "$JANUS_RULES_SIG" sim_janushdl JANUS_MODELS= "$@"

echo "regression: $fails failed"
[ $fails = 0 ]
