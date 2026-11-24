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
#   make sim_ppm     two BFMs a frequency offset apart (tb_ppm), Verilator, ACCURATE:
#                    the recovered clock holds the data; a local clock overruns the RX buffer
#   make sim_icarus  tb_modes in Icarus: each CDR_MODEL at 16, 32 and 64 bits,
#                    ALIGN_COMMA_WORD 01 (even lane) and 11 (lane 0 or 4); then tb_rules
#   make sim_xsim    Vivado XSIM: tb_modes at 64 bits, each CDR_MODEL; then tb_rules
#   make sim_janushdl  JanusHDL (jhdl): the same runs as sim_xsim
#   make formal     the 8b/10b proofs (../2.formal/run-formal.sh)
#   make waves       the waveforms for WaveCrux: tb_modes (64 bits, ACCURATE) and tb_rules
#                    (64 bits, FAST), each an FST and its session in work/waves/
#                    (wavecrux-session.py); WAVES_SIM=verilator (default) or icarus
#   make lint        Verible on the BFM and the test benches (lint.verible)
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
#           XILINX_VIVADO  where Vivado is (default ~/Xilinx/2026.2/Vivado)

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

# The HDL has no `timescale: each simulator takes it on its command line.
# 1ns/10ps (Verilator, xelab and jhdl --timescale). Icarus has no
# option either: a command file (-c) gives it
TIMESCALE := 1ns/10ps
ICARUS_TS := $(IW)/timescale.cf

.PHONY: all sim_modes sim_rules sim_ppm sim_icarus sim_xsim sim_janushdl formal waves lint sanity regression clean

all: sim_icarus sim_modes formal

$(VW) $(IW) $(XW) $(LOGS):
	@mkdir -p $@

$(ICARUS_TS): | $(IW)
	@echo "+timescale+$(TIMESCALE)" > $@

# The SerDes BFM modes against each other, at each datapath width and comma
# lane: data bit-exact, and the latency of every comma within MODES_TOL_NS
# of ACCURATE's (4 UI at 2.5 Gb/s: FAST knows a bit only at the next edge)
# The RX word phase is fixed here: the comma lane is swept instead. Then,
# 64 bits: PRBS7 and PRBS31 with forced errors, each mode; 5 ms at 3 Gb/s
# (a UI off the time grid), NONE and FAST; the random RX word phase with
# ALIGN_COMMA_WORD = 11, ACCURATE, seeds 1 to 3.
MODES_TOL_NS ?= 1.6
MODES_RUNS   := 0:0 0:1 1:0 1:1 1:3 3:0 3:3 3:5 3:7
MODES_VLT    := verilator --binary --assert --timing --timescale $(TIMESCALE) -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
                -Wno-PINCONNECTEMPTY --top-module tb_modes $(MODEL)/ccfpga_serdes.vlt

# tb_rules runs: datapath:RX_SLIDE_MODE:CDR_MODEL (a real line: FAST, ACCURATE)
RULES_RUNS ?= 3:0:FAST 3:0:ACCURATE 0:0:FAST 3:1:FAST 3:2:FAST 3:3:FAST
RULES_VLT  := verilator --binary --assert --timing --timescale $(TIMESCALE) -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
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
	@# a PHY that applies RX_POLARITY_I late (+serdes_rx_pol_lat): 64 bits, FAST
	@$(VW)/rules_3_0_FAST/Vtb_rules +serdes_rx_pol_lat=16 | $(RULES_GREP) \
	  | sed "s/^TB_RULES: DP/TB_RULES: FAST, polarity 16 words late, DP/" | tee -a $(LOGS)/sim_rules.log
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_rules.log) -eq $$(( $(words $(RULES_RUNS)) + 1 ))

