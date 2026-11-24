// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// SerDes BFM across a frequency offset: two BFMs, A's TX to B's RX, each on
// its own 100 MHz reference, B's +ppm=N slower (negative: faster), at
// 2.5 Gb/s and 64 bits. A sends tb_modes' counter stream (a K28.5 every 16
// words, lane 0); B checks it byte for byte. Clock correction is off
// (RX_CLKCOR_USE = 0), as a PCIe endpoint has it (../README.md, RX buffer
// and clock correction). +rxclk= picks B's fabric clock:
//   rec    B's recovered clock (RX_CLK_O), the far end's rate: the RX
//          buffer stays put at any offset; the CDR must track it. PASS:
//          every byte right, no RX_BUF_ERR_O, no realignment, no stop
//   local  B's own PLL clock (CLK_CORE_PLL_O): the buffer drifts at the
//          offset, so it must over- or underflow. PASS: RX_BUF_ERR_O comes,
//          by the time the buffer's slack allows (its time is printed)
// +run_us=N  the run (default 400 us). CDR_MODEL=ACCURATE: the only receiver
// that tracks a frequency offset.
//==========================================================================
module tb_ppm;

  localparam int LANES = 8;
  localparam logic [15:0] PLL_CFG1 = 16'h16FA;  // 2.5 Gb/s, 64 bits (tb_modes)

  logic clk_ref_a, clk_ref_b, clk_reg, arst_n;
  logic clk_tx_a, clk_pll_b, clk_rx_b, clk_rx_b_o, clk_rx_a_o;
  logic rst_core_a_n, rst_core_b_n;
  logic a_txp, a_txn, b_txp, b_txn;
  logic serdes_reset;
  logic reg_en, reg_we, cfg_en;
  logic [7:0] reg_addr;
  logic [15:0] reg_data, rf_do;
  logic rf_rdy;
  logic [63:0] tx_d, rx_d;
  logic [7:0] tx_k, rx_k, rx_nit, rx_disp;
  logic a_tx_ready, b_rx_ready, b_aligned, b_realign, b_buf_err, a_tx_err;

  real ppm = 300.0;
  bit  use_local = 1'b0;
  int  run_us = 400;
  int  errors = 0;

  initial begin : _clk_ref_a
    clk_ref_a = 1'b0;
    forever #5ns clk_ref_a = ~clk_ref_a;  // 100 MHz
  end : _clk_ref_a

  // Edge k at k half periods from time 0: each edge rounds to the time
  // precision on its own, so the offset builds up at any precision
  // (openCologne 7.SerDes tb_link_ppm)
  initial begin : _clk_ref_b
    longint k;
    real    half_ns;
    string  s;
    void'($value$plusargs("ppm=%f", ppm));
    if ($value$plusargs("rxclk=%s", s)) begin
      use_local = (s == "local");
    end
    void'($value$plusargs("run_us=%d", run_us));
    half_ns   = 5.0 * (1.0 + ppm * 1.0e-6);
    clk_ref_b = 1'b0;
    for (k = 1; ; k++) begin
      /* verilator lint_off ZERODLY */  // never 0: k grows each edge
      #((k * half_ns) * 1ns - $realtime);
      /* verilator lint_on ZERODLY */
      clk_ref_b = ~clk_ref_b;
    end
  end : _clk_ref_b

  initial begin : _clk_reg
    clk_reg = 1'b0;
    forever #50ns clk_reg = ~clk_reg;  // 10 MHz regfile clock
  end : _clk_reg

  assign clk_rx_b = use_local ? clk_pll_b : clk_rx_b_o;

  // A: the transmitter (its RX takes B's TX, unchecked)
  ccfpga_serdes #(
      .RX_DATAPATH_SEL(2'd3),
      .TX_DATAPATH_SEL(2'd3)
  ) u_a (
      .clk_ref_i            (clk_ref_a),
      .clk_reg_i            (clk_reg),
      .clk_cfg_i            (clk_reg),
      .clk_core_tx_i        (clk_tx_a),
      .clk_core_rx_i        (clk_rx_a_o),
      .clk_core_rx_o        (clk_rx_a_o),
      .reset_n_i            (arst_n),
      .reset_reg_n_i        (arst_n),
      .reset_core_tx_n_i    (rst_core_a_n),
      .reset_core_rx_n_i    (rst_core_a_n),
      .testmode_i           (1'b0),
      .scan_enable_i        (1'b0),
      .scan_in_i            (7'h0),
      .scan_out_o           (),
      .loopback_i           (3'b000),
      .pll_reset_i          (1'b0),
      .clk_core_pll_o       (clk_tx_a),
      .reset_core_pll_n_o   (rst_core_a_n),
      .refclk_sel_o         (),
      .refclk_rterm_o       (),
      .RX_SERIO_P_B         (b_txp),
      .RX_SERIO_N_B         (b_txn),
      .TX_SERIO_P_B         (a_txp),
      .TX_SERIO_N_B         (a_txn),
      .regfile_we_i         (reg_we),
      .regfile_en_i         (reg_en),
      .regfile_addr_i       (reg_addr),
      .regfile_mask_i       (16'hFFFF),
      .regfile_di_i         (reg_data),
      .regfile_do_o         (rf_do),
      .regfile_rdy_o        (rf_rdy),
      .cfg_en_i             (cfg_en),
      .reset_cfg_i          (1'b0),
      .cfgfile_di_i         (reg_data),
      .cfgfile_valid_i      (cfg_en),
      .cfgfile_addr_i       (reg_addr),
      .tx_reset_i           (serdes_reset),
      .tx_pcs_reset_i       (1'b0),
      .tx_pma_reset_i       (1'b0),
      .tx_elec_idle_i       (1'b0),
      .tx_detect_rx_i       (1'b0),
      .tx_prbs_sel_i        (3'b000),
      .tx_prbs_force_err_i  (1'b0),
      .tx_powerdown_n_i     (1'b1),
      .tx_data_i            (tx_d),
      .tx_char_is_k_i       (tx_k),
      .tx_polarity_i        (1'b0),
      .tx_8b10b_en_i        (1'b1),
      .tx_8b10b_bypass_i    ('0),
      .tx_char_dispmode_i   ('0),
      .tx_char_dispval_i    ('0),
      .tx_buf_err_o         (a_tx_err),
      .tx_resetdone_o       (a_tx_ready),
      .rx_detect_done_o     (),
      .rx_present_o         (),
      .TERM_SERIO_O         (),
      .rx_reset_i           (serdes_reset),
      .rx_pma_reset_i       (1'b0),
      .rx_eqa_reset_i       (1'b0),
      .rx_cdr_reset_i       (1'b0),
      .rx_pcs_reset_i       (1'b0),
      .rx_buf_reset_i       (1'b0),
      .rx_prbs_sel_i        (3'b000),
      .rx_prbs_cnt_reset_i  (1'b0),
      .rx_powerdown_n_i     (1'b1),
      .rx_en_ei_detector_i  (1'b0),
      .rx_comma_detect_en_i (1'b1),
      .rx_slide_i           (1'b0),
      .rx_polarity_i        (1'b0),
      .rx_8b10b_en_i        (1'b1),
      .rx_8b10b_bypass_i    ('0),
      .rx_mcomma_align_i    (1'b1),
      .rx_pcomma_align_i    (1'b1),
      .rx_prbs_err_o        (),
      .rx_data_o            (),
      .rx_char_is_k_o       (),
      .rx_char_is_comma_o   (),
      .rx_not_in_table_o    (),
      .rx_disp_err_o        (),
      .rx_buf_err_o         (),
      .rx_byte_is_aligned_o (),
      .rx_byte_realign_o    (),
      .rx_resetdone_o       (),
      .rx_ei_en_o           ()
  );

  // B: the receiver under test (its TX idles, to A's RX)
  ccfpga_serdes #(
      .RX_DATAPATH_SEL(2'd3),
      .TX_DATAPATH_SEL(2'd3)
  ) u_b (
      .clk_ref_i            (clk_ref_b),
      .clk_reg_i            (clk_reg),
      .clk_cfg_i            (clk_reg),
      .clk_core_tx_i        (clk_pll_b),
      .clk_core_rx_i        (clk_rx_b),
      .clk_core_rx_o        (clk_rx_b_o),
      .reset_n_i            (arst_n),
      .reset_reg_n_i        (arst_n),
      .reset_core_tx_n_i    (rst_core_b_n),
      .reset_core_rx_n_i    (rst_core_b_n),
      .testmode_i           (1'b0),
      .scan_enable_i        (1'b0),
      .scan_in_i            (7'h0),
      .scan_out_o           (),
      .loopback_i           (3'b000),
      .pll_reset_i          (1'b0),
      .clk_core_pll_o       (clk_pll_b),
      .reset_core_pll_n_o   (rst_core_b_n),
      .refclk_sel_o         (),
      .refclk_rterm_o       (),
      .RX_SERIO_P_B         (a_txp),
      .RX_SERIO_N_B         (a_txn),
      .TX_SERIO_P_B         (b_txp),
      .TX_SERIO_N_B         (b_txn),
      .regfile_we_i         (reg_we),
      .regfile_en_i         (reg_en),
      .regfile_addr_i       (reg_addr),
      .regfile_mask_i       (16'hFFFF),
      .regfile_di_i         (reg_data),
      .regfile_do_o         (),
      .regfile_rdy_o        (),
      .cfg_en_i             (cfg_en),
      .reset_cfg_i          (1'b0),
      .cfgfile_di_i         (reg_data),
      .cfgfile_valid_i      (cfg_en),
      .cfgfile_addr_i       (reg_addr),
      .tx_reset_i           (serdes_reset),
      .tx_pcs_reset_i       (1'b0),
      .tx_pma_reset_i       (1'b0),
      .tx_elec_idle_i       (1'b0),
      .tx_detect_rx_i       (1'b0),
      .tx_prbs_sel_i        (3'b000),
      .tx_prbs_force_err_i  (1'b0),
      .tx_powerdown_n_i     (1'b1),
      .tx_data_i            (64'h0000_0000_0000_00BC),
      .tx_char_is_k_i       (8'h01),
      .tx_polarity_i        (1'b0),
      .tx_8b10b_en_i        (1'b1),
      .tx_8b10b_bypass_i    ('0),
      .tx_char_dispmode_i   ('0),
      .tx_char_dispval_i    ('0),
      .tx_buf_err_o         (),
      .tx_resetdone_o       (),
      .rx_detect_done_o     (),
      .rx_present_o         (),
      .TERM_SERIO_O         (),
      .rx_reset_i           (serdes_reset),
      .rx_pma_reset_i       (1'b0),
      .rx_eqa_reset_i       (1'b0),
      .rx_cdr_reset_i       (1'b0),
      .rx_pcs_reset_i       (1'b0),
      .rx_buf_reset_i       (1'b0),
      .rx_prbs_sel_i        (3'b000),
      .rx_prbs_cnt_reset_i  (1'b0),
      .rx_powerdown_n_i     (1'b1),
      .rx_en_ei_detector_i  (1'b0),
      .rx_comma_detect_en_i (1'b1),
      .rx_slide_i           (1'b0),
      .rx_polarity_i        (1'b0),
      .rx_8b10b_en_i        (1'b1),
      .rx_8b10b_bypass_i    ('0),
      .rx_mcomma_align_i    (1'b1),
      .rx_pcomma_align_i    (1'b1),
      .rx_prbs_err_o        (),
      .rx_data_o            (rx_d),
      .rx_char_is_k_o       (rx_k),
      .rx_char_is_comma_o   (),
      .rx_not_in_table_o    (rx_nit),
      .rx_disp_err_o        (rx_disp),
      .rx_buf_err_o         (b_buf_err),
      .rx_byte_is_aligned_o (b_aligned),
      .rx_byte_realign_o    (b_realign),
      .rx_resetdone_o       (b_rx_ready),
      .rx_ei_en_o           ()
  );

  // both get every write
  task automatic reg_write(logic [7:0] a, logic [15:0] d);
    @(posedge clk_reg);
    reg_addr <= a;
    reg_data <= d;
    reg_en   <= (a != 8'h5C);
    reg_we   <= 1'b1;
    cfg_en   <= (a == 8'h5C);
    @(posedge clk_reg);
    reg_en <= 1'b0;
    reg_we <= 1'b0;
    cfg_en <= 1'b0;
    repeat (16) @(posedge clk_reg);
  endtask

  //-----------------------------------------------------------------------
  // TX (A): the counter of tb_modes, the last lane counting words / 32; a
  // comma every 16 words in lane 0
  //-----------------------------------------------------------------------
  int       tx_n = 0;
  bit [8:0] sent[$];

  initial forever begin : _tx
    logic [63:0] d;
    logic [ 7:0] k;
    @(posedge clk_tx_a);
    d = '0;
    k = '0;
    for (int b = 0; b < LANES; b++) begin
      d[b*8+:8] = 8'(tx_n * LANES + b);
    end
    d[(LANES-1)*8+:8] = 8'(tx_n >> 5);
    if (tx_n % 16 == 0) begin
      d[7:0] = 8'hBC;
      k[0]   = 1'b1;
    end
    tx_d <= d;
    tx_k <= k;
    if (a_tx_ready) begin
      for (int b = 0; b < LANES; b++) begin
        sent.push_back({k[b], d[b*8+:8]});
      end
      if (sent.size() > 32768) begin
        void'(sent.pop_front());
      end
    end
    tx_n++;
  end : _tx

  //-----------------------------------------------------------------------
  // RX (B): from the first comma, find the stream in `sent`, then byte
  // for byte
  //-----------------------------------------------------------------------
  localparam int FIND = 64;
  bit [8:0] got_q[$];
  bit       locked = 1'b0;
  int       got = 0, bad = 0;
  realtime  last_t = 0, lock_t = 0;

  function automatic bit found_at(int i);
    for (int j = 0; j < got_q.size(); j++) begin
      if (sent[i+j] != got_q[j]) begin
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction

  task automatic check(bit [8:0] s, bit err);
    got++;
    last_t = $realtime;
    if (sent.size() == 0 || sent[0] != s || err) begin
      bad++;
    end
    if (sent.size() > 0) begin
      void'(sent.pop_front());
    end
  endtask

  initial forever begin : _rx
    bit [8:0] s;
    @(posedge clk_rx_b);
    if (b_rx_ready && b_aligned) begin
      for (int b = 0; b < LANES; b++) begin
        s = {rx_k[b], rx_d[b*8+:8]};
        if (locked) begin
          check(s, rx_nit[b] | rx_disp[b]);
        end
        else if (got_q.size() > 0 || s[8]) begin
          got_q.push_back(s);
          if (got_q.size() == FIND) begin
            for (int i = 0; i + FIND <= sent.size(); i++) begin
              if (found_at(i)) begin
                repeat (i) void'(sent.pop_front());
                locked = 1'b1;
                lock_t = $realtime;
                break;
              end
            end
            if (locked) begin
              for (int j = 0; j < FIND; j++) begin
                check(got_q[j], 1'b0);
              end
            end
            got_q.delete();
          end
        end
      end
    end
  end : _rx

  // After lock: RX_BUF_ERR_O (the first, when), realignments, receiver stops
  int      buf_err = 0, realigns = 0, stops = 0;
  realtime err_t = 0;

  initial forever begin : _watch
    @(posedge clk_rx_b);
    if (locked && b_buf_err) begin
      if (buf_err == 0) begin
        err_t = $realtime;
      end
      buf_err++;
    end
    if (locked && b_realign) begin
      realigns++;
    end
  end : _watch

  initial forever begin : _stops
    @(negedge u_b.rx_sampler_run);
    if (locked) begin
      stops++;
    end
  end : _stops

  initial begin
    string mode;
    arst_n       = 1'b0;
    serdes_reset = 1'b1;
    reg_en       = 1'b0;
    reg_we       = 1'b0;
    cfg_en       = 1'b0;
    reg_addr     = '0;
    reg_data     = '0;
    repeat (4) @(posedge clk_reg);
    arst_n = 1'b1;
    reg_write(8'h51, PLL_CFG1);  // the line rate and word clock
    reg_write(8'h5C, 16'h0001);  // SerDes enable
    reg_write(8'h50, 16'h0C62);  // PLL_CFG0 with the PLL off, then on (tb_modes)
    reg_write(8'h50, 16'h0C63);
    #1us;
    serdes_reset = 1'b0;
    wait (locked);
    /* verilator lint_off ZERODLY */  // run_us > 0
    #(run_us * 1us);
    /* verilator lint_on ZERODLY */
    mode = use_local ? "local" : "rec";
    if (use_local) begin
      // the buffer must give way: before the end of the run
      if (buf_err == 0) begin
        errors++;
      end
      $display("TB_PPM: %0.1f ppm, rxclk local: %0d bytes, RX_BUF_ERR %0.1f us after lock: %s", ppm, got,
               (err_t - lock_t) / 1us, (errors == 0) ? "PASS (the buffer drifts, as it must)" : "FAIL (no RX_BUF_ERR)");
    end
    else begin
      if (bad != 0 || buf_err != 0 || realigns != 0 || stops != 0 || $realtime - last_t > 1us) begin
        errors++;
      end
      $display("TB_PPM: %0.1f ppm, rxclk rec: %0d bytes, %0d wrong, %0d buf err, %0d realign, %0d stops: %s", ppm,
               got, bad, buf_err, realigns, stops, (errors == 0) ? "PASS" : "FAIL");
    end
    $finish;
  end

endmodule : tb_ppm

// -----------------------------------------------------------------------------
// Project:     openSERDES_BFM
// Description: open-source SerDes BFM
// -----------------------------------------------------------------------------
