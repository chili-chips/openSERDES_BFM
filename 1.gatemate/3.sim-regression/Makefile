# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# The SerDes BFM's own tests: one BFM looped back (tb_modes), its rules
# at the ports (tb_rules), the 8b/10b proofs.
#   make             sim_icarus, sim_modes and formal
#   make sim_modes   the CDR_MODELs against each other, Verilator: 9 datapath width and
#                    comma lane cases, data bit-exact, latencies within MODES_TOL_NS; then
#                    PRBS7/31 with forced errors, 5 ms at 3 Gb/s, the random RX word phase;
#                    then sim_rules
#   make sim_rules   the BFM's rules (tb_rules, at the ports), Verilator
#   make sim_icarus  tb_modes in Icarus: each CDR_MODEL at 16, 32 and 64 bits,
#                    ALIGN_COMMA_WORD 01 (even lane) and 11 (lane 0 or 4); then tb_rules
#   make sim_xsim    Vivado XSIM: tb_modes at 64 bits, each CDR_MODEL; then tb_rules
#   make sim_janushdl  JanusHDL (jhdl): the same runs as sim_xsim
#   make formal     the 8b/10b proofs (../2.formal/run-formal.sh)
#   make sanity      the sanity list (run-sanity.sh), about 2 minutes
#   make regression  the regression list (run-regression.sh)
#   make clean       removes work/
# Everything a build or run makes goes to work/: work/verilator/, work/icarus/,
# work/xsim/, work/janushdl/, and the logs in work/logs/.
# Settings: MODES_TOL_NS   sim_modes: how far a mode's latency may be from ACCURATE's
#                          (default 1.6)
#           RULES_RUNS     the tb_rules runs, DP:SLIDE:CDR_MODEL
#           ICARUS_MODELS  ICARUS_RUNS: the tb_modes runs of sim_icarus
#           XSIM_MODELS    JANUS_MODELS: the tb_modes runs of sim_xsim, sim_janushdl
#           XILINX_VIVADO  where Vivado is (default ~/Xilinx/2026.1/Vivado)

# a simulator that fails in a pipe (| tee) fails the target
SHELL       := /bin/bash
.SHELLFLAGS := -o pipefail -ec

MODEL := ../1.model
BFM   := $(MODEL)/ccfpga_serdes_pkg.sv $(MODEL)/ccfpga_serdes.BFM.sv
W     := work
VW    := $(W)/verilator
IW    := $(W)/icarus
XW    := $(W)/xsim
LOGS  := $(W)/logs

.PHONY: all sim_modes sim_rules sim_icarus sim_xsim sim_janushdl formal sanity regression clean

all: sim_icarus sim_modes formal

$(VW) $(IW) $(XW) $(LOGS):
	@mkdir -p $@

# The SerDes BFM modes against each other, at each datapath width and comma
# lane: data bit-exact, and the latency of every comma within MODES_TOL_NS
# of ACCURATE's (4 UI at 2.5 Gb/s: FAST knows a bit only at the next edge)
# The RX word phase is fixed here: the comma lane is swept instead. Then,
# 64 bits: PRBS7 and PRBS31 with forced errors, each mode; 5 ms at 3 Gb/s
# (a UI off the 100 fs grid), NONE and FAST; the random RX word phase with
# ALIGN_COMMA_WORD = 11, ACCURATE, seeds 1 to 3.
MODES_TOL_NS ?= 1.6
MODES_RUNS   := 0:0 0:1 1:0 1:1 1:3 3:0 3:3 3:5 3:7
MODES_VLT    := verilator --binary --assert --timing --timescale 1ns/1ps -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
                -Wno-PINCONNECTEMPTY --top-module tb_modes $(MODEL)/ccfpga_serdes.vlt

# tb_rules runs: datapath:RX_SLIDE_MODE:CDR_MODEL (a real line: FAST, ACCURATE)
RULES_RUNS ?= 3:0:FAST 3:0:ACCURATE 0:0:FAST 3:1:FAST 3:2:FAST 3:3:FAST
RULES_VLT  := verilator --binary --assert --timing --timescale 1ns/1ps -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
              -Wno-PINCONNECTEMPTY --top-module tb_rules $(MODEL)/ccfpga_serdes.vlt
# a tb_rules run's lines: the total, and any rule that failed
RULES_GREP := grep -E "^TB_RULES: (DP .*|.*: FAIL .*)$$"

