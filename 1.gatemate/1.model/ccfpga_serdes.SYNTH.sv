// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: 0BSD

//==========================================================================
// openSERDES_BFM * open-source SerDes BFM
//--------------------------------------------------------------------------
//                   Copyright (C) 2026 Chili.CHIPS
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
//              https://opensource.org/license/0bsd
//
// 0BSD, not the repository's BSD-3-Clause: this wrapper is synthesized into
// every bitstream that uses it, and 0BSD asks for no notice with it.
//--------------------------------------------------------------------------
// Description:
//   ccfpga_serdes for synthesis: the GateMate SerDes hard macro CC_SERDES,
//   behind the ports and parameters of ccfpga_serdes (Cologne Chip's
//   simulation model, and our BFM, ccfpga_serdes.BFM.sv). A design
//   instantiates ccfpga_serdes once; the file list picks this file for the
//   chip and the BFM for simulation, with no `ifdef SYNTHESIS.
//
//   No logic: names only.
//   - Parameters: the vendor model's, with its defaults and widths (as the
//     BFM). Six defaults differ from CC_SERDES: RX_EI_BIAS, PLL_SET_OP_LOCK,
//     PLL_CI, PLL_CP, RX_CDR_CKP, RX_CDR_LOCK_CFG. RX_CDR_LOCK_CFG and
//     RX_DBG_SEL are wider: CC_SERDES takes the low bits. The HM-only TX
//     driver sets for electrical idle and receiver detection copy the main
//     set, as the vendor model's register file does. Renamed:
//     ALIGN_* (RX_ALIGN_* on CC_SERDES), RX_RESETDONE_GATE
//     (RX_RESET_DONE_GATE), the four RX_*_OVR (RX_EN_EQA_EXT_VALUE).
//     TX_BUFFER_ADDR_WIDTH has no CC_SERDES parameter.
//   - Ports: the BFM's, onto the CC_SERDES pins. CC_SERDES has its own
//     serial pins and reference clock and no config, scan or BFM reset
//     ports: those inputs are unused, the serial and termination outputs
//     unconnected, the others constant. The SerDes
//     enable is SERDES_ENABLE, or a regfile write to 0x5C, as in the BFM.
//==========================================================================

