#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Sanity, after every change (README.md, Self-test): the 8b/10b proofs and a
# few runs on each simulator, about 2 minutes. A run marked known fails on an
# open simulator issue: it fails as known (its log shows SIG) without failing
# the list; a PASS is fine too ("known ... not hit"). Prints one line per run,
# logs in work/logs/sanity/; exits 1 if a run fails otherwise, or if
# JanusHDL --race-detect finds a race not on the known list (RACES_OK).
# To add a simulator: a make target sim_<name>, and a line below.
#
# Usage: bash run-sanity.sh [make variables]

set -u
cd "$(dirname "$0")"
LOG=work/logs/sanity
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
    printf '%-16s %4d s  %-72s %s  (%s)\n' "$n" $((SECONDS - t0)) "$*" "$st" "$r"
}

JANUS_MODES="" JANUS_MODES_SIG=""
JANUS_RULES="" JANUS_RULES_SIG=""
XSIM_K="openSERDES_BFM #9" XSIM_SIG="FATAL_ERROR"

run formal          "" "" formal "$@"
run verilator-rules "" "" sim_rules RULES_RUNS=3:0:FAST "$@"
run icarus          "" "" sim_icarus ICARUS_MODELS="FAST ACCURATE" ICARUS_RUNS="1:1:1 3:0:0" RULES_RUNS="3:0:FAST 0:0:FAST" "$@"
run xsim            "$XSIM_K" "$XSIM_SIG" sim_xsim XSIM_MODELS=FAST RULES_RUNS=3:0:FAST "$@"
run janushdl-modes  "$JANUS_MODES" "$JANUS_MODES_SIG" sim_janushdl JANUS_MODELS=FAST RULES_RUNS= "$@"
run janushdl-rules  "$JANUS_RULES" "$JANUS_RULES_SIG" sim_janushdl JANUS_MODELS= RULES_RUNS=3:0:FAST JHDL="jhdl --race-detect" "$@"

# JanusHDL's race detection on the tb_rules run: two processes whose order
# decides a value in one delta cycle (a warning per pair of places). The
# known ones (RACES_OK, by variable: none now) pass; a new one fails the list.
RACES_OK=""
f=work/janushdl/rules_3_0_FAST/run.out
r=$(grep -a -h -m1 '^race detection:' $f 2>/dev/null)
new=$(grep -a 'warning: race' $f 2>/dev/null | grep -a -o -E '(reads|writes) /tb_rules/[^ ]+' | sed 's|.* /tb_rules/||' |
      sort -u | { if [ -n "$RACES_OK" ]; then grep -v -x -F -f <(echo $RACES_OK | tr ' ' '\n'); else cat; fi; } | tr '\n' ' ')
if [ -z "$r" ] || [ -n "$new" ]; then fails=$((fails + 1)); fi
printf '%-16s %4d s  %-72s %s; new: %s\n' race-detect 0 "janushdl-rules --race-detect" "${r:-no race report}" "${new:-none}"

echo "sanity: $fails failed"
[ $fails = 0 ]