# Two BFMs across a frequency offset (tb_ppm), Verilator, ACCURATE, clock
# correction off: on B's recovered clock every byte must arrive at +300,
# -300, -90 and +600 ppm; on B's own PLL clock the RX buffer must give way
# (RX_BUF_ERR_O): B faster (-1000 ppm, underflow) and slower (+1000 ppm,
# overflow, 2.5 ms). Runs: ppm:rxclk:run_us
PPM_RUNS ?= 300:rec:400 -300:rec:400 -90:rec:400 600:rec:400 -1000:local:400 1000:local:2500
PPM_VLT  := verilator --binary --assert --timing --timescale $(TIMESCALE) -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
            -Wno-PINCONNECTEMPTY --top-module tb_ppm $(MODEL)/ccfpga_serdes.vlt

sim_ppm: | $(VW) $(LOGS)
	@$(PPM_VLT) -Mdir $(VW)/ppm +define+CDR_MODEL=ACCURATE $(BFM) tb_ppm.sv > /dev/null
	@: > $(LOGS)/sim_ppm.log; for r in $(PPM_RUNS); do \
	  p=$${r%%:*}; c=$${r#*:}; c=$${c%%:*}; us=$${r##*:}; \
	  $(VW)/ppm/Vtb_ppm +ppm=$$p +rxclk=$$c +run_us=$$us | grep "TB_PPM" | tee -a $(LOGS)/sim_ppm.log; \
	done
	@test $$(grep -c "^TB_PPM: .*: PASS" $(LOGS)/sim_ppm.log) -eq $(words $(PPM_RUNS))

# Verilator resolves names after the whole module is read, so a name used
# before its declaration passes, even with -Wall. Icarus (and the LRM)
# stop on it. Icarus has no `unique case` checks: its "sorry" notes on them
# are filtered out. The decode-table check (+nolut) is left to sim_modes:
# it takes Icarus 12 s. Runs: datapath:comma lane:ALIGN_COMMA_WORD; the RX
# word phase is random (Icarus's fixed seed)
ICARUS_MODELS ?= NONE FAST ACCURATE
ICARUS_RUNS   ?= 0:1:0 1:3:0 1:1:1 3:0:0 3:3:3
# tb_ppm in Icarus: ppm:rxclk:run_us, short (ACCURATE is slow there)
ICARUS_PPM    ?= -90:rec:100 -1000:local:100

sim_icarus: $(ICARUS_TS) | $(IW) $(LOGS)
	@L=$(LOGS)/sim_icarus.log; rm -f $$L; for m in $(ICARUS_MODELS); do for r in $(ICARUS_RUNS); do \
	  dp=$${r%%:*}; c=$${r#*:}; c=$${c%%:*}; al=$${r##*:}; v=$(IW)/modes_$${m}_$${dp}_$$al.vvp; \
	  rm -f $$v; \
	  iverilog -g2012 -c $(ICARUS_TS) -DCDR_MODEL=$$m -Ptb_modes.DP_SEL=$$dp -Ptb_modes.ALIGN=$$al -o $$v $(BFM) tb_modes.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  test -f $$v; \
	  vvp -N $$v +model=$$m +comma=$$c +nolut | grep "TB_MODES" | tee -a $$L; \
	done; done
	@for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; v=$(IW)/rules_$${dp}_$${sl}_$$m.vvp; \
	  rm -f $$v; \
	  iverilog -g2012 -c $(ICARUS_TS) -DCDR_MODEL=$$m -Ptb_rules.DP=$$dp -Ptb_rules.SLIDE=$$sl -o $$v $(BFM) tb_rules.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  test -f $$v; \
	  vvp -N $$v | $(RULES_GREP) | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $(LOGS)/sim_icarus.log; \
	done
	@iverilog -g2012 -c $(ICARUS_TS) -DCDR_MODEL=ACCURATE -o $(IW)/ppm.vvp $(BFM) tb_ppm.sv 2>&1 \
	  | { grep -v "sorry: Case unique" || true; }
	@for r in $(ICARUS_PPM); do \
	  p=$${r%%:*}; c=$${r#*:}; c=$${c%%:*}; us=$${r##*:}; \
	  vvp -N $(IW)/ppm.vvp +ppm=$$p +rxclk=$$c +run_us=$$us | grep "TB_PPM" | tee -a $(LOGS)/sim_icarus.log; \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_icarus.log) -eq $(words $(foreach m,$(ICARUS_MODELS),$(ICARUS_RUNS)))
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_icarus.log) -eq $(words $(RULES_RUNS))
	@test $$(grep -c "^TB_PPM: .*: PASS" $(LOGS)/sim_icarus.log) -eq $(words $(ICARUS_PPM))

# Vivado XSIM: tb_modes at 64 bits, comma in lane 0, each CDR_MODEL; then
# tb_rules. xvlog, xelab and xsim write in the current directory: each run
# builds and runs in its own work/xsim/<run>/
XILINX_VIVADO ?= $(HOME)/Xilinx/2026.2/Vivado
XSIM_BFM      := $(abspath $(BFM))
XSIM_MODELS   ?= NONE FAST ACCURATE

sim_xsim: | $(XW) $(LOGS)
	@L=$(CURDIR)/$(LOGS)/sim_xsim.log; rm -f $$L; for m in $(XSIM_MODELS); do \
	  d=$(XW)/modes_$$m; rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  $(XILINX_VIVADO)/bin/xvlog -sv --nolog -d CDR_MODEL=$$m -d BHV_RX_WORD_PHASE_RANDOM=0 $(XSIM_BFM) \
	    $(CURDIR)/tb_modes.sv > xvlog.out 2>&1 || { cat xvlog.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xelab --nolog --timescale $(TIMESCALE) -generic_top DP_SEL=3 --snapshot s work.tb_modes \
	    > xelab.out 2>&1 || { cat xelab.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xsim s --nolog -R -testplusarg comma=0 -testplusarg words=modes_$$m.txt > run.out 2>&1; \
	  grep "TB_MODES" run.out | tee -a $$L ); \
	done
	@L=$(CURDIR)/$(LOGS)/sim_xsim.log; for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; d=$(XW)/rules_$${dp}_$${sl}_$$m; \
	  rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  $(XILINX_VIVADO)/bin/xvlog -sv --nolog -d CDR_MODEL=$$m $(XSIM_BFM) $(CURDIR)/tb_rules.sv \
	    > xvlog.out 2>&1 || { cat xvlog.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xelab --nolog --timescale $(TIMESCALE) -generic_top DP=$$dp -generic_top SLIDE=$$sl --snapshot s work.tb_rules \
	    > xelab.out 2>&1 || { cat xelab.out; exit 1; }; \
	  $(XILINX_VIVADO)/bin/xsim s --nolog -R > run.out 2>&1 || true; \
	  { $(RULES_GREP) run.out || true; grep -a -m1 -E "FATAL_ERROR|engine not responding" run.out || true; } | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $$L ); \
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
	  timeout $(JANUS_S) $(JHDL) --top tb_modes --timescale $(TIMESCALE) +define+CDR_MODEL=$$m +define+BHV_RX_WORD_PHASE_RANDOM=0 -gDP_SEL=3 \
	    $(XSIM_BFM) $(CURDIR)/tb_modes.sv +comma=0 +words=modes_$$m.txt > run.out 2>&1 || true; \
	  grep "TB_MODES" run.out | tee -a $$L || { echo "TB_MODES: $$m: no result:"; $(JANUS_ERR); } | tee -a $$L ); \
	done
	@L=$(CURDIR)/$(LOGS)/sim_janushdl.log; for r in $(RULES_RUNS); do \
	  dp=$${r%%:*}; sl=$${r#*:}; sl=$${sl%%:*}; m=$${r##*:}; d=$(JW)/rules_$${dp}_$${sl}_$$m; \
	  rm -rf $$d; mkdir -p $$d; ( cd $$d; \
	  timeout $(JANUS_S) $(JHDL) --top tb_rules --timescale $(TIMESCALE) +define+CDR_MODEL=$$m -gDP=$$dp -gSLIDE=$$sl \
	    $(XSIM_BFM) $(CURDIR)/tb_rules.sv > run.out 2>&1 || true; \
	  $(RULES_GREP) run.out | sed "s/^TB_RULES: DP/TB_RULES: $$m, DP/" | tee -a $$L || \
	    { echo "TB_RULES: $$r: no result:"; $(JANUS_ERR); } | tee -a $$L ); \
	done
	@test $$(grep -c "^TB_MODES: .*: PASS$$" $(LOGS)/sim_janushdl.log) -eq $(words $(JANUS_MODELS))
	@test $$(grep -c "^TB_RULES: .*: PASS$$" $(LOGS)/sim_janushdl.log) -eq $(words $(RULES_RUNS))

formal: | $(LOGS)
	bash ../2.formal/run-formal.sh | tee $(LOGS)/formal.log

# The waveforms for WaveCrux: one run of each test bench, dumped whole
# (+define+WAVES), run in work/waves/; then a session for each FST. Its
# signal numbers differ from one simulator to the next, so the session is
# made from the FST (wavecrux-session.py)
WAVES_SIM ?= verilator
WV        := $(W)/waves
PYTHON    ?= python3

waves: $(ICARUS_TS) | $(LOGS)
	@mkdir -p $(WV)
	@case $(WAVES_SIM) in \
	verilator) \
	  $(MODES_VLT) --trace-fst -GDP_SEL=3 -Mdir $(VW)/waves_modes +define+CDR_MODEL=ACCURATE \
	    +define+BHV_RX_WORD_PHASE_RANDOM=0 +define+WAVES $(BFM) tb_modes.sv > /dev/null; \
	  $(RULES_VLT) --trace-fst -GDP=3 -GSLIDE=0 -Mdir $(VW)/waves_rules +define+CDR_MODEL=FAST \
	    +define+WAVES $(BFM) tb_rules.sv > /dev/null; \
	  ( cd $(WV) && ../verilator/waves_modes/Vtb_modes +comma=0 | grep "TB_MODES" ); \
	  ( cd $(WV) && ../verilator/waves_rules/Vtb_rules | $(RULES_GREP) ) ;; \
	icarus) \
	  mkdir -p $(IW); \
	  iverilog -g2012 -c $(ICARUS_TS) -DCDR_MODEL=ACCURATE -DWAVES -Ptb_modes.DP_SEL=3 -o $(IW)/waves_modes.vvp $(BFM) tb_modes.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  iverilog -g2012 -c $(ICARUS_TS) -DCDR_MODEL=FAST -DWAVES -Ptb_rules.DP=3 -Ptb_rules.SLIDE=0 -o $(IW)/waves_rules.vvp $(BFM) tb_rules.sv 2>&1 \
	    | { grep -v "sorry: Case unique" || true; }; \
	  ( cd $(WV) && vvp -N ../icarus/waves_modes.vvp -fst +model=ACCURATE +comma=0 +nolut | grep "TB_MODES" ); \
	  ( cd $(WV) && vvp -N ../icarus/waves_rules.vvp -fst | $(RULES_GREP) ) ;; \
	*) echo "WAVES_SIM must be verilator or icarus (got \"$(WAVES_SIM)\")"; exit 1 ;; \
	esac
	@for t in tb_modes tb_rules; do \
	  mv -f $(WV)/$$t.fst $(WV)/$(WAVES_SIM).$$t.fst; \
	  $(PYTHON) wavecrux-session.py $$t $(WV)/$(WAVES_SIM).$$t.fst $(WV)/$(WAVES_SIM).$$t.wavecrux; \
	done

# Verible on the BFM and the test benches (lint.verible: our rule set)
VERIBLE_LINT ?= verible-verilog-lint
LINT_SRC     := $(wildcard $(MODEL)/*.sv) tb_modes.sv tb_rules.sv tb_ppm.sv

lint:
	@$(VERIBLE_LINT) --rules_config=lint.verible $(LINT_SRC) && echo "lint: Verible, $(words $(LINT_SRC)) files, clean"

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