sim_modes: | $(VW) $(LOGS)
	@for m in NONE FAST ACCURATE; do for dp in 0 1 3; do \
	  $(MODES_VLT) -GDP_SEL=$$dp -Mdir $(VW)/modes_$${m}_$$dp +define+CDR_MODEL=$$m +define+BHV_RX_WORD_PHASE_RANDOM=0 \
	    $(BFM) tb_modes.sv > /dev/null; \
	done; done
	@$(MODES_VLT) -GDP_SEL=3 -GALIGN="2'b11" -Mdir $(VW)/modes_rand +define+CDR_MODEL=ACCURATE $(BFM) tb_modes.sv > /dev/null
	@L=$(LOGS)/sim_modes.log; rm -f $$L; for r in $(MODES_RUNS); do \
	  dp=$${r%%:*}; c=$${r##*:}; \
	  rm -f $(VW)/modes_NONE.txt $(VW)/modes_FAST.txt $(VW)/modes_ACCURATE.txt; \
	  for m in NONE FAST ACCURATE; do \
	    $(VW)/modes_$${m}_$$dp/Vtb_modes +comma=$$c +words=$(VW)/modes_$$m.txt | grep "TB_MODES" | tee -a $$L; \
	  done; \
	  paste $(VW)/modes_ACCURATE.txt $(VW)/modes_NONE.txt $(VW)/modes_FAST.txt | awk -v tol=$(MODES_TOL_NS) \
	    '{ for (i = 2; i <= 3; i++) { d = $$i - $$1; if (NR == 1 || d < lo[i]) lo[i] = d; if (NR == 1 || d > hi[i]) hi[i] = d; \
	         if (d > tol || -d > tol) bad++ } a = $$1 } \
	     END { printf "MODES: ACCURATE %.1f ns, NONE %+.1f..%+.1f, FAST %+.1f..%+.1f, %d commas: %s\n", \
	           a, lo[2], hi[2], lo[3], hi[3], NR, (bad || NR == 0) ? "FAIL" : "PASS" }' | tee -a $$L; \
	done
	@for m in NONE FAST ACCURATE; do for p in 1 4; do \
	  $(VW)/modes_$${m}_3/Vtb_modes +prbs=$$p | grep "TB_MODES" | tee -a $(LOGS)/sim_modes.log; \
	done; done
	@for m in NONE FAST; do \
	  $(VW)/modes_$${m}_3/Vtb_modes +cfg1=063A +run_us=5000 | grep "TB_MODES" | tee -a $(LOGS)/sim_modes.log; \
	done
	@for s in 1 2 3; do \
	  $(VW)/modes_rand/Vtb_modes +comma=3 +verilator+seed+$$s | grep "TB_MODES" | tee -a $(LOGS)/sim_modes.log; \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_modes.log) -eq 38
	@test $$(grep -c "^MODES: .*: PASS$$" $(LOGS)/sim_modes.log) -eq 9
	@$(MAKE) --no-print-directory sim_rules

sim_rules: | $(VW) $(LOGS)
	@rm -f $(LOGS)/sim_rules.log; for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; o=$(VW)/rules_$${dp}_$${sl}_$$m; \
	  $(RULES_VLT) -GDP=$$dp -GSLIDE=$$sl -Mdir $$o +define+CDR_MODEL=$$m $(BFM) tb_rules.sv > /dev/null; \
	  $$o/Vtb_rules | $(RULES_GREP) | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $(LOGS)/sim_rules.log; \
	done
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_rules.log) -eq $(words $(RULES_RUNS))

# Verilator resolves names after the whole module is read, so a name used
# before its declaration passes, even with -Wall. Icarus (and the LRM)
# stop on it. Icarus has no `unique case` checks: its "sorry" notes on them
# are filtered out. The decode-table check (+nolut) is left to sim_modes:
# it takes Icarus 12 s. Runs: datapath:comma lane:ALIGN_COMMA_WORD; the RX
# word phase is random (Icarus's fixed seed)
ICARUS_MODELS ?= NONE FAST ACCURATE
ICARUS_RUNS   ?= 0:1:0 1:3:0 1:1:1 3:0:0 3:3:3

sim_icarus: | $(IW) $(LOGS)
	@L=$(LOGS)/sim_icarus.log; rm -f $$L; for m in $(ICARUS_MODELS); do for r in $(ICARUS_RUNS); do \
	  dp=$${r%%:*}; c=$${r#*:}; c=$${c%%:*}; al=$${r##*:}; v=$(IW)/modes_$${m}_$${dp}_$$al.vvp; \
	  rm -f $$v; \
	  iverilog -g2012 -DCDR_MODEL=$$m -Ptb_modes.DP_SEL=$$dp -Ptb_modes.ALIGN=$$al -o $$v $(BFM) tb_modes.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  test -f $$v; \
	  vvp -N $$v +model=$$m +comma=$$c +nolut | grep "TB_MODES" | tee -a $$L; \
	done; done
	@for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; v=$(IW)/rules_$${dp}_$${sl}_$$m.vvp; \
	  rm -f $$v; \
	  iverilog -g2012 -DCDR_MODEL=$$m -Ptb_rules.DP=$$dp -Ptb_rules.SLIDE=$$sl -o $$v $(BFM) tb_rules.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  test -f $$v; \
	  vvp -N $$v | $(RULES_GREP) | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $(LOGS)/sim_icarus.log; \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_icarus.log) -eq $(words $(foreach m,$(ICARUS_MODELS),$(ICARUS_RUNS)))
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_icarus.log) -eq $(words $(RULES_RUNS))