module ccfpga_serdes #(
    parameter int          TX_BUFFER_ADDR_WIDTH     = 5,  // no CC_SERDES parameter
    parameter logic [ 0:0] RX_WAIT_CDR_LOCK         = 1,
    parameter logic [ 0:0] RX_RESETDONE_GATE        = 0,
    parameter logic [ 4:0] RX_RESET_TIMER_PRESC     = 0,
    parameter logic [ 4:0] RX_PMA_RESET_TIME        = 3,
    parameter logic [ 4:0] RX_EQA_RESET_TIME        = 3,
    parameter logic [ 4:0] RX_CDR_RESET_TIME        = 3,
    parameter logic [ 4:0] RX_PCS_RESET_TIME        = 3,
    parameter logic [ 4:0] RX_BUF_RESET_TIME        = 3,
    parameter logic [ 0:0] RX_CALIB_OVR             = 0,
    parameter logic [ 3:0] RX_CALIB_VAL             = 0,
    parameter logic [ 2:0] RX_RTERM_VCMSEL          = 4,
    parameter logic [ 0:0] RX_RTERM_PD              = 0,
    parameter logic [ 7:0] RX_EQA_CKP_HF            = 8'hA3,
    parameter logic [ 7:0] RX_EQA_CKP_LF            = 8'hA3,
    parameter logic [15:0] RX_EQA_CONFIG            = 16'h01C0,
    parameter logic [ 7:0] RX_EQA_CKP_OFFSET        = 8'h01,
    parameter logic [ 0:0] RX_EN_EQA                = 0,
    parameter logic [ 3:0] RX_EQA_LOCK_CFG          = 0,
    parameter logic [ 0:0] RX_TH_MON1_OVR           = 0,  // RX_EN_EQA_EXT_VALUE
    parameter logic [ 0:0] RX_TH_MON2_OVR           = 0,  // RX_EN_EQA_EXT_VALUE
    parameter logic [ 0:0] RX_TAPW_OVR              = 0,  // RX_EN_EQA_EXT_VALUE
    parameter logic [ 0:0] RX_AFE_OFFSET_OVR        = 0,  // RX_EN_EQA_EXT_VALUE
    parameter logic [ 4:0] RX_TH_MON1               = 8,
    parameter logic [ 4:0] RX_TH_MON2               = 8,
    parameter logic [ 4:0] RX_TAPW                  = 8,
    parameter logic [ 4:0] RX_AFE_OFFSET            = 8,
    parameter logic [ 2:0] RX_AFE_VCMSEL            = 4,
    parameter logic [ 3:0] RX_AFE_GAIN              = 8,
    parameter logic [ 4:0] RX_AFE_PEAK              = 16,
    parameter logic [ 7:0] RX_CDR_CKP               = 8'hAF,  // vendor model; CC_SERDES 8'hF8
    parameter logic [ 7:0] RX_CDR_CKI               = 0,
    parameter logic [14:0] RX_CDR_LOCK_CFG          = 15'h08D5,  // vendor model; CC_SERDES has [7:0]
    parameter logic [ 1:0] RX_CDR_SET_ACC_CONFIG    = 0,
    parameter logic [ 0:0] RX_CDR_FORCE_LOCK        = 0,
    parameter logic [14:0] RX_CDR_FREQ_ACC          = 0,
    parameter logic [15:0] RX_CDR_PHASE_ACC         = 0,
    parameter logic [ 9:0] ALIGN_MCOMMA_VALUE       = 10'h283,
    parameter logic [ 9:0] ALIGN_PCOMMA_VALUE       = 10'h17C,
    parameter logic [ 9:0] ALIGN_COMMA_ENABLE       = 10'h3FF,
    parameter logic [ 1:0] ALIGN_COMMA_WORD         = 0,
    parameter logic [ 1:0] RX_SLIDE_MODE            = 0,
    parameter logic [14:0] RX_EYE_MEAS_CFG          = 0,
    parameter logic [ 5:0] RX_MON_PH_OFFSET         = 0,
    parameter logic [ 3:0] RX_EI_BIAS               = 4,  // vendor model, DS1001; CC_SERDES 0, the detector off
    parameter logic [ 3:0] RX_EI_BW_SEL             = 4,
    parameter logic [ 0:0] RX_BUF_BYPASS            = 0,
    parameter logic [ 0:0] RX_CLKCOR_USE            = 0,
    parameter logic [ 9:0] RX_CLKCOR_SEQ_1_0        = 10'h1F7,
    parameter logic [ 9:0] RX_CLKCOR_SEQ_1_1        = 10'h1F7,
    parameter logic [ 9:0] RX_CLKCOR_SEQ_1_2        = 10'h1F7,
    parameter logic [ 9:0] RX_CLKCOR_SEQ_1_3        = 10'h1F7,
    parameter logic [ 5:0] RX_CLKCOR_MIN_LAT        = 32,
    parameter logic [ 5:0] RX_CLKCOR_MAX_LAT        = 39,
    parameter logic [ 1:0] RX_DATAPATH_SEL          = 3,
    parameter logic [ 5:0] RX_DBG_SRAM_DELAY        = 6'h05,
    parameter logic [ 3:0] RX_DBG_SEL               = 0,  // vendor model, DS1001 0x2D [4:1]; Yosys CC_SERDES has [1:0]
    parameter logic [ 0:0] RX_DBG_MODE              = 0,
    parameter logic [ 4:0] TX_SEL_PRE               = 0,
    parameter logic [ 4:0] TX_SEL_POST              = 0,
    parameter logic [ 2:0] TX_TAIL_CASCODE          = 4,
    parameter logic [ 4:0] TX_BRANCH_EN_PRE         = 0,
    parameter logic [ 5:0] TX_BRANCH_EN_MAIN        = 6'h3F,
    parameter logic [ 4:0] TX_BRANCH_EN_POST        = 0,
    parameter logic [ 6:0] TX_DC_ENABLE             = 63,
    parameter logic [ 4:0] TX_AMP                   = 15,
    parameter logic [ 4:0] TX_DC_OFFSET             = 0,
    parameter logic [ 4:0] TX_CM_RAISE              = 0,
    parameter logic [ 4:0] TX_CM_THRESHOLD_0        = 14,
    parameter logic [ 4:0] TX_CM_THRESHOLD_1        = 16,
    parameter logic [ 0:0] TX_CALIB_OVR             = 0,
    parameter logic [ 3:0] TX_CALIB_VAL             = 0,
    parameter logic [ 0:0] TX_CM_REG_EN             = 1,
    parameter logic [ 7:0] TX_CM_REG_KI             = 8'h80,
    parameter logic [ 4:0] TX_PMA_RESET_TIME        = 3,
    parameter logic [ 4:0] TX_PCS_RESET_TIME        = 3,
    parameter logic [ 1:0] TX_PMA_LOOPBACK          = 0,
    parameter logic [ 1:0] TX_DATAPATH_SEL          = 3,
    parameter logic [ 0:0] SERDES_ENABLE            = 0,
    parameter logic [ 0:0] SERDES_AUTO_INIT         = 0,
    parameter logic [ 0:0] PLL_EN_ADPLL_CTRL        = 0,
    parameter logic [ 0:0] PLL_CONFIG_SEL           = 0,
    parameter logic [ 0:0] PLL_SET_OP_LOCK          = 1,  // vendor model; CC_SERDES 0
    parameter logic [ 0:0] PLL_ENFORCE_LOCK         = 0,
    parameter logic [ 0:0] PLL_DISABLE_LOCK         = 0,
    parameter logic [ 0:0] PLL_LOCK_WINDOW          = 1,
    parameter logic [ 0:0] PLL_FAST_LOCK            = 1,
    parameter logic [ 0:0] PLL_SYNC_BYPASS          = 0,
    parameter logic [ 0:0] PLL_PFD_SELECT           = 0,
    parameter logic [ 0:0] PLL_REF_BYPASS           = 0,
    parameter logic [ 0:0] PLL_REF_SEL              = 0,
    parameter logic [ 0:0] PLL_REF_RTERM            = 1,
    parameter logic [ 5:0] PLL_FCNTRL               = 58,
    parameter logic [ 5:0] PLL_MAIN_DIVSEL          = 27,
    parameter logic [ 1:0] PLL_OUT_DIVSEL           = 0,
    parameter logic [ 4:0] PLL_CI                   = 1,  // vendor model; CC_SERDES 3
    parameter logic [ 9:0] PLL_CP                   = 60,  // vendor model; CC_SERDES 80
    parameter logic [ 3:0] PLL_AO                   = 0,
    parameter logic [ 2:0] PLL_SCAP                 = 0,
    parameter logic [ 0:0] PLL_SCAP_AUTO_CAL        = 1,
    parameter logic [ 1:0] PLL_FILTER_SHIFT         = 2,
    parameter logic [ 2:0] PLL_SAR_LIMIT            = 2,
    parameter logic [10:0] PLL_FT                   = 512,
    parameter logic [ 0:0] PLL_OPEN_LOOP            = 0,
    parameter logic [ 2:0] PLL_BISC_MODE            = 4,
    parameter logic [ 3:0] PLL_BISC_TIMER_MAX       = 15,
    parameter logic [ 4:0] PLL_BISC_CP_MIN          = 4,
    parameter logic [ 4:0] PLL_BISC_CP_MAX          = 18,
    parameter logic [ 4:0] PLL_BISC_CP_START        = 12,
    parameter logic [ 0:0] PLL_BISC_OPT_DET_IND     = 0,
    parameter logic [ 0:0] PLL_BISC_PFD_SEL         = 0,
    parameter logic [ 0:0] PLL_BISC_DLY_DIR         = 0,
    parameter logic [ 0:0] PLL_BISC_CAL_SIGN        = 0,
    parameter logic [ 0:0] PLL_BISC_CAL_AUTO        = 1,
    parameter logic [ 4:0] PLL_BISC_DLY_PFD_MON_REF = 0,
    parameter logic [ 4:0] PLL_BISC_DLY_PFD_MON_DIV = 2,
    parameter logic [ 2:0] PLL_BISC_COR_DLY         = 1
) (
    input  logic        clk_ref_i,
    input  logic        clk_reg_i,
    input  logic        clk_cfg_i,
    input  logic        clk_core_tx_i,
    input  logic        clk_core_rx_i,
    output logic        clk_core_rx_o,
    input  logic        reset_n_i,
    input  logic        reset_reg_n_i,
    input  logic        reset_core_tx_n_i,
    input  logic        reset_core_rx_n_i,
    input  logic        testmode_i,
    input  logic        scan_enable_i,
    input  logic [ 6:0] scan_in_i,
    output logic [ 6:0] scan_out_o,
    input  logic [ 2:0] loopback_i,
    input  logic        pll_reset_i,
    output logic        clk_core_pll_o,
    output logic        reset_core_pll_n_o,
    output logic        refclk_sel_o,
    output logic        refclk_rterm_o,
    // Serial pins: CC_SERDES has none. The chip's SerDes drives and senses
    // its own dedicated pads, which no netlist reaches, so these four stay
    // unconnected here: no level on a pin the chip does not have. They exist
    // for the BFM (ccfpga_serdes.BFM.sv), whose serializer drives TX and
    // samples RX, so phy_top takes either file unchanged. top.sv drops them
    // under SYNTHESIS
    input  logic        RX_SERIO_P_B,
    input  logic        RX_SERIO_N_B,
    output logic        TX_SERIO_P_B,
    output logic        TX_SERIO_N_B,
    input  logic        regfile_we_i,
    input  logic        regfile_en_i,
    input  logic [ 7:0] regfile_addr_i,
    input  logic [15:0] regfile_mask_i,
    input  logic [15:0] regfile_di_i,
    output logic [15:0] regfile_do_o,
    output logic        regfile_rdy_o,
    input  logic        cfg_en_i,
    input  logic        reset_cfg_i,
    input  logic [15:0] cfgfile_di_i,
    input  logic        cfgfile_valid_i,
    input  logic [ 7:0] cfgfile_addr_i,
    input  logic        tx_reset_i,
    input  logic        tx_pcs_reset_i,
    input  logic        tx_pma_reset_i,
    input  logic        tx_elec_idle_i,
    input  logic        tx_detect_rx_i,
    input  logic [ 2:0] tx_prbs_sel_i,
    input  logic        tx_prbs_force_err_i,
    input  logic        tx_powerdown_n_i,
    input  logic [63:0] tx_data_i,
    input  logic [ 7:0] tx_char_is_k_i,
    input  logic        tx_polarity_i,
    input  logic        tx_8b10b_en_i,
    input  logic [ 7:0] tx_8b10b_bypass_i,
    input  logic [ 7:0] tx_char_dispmode_i,
    input  logic [ 7:0] tx_char_dispval_i,
    output logic        tx_buf_err_o,
    output logic        tx_resetdone_o,
    output logic        rx_detect_done_o,
    output logic        rx_present_o,
    // the wrapper's termination calibration output: no CC_SERDES pin, left
    // unconnected like the serial pins above
    output logic        TERM_SERIO_O,
    input  logic        rx_reset_i,
    input  logic        rx_pma_reset_i,
    input  logic        rx_eqa_reset_i,
    input  logic        rx_cdr_reset_i,
    input  logic        rx_pcs_reset_i,
    input  logic        rx_buf_reset_i,
    input  logic [ 2:0] rx_prbs_sel_i,
    input  logic        rx_prbs_cnt_reset_i,
    input  logic        rx_powerdown_n_i,
    input  logic        rx_en_ei_detector_i,
    input  logic        rx_comma_detect_en_i,
    input  logic        rx_slide_i,
    input  logic        rx_polarity_i,
    input  logic        rx_8b10b_en_i,
    input  logic [ 7:0] rx_8b10b_bypass_i,
    input  logic        rx_mcomma_align_i,
    input  logic        rx_pcomma_align_i,
    output logic        rx_prbs_err_o,
    output logic [63:0] rx_data_o,
    output logic [ 7:0] rx_char_is_k_o,
    output logic [ 7:0] rx_char_is_comma_o,
    output logic [ 7:0] rx_not_in_table_o,
    output logic [ 7:0] rx_disp_err_o,
    output logic        rx_buf_err_o,
    output logic        rx_byte_is_aligned_o,
    output logic        rx_byte_realign_o,
    output logic        rx_resetdone_o,
    output logic        rx_ei_en_o
);

  // The BFM-only inputs have no CC_SERDES pin: the chip has its own serial
  // pins and reference clock, and no config, scan or BFM reset ports;
  // TX_BUFFER_ADDR_WIDTH sizes the BFM's TX buffer only
  logic unused;
  assign unused = ^{1'(TX_BUFFER_ADDR_WIDTH), clk_ref_i, clk_cfg_i, reset_n_i, reset_reg_n_i, reset_core_tx_n_i, reset_core_rx_n_i, testmode_i, scan_enable_i, scan_in_i, RX_SERIO_P_B, RX_SERIO_N_B, cfg_en_i, reset_cfg_i, cfgfile_di_i, cfgfile_valid_i, cfgfile_addr_i};

  assign scan_out_o = '0;
  assign reset_core_pll_n_o = 1'b1;
  assign refclk_sel_o = PLL_REF_SEL;
  assign refclk_rterm_o = PLL_REF_RTERM;

  CC_SERDES #(
      .RX_WAIT_CDR_LOCK         (RX_WAIT_CDR_LOCK),
      .RX_RESET_DONE_GATE       (RX_RESETDONE_GATE),
      .RX_RESET_TIMER_PRESC     (RX_RESET_TIMER_PRESC),
      .RX_PMA_RESET_TIME        (RX_PMA_RESET_TIME),
      .RX_EQA_RESET_TIME        (RX_EQA_RESET_TIME),
      .RX_CDR_RESET_TIME        (RX_CDR_RESET_TIME),
      .RX_PCS_RESET_TIME        (RX_PCS_RESET_TIME),
      .RX_BUF_RESET_TIME        (RX_BUF_RESET_TIME),
      .RX_CALIB_OVR             (RX_CALIB_OVR),
      .RX_CALIB_VAL             (RX_CALIB_VAL),
      .RX_RTERM_VCMSEL          (RX_RTERM_VCMSEL),
      .RX_RTERM_PD              (RX_RTERM_PD),
      .RX_EQA_CKP_HF            (RX_EQA_CKP_HF),
      .RX_EQA_CKP_LF            (RX_EQA_CKP_LF),
      .RX_EQA_CONFIG            (RX_EQA_CONFIG),
      .RX_EQA_CKP_OFFSET        (RX_EQA_CKP_OFFSET),
      .RX_EN_EQA                (RX_EN_EQA),
      .RX_EQA_LOCK_CFG          (RX_EQA_LOCK_CFG),
      .RX_TH_MON1               (RX_TH_MON1),
      .RX_TH_MON2               (RX_TH_MON2),
      .RX_TAPW                  (RX_TAPW),
      .RX_AFE_OFFSET            (RX_AFE_OFFSET),
      .RX_AFE_VCMSEL            (RX_AFE_VCMSEL),
      .RX_AFE_GAIN              (RX_AFE_GAIN),
      .RX_AFE_PEAK              (RX_AFE_PEAK),
      .RX_CDR_CKP               (RX_CDR_CKP),
      .RX_CDR_CKI               (RX_CDR_CKI),
      .RX_CDR_LOCK_CFG          (RX_CDR_LOCK_CFG[7:0]),
      .RX_CDR_SET_ACC_CONFIG    (RX_CDR_SET_ACC_CONFIG),
      .RX_CDR_FORCE_LOCK        (RX_CDR_FORCE_LOCK),
      .RX_CDR_FREQ_ACC          (RX_CDR_FREQ_ACC),
      .RX_CDR_PHASE_ACC         (RX_CDR_PHASE_ACC),
      .RX_ALIGN_MCOMMA_VALUE    (ALIGN_MCOMMA_VALUE),
      .RX_ALIGN_PCOMMA_VALUE    (ALIGN_PCOMMA_VALUE),
      .RX_ALIGN_COMMA_ENABLE    (ALIGN_COMMA_ENABLE),
      .RX_ALIGN_COMMA_WORD      (ALIGN_COMMA_WORD),
      .RX_SLIDE_MODE            (RX_SLIDE_MODE),
      .RX_EYE_MEAS_CFG          (RX_EYE_MEAS_CFG),
      .RX_MON_PH_OFFSET         (RX_MON_PH_OFFSET),
      .RX_EI_BIAS               (RX_EI_BIAS),
      .RX_EI_BW_SEL             (RX_EI_BW_SEL),
      .RX_BUF_BYPASS            (RX_BUF_BYPASS),
      .RX_CLKCOR_USE            (RX_CLKCOR_USE),
      .RX_CLKCOR_SEQ_1_0        (RX_CLKCOR_SEQ_1_0),
      .RX_CLKCOR_SEQ_1_1        (RX_CLKCOR_SEQ_1_1),
      .RX_CLKCOR_SEQ_1_2        (RX_CLKCOR_SEQ_1_2),
      .RX_CLKCOR_SEQ_1_3        (RX_CLKCOR_SEQ_1_3),
      .RX_CLKCOR_MIN_LAT        (RX_CLKCOR_MIN_LAT),
      .RX_CLKCOR_MAX_LAT        (RX_CLKCOR_MAX_LAT),
      .RX_DATAPATH_SEL          (RX_DATAPATH_SEL),
      .RX_DBG_SRAM_DELAY        (RX_DBG_SRAM_DELAY),
      .RX_DBG_SEL               (RX_DBG_SEL[1:0]),
      .RX_DBG_MODE              (RX_DBG_MODE),
      .TX_SEL_PRE               (TX_SEL_PRE),
      .TX_SEL_POST              (TX_SEL_POST),
      .TX_TAIL_CASCODE          (TX_TAIL_CASCODE),
      .TX_BRANCH_EN_PRE         (TX_BRANCH_EN_PRE),
      .TX_BRANCH_EN_MAIN        (TX_BRANCH_EN_MAIN),
      .TX_BRANCH_EN_POST        (TX_BRANCH_EN_POST),
      .TX_DC_ENABLE             (TX_DC_ENABLE),
      .TX_AMP                   (TX_AMP),
      .TX_DC_OFFSET             (TX_DC_OFFSET),
      .TX_CM_RAISE              (TX_CM_RAISE),
      .TX_CM_THRESHOLD_0        (TX_CM_THRESHOLD_0),
      .TX_CM_THRESHOLD_1        (TX_CM_THRESHOLD_1),
      .TX_CALIB_OVR             (TX_CALIB_OVR),
      .TX_CALIB_VAL             (TX_CALIB_VAL),
      .TX_CM_REG_EN             (TX_CM_REG_EN),
      .TX_CM_REG_KI             (TX_CM_REG_KI),
      .TX_PMA_RESET_TIME        (TX_PMA_RESET_TIME),
      .TX_PCS_RESET_TIME        (TX_PCS_RESET_TIME),
      .TX_PMA_LOOPBACK          (TX_PMA_LOOPBACK),
      .TX_DATAPATH_SEL          (TX_DATAPATH_SEL),
      .SERDES_ENABLE            (SERDES_ENABLE),
      .SERDES_AUTO_INIT         (SERDES_AUTO_INIT),
      .PLL_EN_ADPLL_CTRL        (PLL_EN_ADPLL_CTRL),
      .PLL_CONFIG_SEL           (PLL_CONFIG_SEL),
      .PLL_SET_OP_LOCK          (PLL_SET_OP_LOCK),
      .PLL_ENFORCE_LOCK         (PLL_ENFORCE_LOCK),
      .PLL_DISABLE_LOCK         (PLL_DISABLE_LOCK),
      .PLL_LOCK_WINDOW          (PLL_LOCK_WINDOW),
      .PLL_FAST_LOCK            (PLL_FAST_LOCK),
      .PLL_SYNC_BYPASS          (PLL_SYNC_BYPASS),
      .PLL_PFD_SELECT           (PLL_PFD_SELECT),
      .PLL_REF_BYPASS           (PLL_REF_BYPASS),
      .PLL_REF_SEL              (PLL_REF_SEL),
      .PLL_REF_RTERM            (PLL_REF_RTERM),
      .PLL_FCNTRL               (PLL_FCNTRL),
      .PLL_MAIN_DIVSEL          (PLL_MAIN_DIVSEL),
      .PLL_OUT_DIVSEL           (PLL_OUT_DIVSEL),
      .PLL_CI                   (PLL_CI),
      .PLL_CP                   (PLL_CP),
      .PLL_AO                   (PLL_AO),
      .PLL_SCAP                 (PLL_SCAP),
      .PLL_SCAP_AUTO_CAL        (PLL_SCAP_AUTO_CAL),
      .PLL_FILTER_SHIFT         (PLL_FILTER_SHIFT),
      .PLL_SAR_LIMIT            (PLL_SAR_LIMIT),
      .PLL_FT                   (PLL_FT),
      .PLL_OPEN_LOOP            (PLL_OPEN_LOOP),
      .PLL_BISC_MODE            (PLL_BISC_MODE),
      .PLL_BISC_TIMER_MAX       (PLL_BISC_TIMER_MAX),
      .PLL_BISC_CP_MIN          (PLL_BISC_CP_MIN),
      .PLL_BISC_CP_MAX          (PLL_BISC_CP_MAX),
      .PLL_BISC_CP_START        (PLL_BISC_CP_START),
      .PLL_BISC_OPT_DET_IND     (PLL_BISC_OPT_DET_IND),
      .PLL_BISC_PFD_SEL         (PLL_BISC_PFD_SEL),
      .PLL_BISC_DLY_DIR         (PLL_BISC_DLY_DIR),
      .PLL_BISC_CAL_SIGN        (PLL_BISC_CAL_SIGN),
      .PLL_BISC_CAL_AUTO        (PLL_BISC_CAL_AUTO),
      .PLL_BISC_DLY_PFD_MON_REF (PLL_BISC_DLY_PFD_MON_REF),
      .PLL_BISC_DLY_PFD_MON_DIV (PLL_BISC_DLY_PFD_MON_DIV),
      .PLL_BISC_COR_DLY         (PLL_BISC_COR_DLY),
      .RX_EN_EQA_EXT_VALUE      ({RX_AFE_OFFSET_OVR, RX_TAPW_OVR, RX_TH_MON2_OVR, RX_TH_MON1_OVR}),
      // HM only, as the vendor model: the TX driver sets for electrical
      // idle (_EI) and receiver detection (_RXDET) copy the main set. Unset,
      // nextpnr gives TX_DC_ENABLE_RXDET 0 (DS1001: 63): detection off
      .TX_SEL_PRE_EI            (TX_SEL_PRE),
      .TX_SEL_POST_EI           (TX_SEL_POST),
      .TX_AMP_EI                (TX_AMP),
      .TX_BRANCH_EN_PRE_EI      (TX_BRANCH_EN_PRE),
      .TX_BRANCH_EN_MAIN_EI     (TX_BRANCH_EN_MAIN),
      .TX_BRANCH_EN_POST_EI     (TX_BRANCH_EN_POST),
      .TX_TAIL_CASCODE_EI       (TX_TAIL_CASCODE),
      .TX_DC_ENABLE_EI          (TX_DC_ENABLE),
      .TX_DC_OFFSET_EI          (TX_DC_OFFSET),
      .TX_CM_RAISE_EI           (TX_CM_RAISE),
      .TX_CM_THRESHOLD_0_EI     (TX_CM_THRESHOLD_0),
      .TX_CM_THRESHOLD_1_EI     (TX_CM_THRESHOLD_1),
      .TX_SEL_PRE_RXDET         (TX_SEL_PRE),
      .TX_SEL_POST_RXDET        (TX_SEL_POST),
      .TX_AMP_RXDET             (TX_AMP),
      .TX_BRANCH_EN_PRE_RXDET   (TX_BRANCH_EN_PRE),
      .TX_BRANCH_EN_MAIN_RXDET  (TX_BRANCH_EN_MAIN),
      .TX_BRANCH_EN_POST_RXDET  (TX_BRANCH_EN_POST),
      .TX_TAIL_CASCODE_RXDET    (TX_TAIL_CASCODE),
      .TX_DC_ENABLE_RXDET       (TX_DC_ENABLE),
      .TX_DC_OFFSET_RXDET       (TX_DC_OFFSET),
      .TX_CM_RAISE_RXDET        (TX_CM_RAISE),
      .TX_CM_THRESHOLD_0_RXDET  (TX_CM_THRESHOLD_0),
      .TX_CM_THRESHOLD_1_RXDET  (TX_CM_THRESHOLD_1)
  ) u_serdes (
      .REGFILE_CLK_I          (clk_reg_i),
      .TX_CLK_I               (clk_core_tx_i),
      .RX_CLK_I               (clk_core_rx_i),
      .RX_CLK_O               (clk_core_rx_o),
      .LOOPBACK_I             (loopback_i),
      .PLL_RESET_I            (pll_reset_i),
      .PLL_CLK_O              (clk_core_pll_o),
      .REGFILE_WE_I           (regfile_we_i),
      .REGFILE_EN_I           (regfile_en_i),
      .REGFILE_ADDR_I         (regfile_addr_i),
      .REGFILE_MASK_I         (regfile_mask_i),
      .REGFILE_DI_I           (regfile_di_i),
      .REGFILE_DO_O           (regfile_do_o),
      .REGFILE_RDY_O          (regfile_rdy_o),
      .TX_RESET_I             (tx_reset_i),
      .TX_PCS_RESET_I         (tx_pcs_reset_i),
      .TX_PMA_RESET_I         (tx_pma_reset_i),
      .TX_ELEC_IDLE_I         (tx_elec_idle_i),
      .TX_DETECT_RX_I         (tx_detect_rx_i),
      .TX_PRBS_SEL_I          (tx_prbs_sel_i),
      .TX_PRBS_FORCE_ERR_I    (tx_prbs_force_err_i),
      .TX_POWER_DOWN_N_I      (tx_powerdown_n_i),
      .TX_DATA_I              (tx_data_i),
      .TX_CHAR_IS_K_I         (tx_char_is_k_i),
      .TX_POLARITY_I          (tx_polarity_i),
      .TX_8B10B_EN_I          (tx_8b10b_en_i),
      .TX_8B10B_BYPASS_I      (tx_8b10b_bypass_i),
      .TX_CHAR_DISPMODE_I     (tx_char_dispmode_i),
      .TX_CHAR_DISPVAL_I      (tx_char_dispval_i),
      .TX_BUF_ERR_O           (tx_buf_err_o),
      .TX_RESET_DONE_O        (tx_resetdone_o),
      .TX_DETECT_RX_DONE_O    (rx_detect_done_o),
      .TX_DETECT_RX_PRESENT_O (rx_present_o),
      .RX_RESET_I             (rx_reset_i),
      .RX_PMA_RESET_I         (rx_pma_reset_i),
      .RX_EQA_RESET_I         (rx_eqa_reset_i),
      .RX_CDR_RESET_I         (rx_cdr_reset_i),
      .RX_PCS_RESET_I         (rx_pcs_reset_i),
      .RX_BUF_RESET_I         (rx_buf_reset_i),
      .RX_PRBS_SEL_I          (rx_prbs_sel_i),
      .RX_PRBS_CNT_RESET_I    (rx_prbs_cnt_reset_i),
      .RX_POWER_DOWN_N_I      (rx_powerdown_n_i),
      .RX_EN_EI_DETECTOR_I    (rx_en_ei_detector_i),
      .RX_COMMA_DETECT_EN_I   (rx_comma_detect_en_i),
      .RX_SLIDE_I             (rx_slide_i),
      .RX_POLARITY_I          (rx_polarity_i),
      .RX_8B10B_EN_I          (rx_8b10b_en_i),
      .RX_8B10B_BYPASS_I      (rx_8b10b_bypass_i),
      .RX_MCOMMA_ALIGN_I      (rx_mcomma_align_i),
      .RX_PCOMMA_ALIGN_I      (rx_pcomma_align_i),
      .RX_PRBS_ERR_O          (rx_prbs_err_o),
      .RX_DATA_O              (rx_data_o),
      .RX_CHAR_IS_K_O         (rx_char_is_k_o),
      .RX_CHAR_IS_COMMA_O     (rx_char_is_comma_o),
      .RX_NOT_IN_TABLE_O      (rx_not_in_table_o),
      .RX_DISP_ERR_O          (rx_disp_err_o),
      .RX_BUF_ERR_O           (rx_buf_err_o),
      .RX_BYTE_IS_ALIGNED_O   (rx_byte_is_aligned_o),
      .RX_BYTE_REALIGN_O      (rx_byte_realign_o),
      .RX_RESET_DONE_O        (rx_resetdone_o),
      .RX_EI_EN_O             (rx_ei_en_o)
  );

endmodule : ccfpga_serdes


// -----------------------------------------------------------------------------
// Project:     openSERDES_BFM
// Description: open-source SerDes BFM
// -----------------------------------------------------------------------------
