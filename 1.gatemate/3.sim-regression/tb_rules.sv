// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// SerDes BFM rules: what the BFM does at its ports where DS1001 is
// silent, checked one by one; rules straight from DS1001 are marked DS.
// Ports only, so it runs on any model with these ports. One BFM, its TX looped to its
// RX through a wire delay the test moves (a bit slip), 2.5 Gb/s, PLL_CLK_O
// on TX_CLK_I and RX_CLK_I. CDR_MODEL FAST or ACCURATE: a real line.
//   DP = 3: regfile, PLL, resets, TX (RD+, buffer), comma alignment,
//           PRBS, electrical idle, loopback, RX_CLK_O
//   DP = 0: 16-bit TX lane rotation, PRBS-31 at 16 bits
//   SLIDE = 1, 2, 3: RX_SLIDE_I, a bit, a symbol, both
// Prints TB_RULES: <rule>: PASS/FAIL, then a total. make sim_modes and
// make sim_icarus run it. Times in ns at any time unit, as the BFM's.
//==========================================================================
module tb_rules #(
    parameter int DP    = 3,  // TX/RX_DATAPATH_SEL: 0 16 bits, 3 64 bits
    parameter int SLIDE = 0   // RX_SLIDE_MODE
);

  localparam int LANES = (DP == 0) ? 2 : (DP == 1) ? 4 : 8;
  localparam real UI = 0.4;  // ns at 2.5 Gb/s
  localparam logic [15:0] CFG1 = (DP == 0) ? 16'h16DA : 16'h16FA;  // 2.5 Gb/s, a word a clock

  // now, in ns: a time literal takes the module's unit
  function automatic real now_ns();
    return $realtime / 1ns;
  endfunction

  logic clk_ref, clk_reg;

  initial begin : _clk_ref
    clk_ref = 1'b0;
    forever #5ns clk_ref = ~clk_ref;  // 100 MHz reference
  end : _clk_ref

  initial begin : _clk_reg
    clk_reg = 1'b0;
    forever #5ns clk_reg = ~clk_reg;  // 100 MHz regfile clock
  end : _clk_reg

  logic arst_n = 1'b1;
  logic cfg_en = 1'b0, cfg_valid = 1'b0;
  logic [ 7:0] cfg_addr = '0;
  logic [15:0] cfg_di = '0;
  logic tx_rst = 1'b0, tx_pcs = 1'b0, rx_rst = 1'b0, rx_eqa = 1'b0, rx_pcs = 1'b0, rx_buf = 1'b0;
  logic [2:0] lb = 3'b000;
  logic txpd = 1'b1, rxpd = 1'b1, tx_ei = 1'b0, det = 1'b0, det_done, det_present;
  logic [2:0] tx_prbs = 3'b000, rx_prbs = 3'b000;
  logic prbs_cnt_rst = 1'b0;
  logic ei_det = 1'b0, comma_en = 1'b1, slide = 1'b0, mcomma = 1'b1, pcomma = 1'b1;
  logic rx_8en = 1'b1;
  logic we = 1'b0, en = 1'b0;
  logic [7:0] addr = '0;
  logic [15:0] di = '0, mask = 16'hFFFF;
  logic clk_pll, rcp_n, clk_rxo;
  logic [15:0] do_;
  logic rdy;
  logic txp, txn, txdone, rxdone, tx_err, aligned, realign, prbs_err, ei_o;
  logic [63:0] rxd;
  logic [7:0] rxk, rxnit, rxdisp, NC_rxc;
  logic [63:0] txd;
  logic [ 7:0] txk;

  // TX_CLK_I: PLL_CLK_O, stopped, or a clock of its own
  logic stop_tx = 1'b0, use_own = 1'b0, own_clk;
  real own_half = 17.0;

  /* verilator lint_off ZERODLY */
  initial begin : _own_clk
    own_clk = 1'b0;
    forever #(own_half * 1ns) own_clk = ~own_clk;
  end : _own_clk
  /* verilator lint_on ZERODLY */

  // continuous assignments, not always_comb: no procedure, so no order
  wire clk_tx = (use_own ? own_clk : clk_pll) & ~stop_tx;

  // the line: the TX pins after wd ns; cut: constant
  real wd = 2.0;
  logic rxp_w, rxn_w, cut = 1'b0;

  // A transport delay: each change of the TX pins wd later, in order. A
  // queue, one process, no fork: two changes in one time step arrive in
  // the order sent. If wd shrinks, the changes due earlier wait for the
  // last one queued, as on a shorter line (bits lost: a slip back).
  // Two queues, not one of a struct {t, v}: Icarus 14 has no unpacked
  // struct (a real field) and no queue of a packed struct. Not
  // rxp_w <= #(wd * 1ns) txp: XSIM 2026.1 dies on it here (double free).
  real        line_t[$];  // when each change arrives, ns
  logic [1:0] line_v[$];  // {P, N} at the change
  int         line_n;     // the queue's size, for the wait
  initial forever begin : _line_in
    real t;
    @(txp or txn);
    t = now_ns() + wd;
    if ((line_t.size() > 0) && (line_t[line_t.size()-1] > t)) t = line_t[line_t.size()-1];
    line_t.push_back(t);
    line_v.push_back({txp, txn});
    line_n++;
  end : _line_in
  /* verilator lint_off ZERODLY */
  initial begin : _line_out
    {rxp_w, rxn_w} = 2'b01;
    forever begin
      wait (line_n > 0);
      #((line_t[0] - now_ns()) * 1ns);
      {rxp_w, rxn_w} = line_v.pop_front();
      void'(line_t.pop_front());
      line_n--;
    end
  end : _line_out
  /* verilator lint_on ZERODLY */

  // the TX pin states (tx_drive in the BFM): P/N differential, 0/0
  // (electrical idle, TX not running), 1/1 only in power down; no X or Z.
  // Checked on each pin change; txpd may change in the same time step.
  real        txpd_t = 0.0, pins_bad_t = -1.0;
  int         n_pins_bad = 0;
  logic [1:0] pins_bad = 2'b00;
  initial forever begin
    @(txpd);
    txpd_t = now_ns();
  end
  initial forever begin
    @(txp or txn);
    if ((now_ns() > 0.0) && (((^{txp, txn}) === 1'bx) || (txp && txn && txpd && (txpd_t != now_ns())))) begin
      n_pins_bad++;
      if (pins_bad_t < 0.0) begin
        pins_bad_t = now_ns();
        pins_bad   = {txp, txn};
      end
    end
  end

  wire rxp = cut ? 1'b0 : rxp_w;
  wire rxn = cut ? 1'b1 : rxn_w;

  ccfpga_serdes #(
      .RX_DATAPATH_SEL  (2'(DP)),
      .TX_DATAPATH_SEL  (2'(DP)),
      .ALIGN_COMMA_WORD (2'b01),     // even lanes
      .RX_SLIDE_MODE    (2'(SLIDE))
  ) u_serdes (
      .clk_ref_i            (clk_ref),
      .clk_reg_i            (clk_reg),
      .clk_cfg_i            (clk_reg),
      .clk_core_tx_i        (clk_tx),
      .clk_core_rx_i        (clk_pll),
      .clk_core_rx_o        (clk_rxo),
      .reset_n_i            (arst_n),
      .reset_reg_n_i        (arst_n),
      .reset_core_tx_n_i    (rcp_n),
      .reset_core_rx_n_i    (rcp_n),
      .testmode_i           (1'b0),
      .scan_enable_i        (1'b0),
      .scan_in_i            (7'h0),
      .scan_out_o           (),
      .loopback_i           (lb),
      .pll_reset_i          (1'b0),
      .clk_core_pll_o       (clk_pll),
      .reset_core_pll_n_o   (rcp_n),
      .refclk_sel_o         (),
      .refclk_rterm_o       (),
      .RX_SERIO_P_B         (rxp),
      .RX_SERIO_N_B         (rxn),
      .TX_SERIO_P_B         (txp),
      .TX_SERIO_N_B         (txn),
      .regfile_we_i         (we),
      .regfile_en_i         (en),
      .regfile_addr_i       (addr),
      .regfile_mask_i       (mask),
      .regfile_di_i         (di),
      .regfile_do_o         (do_),
      .regfile_rdy_o        (rdy),
      .cfg_en_i             (cfg_en),
      .reset_cfg_i          (1'b0),
      .cfgfile_di_i         (cfg_di),
      .cfgfile_valid_i      (cfg_valid),
      .cfgfile_addr_i       (cfg_addr),
      .tx_reset_i           (tx_rst),
      .tx_pcs_reset_i       (tx_pcs),
      .tx_pma_reset_i       (1'b0),
      .tx_elec_idle_i       (tx_ei),
      .tx_detect_rx_i       (det),
      .tx_prbs_sel_i        (tx_prbs),
      .tx_prbs_force_err_i  (1'b0),
      .tx_powerdown_n_i     (txpd),
      .tx_data_i            (txd),
      .tx_char_is_k_i       (txk),
      .tx_polarity_i        (1'b0),
      .tx_8b10b_en_i        (1'b1),
      .tx_8b10b_bypass_i    ('0),
      .tx_char_dispmode_i   ('0),
      .tx_char_dispval_i    ('0),
      .tx_buf_err_o         (tx_err),
      .tx_resetdone_o       (txdone),
      .rx_detect_done_o     (det_done),
      .rx_present_o         (det_present),
      .TERM_SERIO_O         (),
      .rx_reset_i           (rx_rst),
      .rx_pma_reset_i       (1'b0),
      .rx_eqa_reset_i       (rx_eqa),
      .rx_cdr_reset_i       (1'b0),
      .rx_pcs_reset_i       (rx_pcs),
      .rx_buf_reset_i       (rx_buf),
      .rx_prbs_sel_i        (rx_prbs),
      .rx_prbs_cnt_reset_i  (prbs_cnt_rst),
      .rx_powerdown_n_i     (rxpd),
      .rx_en_ei_detector_i  (ei_det),
      .rx_comma_detect_en_i (comma_en),
      .rx_slide_i           (slide),
      .rx_polarity_i        (1'b0),
      .rx_8b10b_en_i        (rx_8en),
      .rx_8b10b_bypass_i    ('0),
      .rx_mcomma_align_i    (mcomma),
      .rx_pcomma_align_i    (pcomma),
      .rx_prbs_err_o        (prbs_err),
      .rx_data_o            (rxd),
      .rx_char_is_k_o       (rxk),
      .rx_char_is_comma_o   (NC_rxc),
      .rx_not_in_table_o    (rxnit),
      .rx_disp_err_o        (rxdisp),
      .rx_buf_err_o         (),
      .rx_byte_is_aligned_o (aligned),
      .rx_byte_realign_o    (realign),
      .rx_resetdone_o       (rxdone),
      .rx_ei_en_o           (ei_o)
  );

  //-----------------------------------------------------------------------
  // results
  //-----------------------------------------------------------------------
  int n_rules = 0, n_bad = 0;

  task rule(string name, bit ok, string got);
    n_rules++;
    if (!ok) begin
      n_bad++;
    end
    $display("TB_RULES: %s: %s (%s)", name, ok ? "PASS" : "FAIL", got);
  endtask

  //-----------------------------------------------------------------------
  // config file and regfile; lat: the clocks to REGFILE_RDY_O, counted
  // from the clock after the one REGFILE_EN_I rises for
  //-----------------------------------------------------------------------
  task cfgw(logic [7:0] a, logic [15:0] d);
    @(posedge clk_reg);
    cfg_en    <= 1'b1;
    cfg_addr  <= a;
    cfg_di    <= d;
    cfg_valid <= 1'b1;
    @(posedge clk_reg);
    cfg_valid <= 1'b0;
    @(posedge clk_reg);
    cfg_en <= 1'b0;
    repeat (2) @(posedge clk_reg);
  endtask

  int lat;
  logic [15:0] rv;

  task rf_wait_rdy();
    lat = 1;
    while (!rdy && lat < 400) begin
      @(posedge clk_reg);
      lat++;
    end
    rv = do_;
    repeat (2) @(posedge clk_reg);
  endtask

  task rd(logic [7:0] a);
    @(posedge clk_reg);
    addr <= a;
    en   <= 1'b1;
    we   <= 1'b0;
    @(posedge clk_reg);
    en <= 1'b0;
    rf_wait_rdy();
  endtask

  task wr(logic [7:0] a, logic [15:0] d, logic [15:0] m);
    @(posedge clk_reg);
    addr <= a;
    di   <= d;
    mask <= m;
    en   <= 1'b1;
    we   <= 1'b1;
    @(posedge clk_reg);
    en <= 1'b0;
    we <= 1'b0;
    rf_wait_rdy();
  endtask

  task wr_rd(logic [7:0] a, logic [15:0] d, logic [15:0] m, logic [15:0] want, string name);
    wr(a, d, m);
    rd(a);
    rule(name, rv == want, $sformatf("0x%02h reads 0x%04h, want 0x%04h", a, rv, want));
  endtask

  //-----------------------------------------------------------------------
  // TX data: 0 counter, a comma every cevery words in lane clane;
  // 1 constant txd_c / txk_c; 2 (rules_16) K28.5 and a count
  //-----------------------------------------------------------------------
  int tx_mode = 0, cevery = 4, clane = 1, txn_w = 0;
  logic [63:0] txd_c = '0;
  logic [ 7:0] txk_c = '0;

  initial begin : _tx
    logic [63:0] d;
    logic [ 7:0] k;
    txd = '0;
    txk = '0;
    forever begin
      @(posedge clk_tx);
      if (tx_mode == 1) begin
        d = txd_c;
        k = txk_c;
      end else if (tx_mode == 2) begin  // K28.5 in the even lanes, a count in the odd
        for (int b = 0; b < 8; b++) begin
          d[b*8+:8] = (b % 2 == 0) ? 8'hBC : 8'(txn_w * 8 + b);
          k[b]      = (b % 2 == 0);
        end
      end else begin
        d = '0;
        k = '0;
        for (int b = 0; b < 8; b++) begin
          d[b*8+:8] = 8'(txn_w * 8 + b);
        end
        if (txn_w % cevery == 0) begin
          d[clane*8+:8] = 8'hBC;
          k[clane]      = 1'b1;
        end
      end
      txd <= d;
      txk <= k;
      txn_w++;
    end
  end : _tx

  // RX_BYTE_REALIGN_O pulses
  int realigns = 0;
  initial
    forever begin : _realigns
      @(posedge clk_pll);
      if (realign === 1'b1) begin
        realigns++;
      end
    end : _realigns

  // the lane of the last comma out, -1: none yet
  int rx_comma_lane = -1;
  initial
    forever begin : _comma_lane
      @(posedge clk_pll);
      for (int b = 0; b < LANES; b++) begin
        if (rxk[b] && rxd[b*8+:8] == 8'hBC) begin
          rx_comma_lane = b;
        end
      end
    end : _comma_lane

  // a flag up, or t_ns gone (at a CLK_REF_I rise): one process, no fork
  task wait_aligned(input real t_ns);
    real t0;
    t0 = now_ns();
    while ((aligned !== 1'b1) && ((now_ns() - t0) < t_ns)) @(aligned or posedge clk_ref);
  endtask

  task wait_tx_err(input real t_ns);
    real t0;
    t0 = now_ns();
    while ((tx_err !== 1'b1) && ((now_ns() - t0) < t_ns)) @(tx_err or posedge clk_ref);
  endtask

  // PLL_CLK_O clocks from now (a port's release) to the rise of done,
  // once it fell: done falls some clocks after the port rose
  int pll_n;
  task clks_to_tx_done();
    bit fell;
    fell  = (txdone !== 1'b1);
    pll_n = 0;
    while (!(fell && txdone === 1'b1) && pll_n < 100000) begin
      @(posedge clk_pll);
      pll_n++;
      fell = fell || (txdone !== 1'b1);
    end
  endtask

  task clks_to_rx_done();
    bit fell;
    fell  = (rxdone !== 1'b1);
    pll_n = 0;
    while (!(fell && rxdone === 1'b1) && pll_n < 100000) begin
      @(posedge clk_pll);
      pll_n++;
      fell = fell || (rxdone !== 1'b1);
    end
  endtask

  real t0, per;

  task pll_period();
    @(posedge clk_pll);
    t0 = now_ns();
    repeat (20) @(posedge clk_pll);
    per = (now_ns() - t0) / 20.0;
  endtask

  // the first K28.5 on the line after 20 UI low: 0 RD-, 1 RD+, -1 none
  // in 40 bits (a part symbol may come first)
  int first_k;
  task line_symbol();
    int z;
    logic [39:0] b;
    z = 0;
    while (z < 20) begin
      #(UI * 1ns);
      z = (txp === 1'b0) ? z + 1 : 0;
    end
    @(posedge txp);
    #(UI / 2.0 * 1ns);
    for (int i = 0; i < 40; i++) begin
      b[i] = txp;
      #(UI * 1ns);
    end
    first_k = -1;
    for (int i = 30; i >= 0; i--) begin
      if (b[i+:10] == 10'b0101111100) begin  // a first: 001111 1010
        first_k = 0;
      end
      if (b[i+:10] == 10'b1010000011) begin  // 110000 0101
        first_k = 1;
      end
    end
  endtask

  //=======================================================================
  // DP = 3, SLIDE = 0: the 64-bit rules
  //=======================================================================
  task rules_regfile();
    // reset values, ready latency, a write's DO
    rd(8'h50);
    rule("PLL_CFG0 reset", rv == 16'h0864, $sformatf("0x%04h", rv));
    rule("REGFILE_RDY_O, a config register: 5 clocks", lat == 5, $sformatf("%0d", lat));
    rd(8'h55);
    rule("REGFILE_RDY_O, PLL status: 16 clocks", lat == 16, $sformatf("%0d", lat));
    rd(8'h47);
    rule("REGFILE_RDY_O, no register: 3 clocks", lat == 3, $sformatf("%0d", lat));
    wr(8'h51, CFG1, 16'hFFFF);
    rule("REGFILE_DO_O on a write: the register", rv == CFG1, $sformatf("0x%04h", rv));
    // busy: a second rise 2 clocks after the first is lost
    @(posedge clk_reg);
    addr <= 8'h50;
    en   <= 1'b1;
    we   <= 1'b0;
    @(posedge clk_reg);
    en <= 1'b0;
    @(posedge clk_reg);
    addr <= 8'h51;
    en   <= 1'b1;
    @(posedge clk_reg);
    en <= 1'b0;
    begin
      int n;
      n = 0;
      repeat (40) begin
        @(posedge clk_reg);
        n += int'(rdy);
      end
      rule("REGFILE_EN_I rise while busy: lost", n == 1, $sformatf("%0d ready", n));
    end
    // PLL_CFG0 [9:1]: only a write that leaves the PLL off
    wr_rd(8'h50, 16'h0FFE, 16'hFFFF, 16'h0FFE, "PLL_CFG0, PLL off: [9:1] written");
    wr_rd(8'h50, 16'h0000, 16'hFFFF, 16'h0000, "PLL_CFG0, PLL off: [9:1] cleared");
    wr_rd(8'h50, 16'h0C03, 16'hFFFF, 16'h0C01, "PLL_CFG0, a write that turns it on: [9:1] kept");
    wr_rd(8'h50, 16'h0FFF, 16'hFFFF, 16'h0C01, "PLL_CFG0, on: [9:1] kept");
    wr_rd(8'h50, 16'h0002, 16'h0FFE, 16'h0001, "PLL_CFG0, on, bit 0 masked: [9:1] kept");
    wr_rd(8'h50, 16'h0C02, 16'hFFFF, 16'h0C02,
          "PLL_CFG0, a write that turns it off: [9:1] written");
    // PLL_CONFIG_SEL = 0 (the C01 above): PLL_CLK_O 40 ns at 16FA, 4 Gb/s
    wr(8'h50, 16'h0C00, 16'hFFFF);
    wr(8'h50, 16'h0C61, 16'hFFFF);  // on, CONFIG_SEL 0
    #2000ns;
    pll_period();
    rule("PLL_CONFIG_SEL = 0: N = 20, PLL_CLK_O takes M3", (per > 39.9) && (per < 40.1), $sformatf(
         "%0.2f ns", per));
    wr(8'h50, 16'h0C62, 16'hFFFF);  // off, CONFIG_SEL 1
    wr_rd(8'h51, 16'h06FA, 16'hFFFF, 16'h06FA, "PLL_CFG1 with the PLL off: written");
    wr(8'h50, 16'h0E62, 16'hFFFF);  // REF_BYPASS, then on
    wr(8'h50, 16'h0E63, 16'hFFFF);
    #200ns;
    pll_period();
    rule("PLL_REF_BYPASS: PLL_CLK_O = f_ref / (M3 M4), before the lock",
         (per > 19.9) && (per < 20.1), $sformatf("%0.2f ns", per));
    wr(8'h50, 16'h0C62, 16'hFFFF);
    wr(8'h51, CFG1, 16'hFFFF);
    wr(8'h50, 16'h0C63, 16'hFFFF);  // on, CONFIG_SEL 1
    wr_rd(8'h51, 16'h06FA, 16'hFFFF, CFG1, "PLL_CFG1 with the PLL on: kept");
    #2000ns;
    pll_period();
    rule("PLL_CONFIG_SEL = 1: PLL_CFG1 sets the rate", (per > 31.9) && (per < 32.1), $sformatf(
         "%0.2f ns", per));
    // clock correction on: MIN/MAX and the sequence kept
    wr_rd(8'h25, 16'h2782, 16'hFFFF, 16'h2782, "RX_BUF_CFG, RX_CLKCOR_USE on");
    wr_rd(8'h25, 16'h1E52, 16'hFFFF, 16'h2782, "RX_BUF_CFG with clock correction: MIN/MAX kept");
    wr_rd(8'h26, 16'h0055, 16'hFFFF, 16'h01F7, "RX_CLKCOR_SEQ with clock correction: kept");
    wr_rd(8'h25, 16'h1E50, 16'hFFFF, 16'h2780, "RX_BUF_CFG: RX_CLKCOR_USE off, MIN/MAX kept");
    wr_rd(8'h25, 16'h1E50, 16'hFFFF, 16'h1E50, "RX_BUF_CFG without clock correction: written");
    wr(8'h25, 16'h2780, 16'hFFFF);
  endtask

  task rules_reset();
    // the counts from the release of the port, PLL_CLK_O clocks
    tx_rst = 1'b1;
    #200ns;
    rule("TX_RESET_I held: TX_RESET_DONE_O low", txdone === 1'b0, $sformatf("%b", txdone));
    @(negedge clk_pll);
    tx_rst = 1'b0;
    clks_to_tx_done();
    rule("TX_RESET_I: done 16 clocks after", pll_n == 16, $sformatf("%0d", pll_n));
    #1000ns;
    @(negedge clk_pll);
    tx_pcs = 1'b1;
    @(negedge clk_pll);
    tx_pcs = 1'b0;
    clks_to_tx_done();
    rule("TX_PCS_RESET_I: done 12 clocks after", pll_n == 12, $sformatf("%0d", pll_n));
    wait_aligned(20000.0);
    #1000ns;
    @(negedge clk_pll);
    rx_buf = 1'b1;
    @(negedge clk_pll);
    rx_buf = 1'b0;
    clks_to_rx_done();
    rule("RX_BUF_RESET_I: done 12 clocks after", pll_n == 12, $sformatf("%0d", pll_n));
    #1000ns;
    @(negedge clk_pll);
    rx_pcs = 1'b1;
    @(negedge clk_pll);
    rx_pcs = 1'b0;
    clks_to_rx_done();
    rule("RX_PCS_RESET_I: done 16 clocks after", pll_n == 16, $sformatf("%0d", pll_n));
    rule("RX_PCS_RESET_I: comma alignment starts over", aligned === 1'b0, $sformatf("%b", aligned));
    wait_aligned(20000.0);
    #1000ns;
    @(negedge clk_pll);
    rx_eqa = 1'b1;
    @(negedge clk_pll);
    rx_eqa = 1'b0;
    #300ns;
    rule("RX_EQA_RESET_I: done drops", rxdone === 1'b0, $sformatf("%b", rxdone));
    wait (rxdone === 1'b1);
    wait_aligned(20000.0);
    #1000ns;
    // power down: done stays
    txpd = 1'b0;
    rxpd = 1'b0;
    #2000ns;
    rule("TX/RX_POWER_DOWN_N_I: done stays", (txdone === 1'b1) && (rxdone === 1'b1), $sformatf(
         "%b%b", txdone, rxdone));
    rule("TX_POWERDOWN_N_I low: 1/1 on the TX pins, no Z", (txp === 1'b1) && (txn === 1'b1), $sformatf(
         "%b%b", txp, txn));
    txpd = 1'b1;
    rxpd = 1'b1;
    // near-end PCS loopback: no CDR lock wait; the line cut
    cut  = 1'b1;
    lb   = 3'b001;
    #200ns;
    @(negedge clk_pll);
    rx_rst = 1'b1;
    @(negedge clk_pll);
    rx_rst = 1'b0;
    clks_to_rx_done();
    rule("RX_RESET_I, LOOPBACK_I = 001: done 28 clocks after, no CDR wait", pll_n == 28, $sformatf(
         "%0d", pll_n));
    wait_aligned(30000.0);
    rule("LOOPBACK_I = 001: near-end loopback", aligned === 1'b1, $sformatf("%b", aligned));
    lb = 3'b010;  // TX_PMA_LOOPBACK = 0: no loopback
    rx_rst = 1'b1;
    #100ns;
    rx_rst = 1'b0;
    #20000ns;
    rule("LOOPBACK_I = 010, TX_PMA_LOOPBACK = 0: no loopback", aligned === 1'b0, $sformatf(
         "aligned %b", aligned));
    lb = 3'b000;
    cut = 1'b0;
    rx_rst = 1'b1;
    #100ns;
    rx_rst = 1'b0;
    clks_to_rx_done();
    wait_aligned(30000.0);
  endtask

  task rules_tx();
    // RD+ after a TX reset: K28.5 as 110000 0101
    tx_mode = 1;
    txd_c   = {8{8'hBC}};
    txk_c   = 8'hFF;
    tx_rst  = 1'b1;
    #200ns;
    tx_rst = 1'b0;
    line_symbol();  // the zeros of the reset, then the first symbol
    rule("TX running disparity starts RD+", first_k == 1, $sformatf(
         "the first K28.5: %0d (1 RD+, 0 RD-)", first_k));
    tx_mode = 0;
    wait_aligned(30000.0);
    #1000ns;
    // a stopped TX_CLK_I: zeros, no TX_BUF_ERR_O, then the data again
    @(negedge clk_pll);
    stop_tx = 1'b1;
    #2000ns;
    begin
      int ones;
      ones = 0;
      repeat (100) begin
        #(UI * 1ns);
        ones += int'(txp);
      end
      rule("TX_CLK_I stopped: zero symbols", ones == 0, $sformatf("%0d ones in 100 UI", ones));
    end
    @(negedge clk_pll);
    stop_tx = 1'b0;
    #3000ns;
    rule("TX_CLK_I stopped: no TX_BUF_ERR_O", tx_err === 1'b0, $sformatf("%b", tx_err));
    rule("TX_CLK_I back: the data again", aligned === 1'b1, $sformatf("aligned %b", aligned));
    // a slow TX_CLK_I: underflow, sticky, zeros until TX_PCS_RESET_I
    own_half = 17.0;
    use_own  = 1'b1;
    wait_tx_err(20000.0);
    use_own = 1'b0;
    #2000ns;
    begin
      int ones;
      ones = 0;
      repeat (100) begin
        #(UI * 1ns);
        ones += int'(txp);
      end
      rule("TX underflow: TX_BUF_ERR_O sticky, zero symbols", (tx_err === 1'b1) && (ones == 0),
           $sformatf("err %b, %0d ones", tx_err, ones));
    end
    tx_pcs = 1'b1;
    #100ns;
    tx_pcs = 1'b0;
    #1500ns;
    rule("TX_PCS_RESET_I clears TX_BUF_ERR_O", tx_err === 1'b0, $sformatf("%b", tx_err));
    // a fast TX_CLK_I: overflow
    own_half = 15.0;
    use_own  = 1'b1;
    wait_tx_err(40000.0);
    use_own = 1'b0;
    rule("TX overflow: TX_BUF_ERR_O", tx_err === 1'b1, $sformatf("%b", tx_err));
    tx_pcs = 1'b1;
    #100ns;
    tx_pcs = 1'b0;
    #1500ns;
    wait_aligned(30000.0);
  endtask

  task rules_align();
    int r0, l0;
    logic [63:0] d0;
    logic [ 7:0] k0;
    // acquisition from an RX reset: 17 commas at least; ALIGN_COMMA_WORD
    // 01 with the comma in lane 1: one symbol dropped, then lane 0
    clane = 1;
    #500ns;
    r0 = realigns;
    rx_rst = 1'b1;
    #100ns;
    rx_rst = 1'b0;
    clks_to_rx_done();
    t0 = now_ns();
    // decoded data holds until aligned, K / NOT_IN_TABLE / DISP_ERR low
    // (after the RX buffer's old words)
    #1000ns;
    @(posedge clk_pll);
    d0 = rxd;
    k0 = rxk | rxnit | rxdisp;
    begin
      bit moved;
      moved = 1'b0;
      while (aligned !== 1'b1 && (now_ns() - t0) < 30000.0) begin
        @(posedge clk_pll);
        if (aligned !== 1'b1 && (rxd !== d0 || (rxk | rxnit | rxdisp) != 8'h00)) begin
          moved = 1'b1;
        end
      end
      rule("decoded data holds until aligned", !moved, $sformatf("moved %b", moved));
    end
    rule("aligned after 16 commas or more", (now_ns() - t0) > 64 * 32.0, $sformatf(
         "%0.0f ns", now_ns() - t0));
    rule("ALIGN_COMMA_WORD 01, comma in lane 1: an RX_BYTE_REALIGN_O at most", realigns - r0 <= 1,
         $sformatf("%0d", realigns - r0));
    #500ns;
    rule("ALIGN_COMMA_WORD 01: the comma in an even lane", (rx_comma_lane % 2) == 0, $sformatf(
         "lane %0d", rx_comma_lane));
    // locked: a comma in another lane is not corrected
    r0    = realigns;
    clane = 2;
    #3000ns;
    l0 = rx_comma_lane;
    rule("locked: a comma in a wrong lane is not corrected",
         (aligned === 1'b1) && (realigns == r0) && (l0 % 2 == 1), $sformatf(
         "aligned %b, %0d realigns, lane %0d", aligned, realigns - r0, l0));
    // locked: a comma a bit off realigns
    wd = wd + UI;
    #2000ns;
    rule("locked: a comma off the boundary realigns", realigns - r0 == 1, $sformatf(
         "%0d realigns", realigns - r0));
    wait_aligned(30000.0);
    rule("realigned", aligned === 1'b1, $sformatf("%b", aligned));
    // RX_COMMA_DETECT_EN_I low: RX_BYTE_IS_ALIGNED_O low
    comma_en = 1'b0;
    #1000ns;
    rule("RX_COMMA_DETECT_EN_I low: not aligned", aligned === 1'b0, $sformatf("%b", aligned));
    comma_en = 1'b1;
    wait_aligned(30000.0);
    #500ns;
    // align enables low: frozen, still aligned; a slip is not followed
    mcomma = 1'b0;
    pcomma = 1'b0;
    r0     = realigns;
    #500ns;
    wd = wd + UI;
    #3000ns;
    rule("RX_M/PCOMMA_ALIGN_I low: alignment frozen", (aligned === 1'b1) && (realigns == r0),
         $sformatf("aligned %b, %0d realigns", aligned, realigns - r0));
    mcomma = 1'b1;
    pcomma = 1'b1;
    wait_aligned(30000.0);
    #3000ns;
  endtask

  task rules_prbs();
    int r0;
    // PRBS checker on: the aligner holds; 101 to 111: no checker
    r0      = realigns;
    rx_prbs = 3'b001;
    tx_prbs = 3'b001;
    #2000ns;
    rule("PRBS checker on: comma alignment holds", (realigns == r0) && (aligned === 1'b1),
         $sformatf("aligned %b, %0d realigns", aligned, realigns - r0));
    rx_prbs = 3'b101;
    #2000ns;
    begin
      int n;
      n = 0;
      repeat (50) begin
        @(posedge clk_pll);
        n += int'(prbs_err);
      end
      rule("RX_PRBS_SEL_I 101: no checker", n == 0, $sformatf("%0d error words", n));
    end
    rx_prbs = 3'b000;
    tx_prbs = 3'b000;
    #2000ns;
    wait_aligned(30000.0);
  endtask

  task rules_misc();
    // RX_CLK_O: high for half a symbol at most
    begin
      real th;
      @(posedge clk_rxo);
      th = now_ns();
      @(negedge clk_rxo);
      th = now_ns() - th;
      rule("RX_CLK_O: a narrow pulse each word", th < 6.0 * UI, $sformatf("high %0.2f ns", th));
    end
    // electrical idle: RX_EI_EN_O, with the detector on (DS)
    ei_det = 1'b1;
    tx_ei  = 1'b1;
    #3000ns;
    rule("DS: TX_ELEC_IDLE_I: RX_EI_EN_O at the default RX_EI_BW_SEL", ei_o === 1'b1, $sformatf(
         "%b", ei_o));
    rule("TX_ELEC_IDLE_I: 0/0 on the TX pins, no X", (txp === 1'b0) && (txn === 1'b0), $sformatf(
         "%b%b", txp, txn));
    tx_ei = 1'b0;
    #3000ns;
    rule("RX_EI_EN_O low again with data", ei_o === 1'b0, $sformatf("%b", ei_o));
    ei_det = 1'b0;
    // receiver detection, as the vendor model: 112 CLK_REF_I clocks plus
    // the syncs (2 core TX, 2 ref, 3 core RX clocks); DONE and PRESENT hold
    // after the request drops; the next request clears DONE
    begin
      real  td;
      logic p;
      @(negedge clk_ref);
      det = 1'b1;
      td  = now_ns();
      @(posedge det_done);
      td = now_ns() - td;
      p  = det_present;
      rule("TX_DETECT_RX_I: RX_DETECT_DONE_O after 112 CLK_REF_I clocks and the syncs",
           (td > 1140.0) && (td < 1400.0), $sformatf("%0.1f ns", td));
      rule("TX_DETECT_RX_I: a far end present (BHV_RX_PRESENT)", p === 1'b1, $sformatf("%b", p));
      det = 1'b0;
      #200ns;
      rule("TX_DETECT_RX_I low: both hold", {det_done, det_present} === {1'b1, p}, $sformatf(
           "%b%b", det_done, det_present));
      det = 1'b1;
      #200ns;
      rule("TX_DETECT_RX_I again: DONE clears, PRESENT holds", {det_done, det_present} === {1'b0, p},
           $sformatf("%b%b", det_done, det_present));
      det = 1'b0;
      wait (det_done === 1'b1);
    end
  endtask

  //=======================================================================
  // DP = 0: 16-bit TX lane rotation; PRBS-31 does not lock at 16 bits
  //=======================================================================
  task rules_16();
    int q  [$];
    bit ok;
    // even lanes K28.5, odd lanes counting: the odd lane sent tells the
    // quarter of TX_DATA_I
    tx_mode = 2;
    wait_aligned(30000.0);
    #1000ns;
    repeat (8) begin
      @(posedge clk_pll);
      if (rxk[0]) begin
        q.push_back(int'(rxd[15:8]) % 8);
      end
    end
    ok = (q.size() == 8);
    for (int i = 1; i < q.size(); i++) begin
      if (q[i] != (q[i-1] + 2) % 8) begin
        ok = 1'b0;
      end
    end
    rule("16 bits: the line takes TX_DATA_I's quarters in turn", ok, $sformatf("%0d words", q.size()
         ));
    rx_prbs = 3'b100;
    tx_prbs = 3'b100;
    #5000ns;
    begin
      int n;
      n = 0;
      repeat (50) begin
        @(posedge clk_pll);
        n += int'(prbs_err);
      end
      rule("16 bits: PRBS-31 does not lock", n == 0, $sformatf("%0d error words", n));
    end
  endtask

  //=======================================================================
  // SLIDE = 1, 2, 3: RX_SLIDE_I. No automatic alignment; decoded data
  // holds: the decoder off, raw symbols. A strobe slips a bit if 16 words
  // passed since the last, and drops a symbol each time. The comma's bit
  // in the raw word tells: a slip moves it a bit, a drop a symbol.
  //=======================================================================
  int at;  // the comma's bit in the raw word, -1: none

  // a comma each word: it starts at the same bit in each, maybe across
  // two words
  logic [159:0] w2;  // this word over the last
  task comma_at();
    for (int i = 0; i < 8; i++) begin
      w2[80+i*10+:10] = {rxdisp[i], rxk[i], rxd[i*8+:8]};
    end
    at = -1;
    for (int b = 0; b < 80; b++) begin
      if (at < 0 && (w2[b+:10] == 10'b0101111100 || w2[b+:10] == 10'b1010000011)) begin
        at = b;
      end
    end
  endtask

  // the comma's bit, 30 words after a strobe or now
  task settle_at();
    repeat (30) begin
      @(posedge clk_pll);
      w2[79:0] = w2[159:80];
      for (int i = 0; i < 8; i++) begin
        w2[80+i*10+:10] = {rxdisp[i], rxk[i], rxd[i*8+:8]};
      end
    end
    comma_at();
  endtask

  task strobe();
    @(posedge clk_pll);
    slide <= 1'b1;
    @(posedge clk_pll);
    slide <= 1'b0;
  endtask

  // how far the comma moved to the word start: a bit slip 1 (the
  // boundary a bit later), a dropped symbol 10
  function int moved(int a, int b);
    int d;
    d = (a - b + 80) % 80;
    return (d > 40) ? d - 80 : d;
  endfunction

  task rules_slide();
    int a0, a1, d1, d2;
    rx_8en = 1'b0;
    cevery = 1;
    clane  = 0;
    #3000ns;
    rule("slide mode: no automatic alignment", aligned === 1'b0, $sformatf("%b", aligned));
    settle_at();
    a0 = at;
    strobe();
    settle_at();
    a1 = at;
    d1 = moved(a0, a1);
    // two strobes 8 clocks apart: a second bit slip waits 16 words
    strobe();
    repeat (8) @(posedge clk_pll);
    strobe();
    settle_at();
    d2 = moved(a1, at);
    if (SLIDE == 1) begin
      rule("RX_SLIDE_MODE 1: a strobe slips a bit", d1 == 1, $sformatf("bit %0d to %0d", a0, a1));
      rule("RX_SLIDE_MODE 1: one slip in 16 words", d2 == 1, $sformatf("moved %0d", d2));
    end else if (SLIDE == 2) begin
      rule("RX_SLIDE_MODE 2: a strobe drops a symbol", d1 == 10, $sformatf("bit %0d to %0d", a0, a1
           ));
      rule("RX_SLIDE_MODE 2: each strobe drops one", d2 == 20, $sformatf("moved %0d", d2));
    end else begin
      rule("RX_SLIDE_MODE 3: a strobe slips a bit and drops a symbol", d1 == 11, $sformatf(
           "bit %0d to %0d", a0, a1));
    end
  endtask

  //=======================================================================
  initial begin
    #10ns arst_n = 1'b0;
    #90ns arst_n = 1'b1;
    #50ns;
    cfgw(8'h5C, 16'h0001);  // SerDes enable
    rx_rst = 1'b1;
    if (DP == 3 && SLIDE == 0) begin
      rules_regfile();
    end else begin
      wr(8'h51, CFG1, 16'hFFFF);
      wr(8'h50, 16'h0C62, 16'hFFFF);
      wr(8'h50, 16'h0C63, 16'hFFFF);
    end
    wait (txdone === 1'b1);
    #200ns;
    rx_rst = 1'b0;
    if (DP == 3 && SLIDE == 0) begin
      wait_aligned(60000.0);
      rule("aligned at start", aligned === 1'b1, $sformatf("%b", aligned));
      rules_reset();
      rules_tx();
      rules_align();
      rules_prbs();
      rules_misc();
    end else if (SLIDE != 0) begin
      wait (rxdone === 1'b1);
      rules_slide();
    end else begin
      rules_16();
    end
    rule("TX pins: P/N, 0/0, or 1/1 in power down; no X or Z", n_pins_bad == 0,
         (n_pins_bad == 0) ? "0 bad" : $sformatf("%0d bad, the first %b/%b at %0.3f ns", n_pins_bad, pins_bad[1], pins_bad[0], pins_bad_t));
    $display("TB_RULES: DP %0d, SLIDE %0d: %0d rules, %0d failed: %s", DP, SLIDE, n_rules, n_bad,
             (n_bad == 0) ? "PASS" : "FAIL");
    $finish;
  end

  initial begin
    #2ms;
    $display("TB_RULES: timeout: FAIL");
    $finish;
  end

`ifdef WAVES
  // make waves: the waveform for WaveCrux, tb_rules.fst
  initial begin
    $dumpfile("tb_rules.fst");
    $dumpvars(0, tb_rules);
  end
`endif

endmodule : tb_rules

// -----------------------------------------------------------------------------
// Project:     openSERDES_BFM
// Description: open-source SerDes BFM
// -----------------------------------------------------------------------------