# Vivado XSIM: tb_modes at 64 bits, comma in lane 0, each CDR_MODEL; then
# tb_rules. xvlog, xelab and xsim write in the current directory: each run
# builds and runs in its own work/xsim/<run>/
XILINX_VIVADO ?= $(HOME)/Xilinx/2026.1/Vivado
XSIM_BFM      := $(abspath $(BFM))
XSIM_MODELS   ?= NONE FAST ACCURATE

sim_xsim: | $(XW) $(LOGS)
	@L=$(CURDIR)/$(LOGS)/sim_xsim.log; rm -f $$L; for m in $(XSIM_MODELS); do \
	  d=$(XW)/modes_$$m; rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  $(XILINX_VIVADO)/bin/xvlog -sv --nolog -d CDR_MODEL=$$m -d BHV_RX_WORD_PHASE_RANDOM=0 $(XSIM_BFM) \
	    $(CURDIR)/tb_modes.sv > xvlog.out 2>&1 || { cat xvlog.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xelab --nolog --timescale 1ns/1ps -generic_top DP_SEL=3 --snapshot s work.tb_modes \
	    > xelab.out 2>&1 || { cat xelab.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xsim s --nolog -R -testplusarg comma=0 -testplusarg words=modes_$$m.txt > run.out 2>&1; \
	  grep "TB_MODES" run.out | tee -a $$L ); \
	done
	@L=$(CURDIR)/$(LOGS)/sim_xsim.log; for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; d=$(XW)/rules_$${dp}_$${sl}_$$m; \
	  rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  $(XILINX_VIVADO)/bin/xvlog -sv --nolog -d CDR_MODEL=$$m $(XSIM_BFM) $(CURDIR)/tb_rules.sv \
	    > xvlog.out 2>&1 || { cat xvlog.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xelab --nolog -generic_top DP=$$dp -generic_top SLIDE=$$sl --snapshot s work.tb_rules \
	    > xelab.out 2>&1 || { cat xelab.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xsim s --nolog -R > run.out 2>&1; \
	  $(RULES_GREP) run.out | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $$L ); \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_xsim.log) -eq $(words $(XSIM_MODELS))
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_xsim.log) -eq $(words $(RULES_RUNS))

# JanusHDL: the runs of sim_xsim. jhdl compiles at each run, in its own
# work/janushdl/<run>/. A run with no result line shows its first errors
JHDL         ?= jhdl
JANUS_ERR    := grep -a -A1 -m3 -E "(^|: )error:" run.out || tail -5 run.out
JW           := $(W)/janushdl
JANUS_MODELS ?= NONE FAST ACCURATE
JANUS_S      ?= 900

sim_janushdl: | $(LOGS)
	@L=$(CURDIR)/$(LOGS)/sim_janushdl.log; rm -f $$L; touch $$L; for m in $(JANUS_MODELS); do \
	  d=$(JW)/modes_$$m; rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  timeout $(JANUS_S) $(JHDL) --top tb_modes +define+CDR_MODEL=$$m +define+BHV_RX_WORD_PHASE_RANDOM=0 -gDP_SEL=3 \
	    $(XSIM_BFM) $(CURDIR)/tb_modes.sv +comma=0 +words=modes_$$m.txt > run.out 2>&1 || true; \
	  grep "TB_MODES" run.out | tee -a $$L || { echo "TB_MODES: $$m: no result:"; $(JANUS_ERR); } | tee -a $$L ); \
	done
	@L=$(CURDIR)/$(LOGS)/sim_janushdl.log; for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; d=$(JW)/rules_$${dp}_$${sl}_$$m; \
	  rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  timeout $(JANUS_S) $(JHDL) --top tb_rules +define+CDR_MODEL=$$m -gDP=$$dp -gSLIDE=$$sl \
	    $(XSIM_BFM) $(CURDIR)/tb_rules.sv > run.out 2>&1 || true; \
	  $(RULES_GREP) run.out | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $$L || \
	    { echo "TB_RULES: $$r: no result:"; $(JANUS_ERR); } | tee -a $$L ); \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_janushdl.log) -eq $(words $(JANUS_MODELS))
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_janushdl.log) -eq $(words $(RULES_RUNS))

formal: | $(LOGS)
	bash ../2.formal/run-formal.sh | tee $(LOGS)/formal.log

sanity:
	@bash run-sanity.sh

regression:
	@bash run-regression.sh

clean:
	rm -rf $(W)

# -----------------------------------------------------------------------------
# Project:     openSERDES_BFM
# Description: open-source SerDes BFM
# -----------------------------------------------------------------------------
