// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"

module mbx
  import tlul_pkg::*;
  import mbx_reg_pkg::*;
#(
  parameter logic [NumAlerts-1:0] AlertAsyncOn = {NumAlerts{1'b1}},
  parameter int unsigned CfgSramAddrWidth      = 32,
  parameter int unsigned CfgSramDataWidth      = 32,
  parameter bit          DoeIrqSupport         = 1'b1
) (
  input  logic                                      clk_i,
  input  logic                                      rst_ni,
  // Comportable interrupt to the OT
  output logic                                      intr_mbx_ready_o,
  output logic                                      intr_mbx_abort_o,
  // Custom interrupt to the system requester
  output logic                                      doe_intr_support_o,
  output logic                                      doe_intr_en_o,
  output logic                                      doe_intr_o,
  // Alerts
  input  prim_alert_pkg::alert_rx_t [NumAlerts-1:0] alert_rx_i,
  output prim_alert_pkg::alert_tx_t [NumAlerts-1:0] alert_tx_o,
  // Device port facing OT-host
  input   tlul_pkg::tl_h2d_t                        tl_host_i,
  output  tlul_pkg::tl_d2h_t                        tl_host_o,
  // Device port facing CTN Xbar
  input   tlul_pkg::tl_h2d_t                        tl_sys_i,
  output  tlul_pkg::tl_d2h_t                        tl_sys_o,
  // Host port to access private SRAM
  input   tlul_pkg::tl_d2h_t                        tl_sram_i,
  output  tlul_pkg::tl_h2d_t                        tl_sram_o
);
  //////////////////////////////////////////////////////////////////////////////
  // General signals for the mailbox
  //////////////////////////////////////////////////////////////////////////////

  // Collect all error sources
  logic sysif_intg_err, tl_sram_intg_err, imbx_state_error, alert_signal;
  assign alert_signal = sysif_intg_err     |
                        tl_sram_intg_err   |
                        imbx_state_error;

  //////////////////////////////////////////////////////////////////////////////
  // Control and Status signals of the host interface
  //////////////////////////////////////////////////////////////////////////////

  logic hostif_event_intr_ready, hostif_event_intr_abort;
  logic hostif_address_range_valid;
  logic sysif_control_abort_write;

  // Status signal inputs from the sysif to the hostif
  logic sysif_status_busy, sysif_status_doe_intr_status, sysif_status_async_msg_status,
        sysif_status_error, sysif_status_ready;

  // Setter signals from the hostif to the sysif
  logic hostif_status_doe_intr_status_set, hostif_status_async_msg_status_set,
        hostif_control_abort_set, hostif_status_busy_clear,
        hostif_status_error_set, hostif_status_error_clear;

  // Alias signals from the sys interface
  logic [CfgSramAddrWidth-1:0] sysif_intr_msg_addr;
  logic [CfgSramDataWidth-1:0] sysif_intr_msg_data;

  //////////////////////////////////////////////////////////////////////////////
  // Signals for the Inbox
  //////////////////////////////////////////////////////////////////////////////

  logic [CfgSramAddrWidth-1:0] hostif_imbx_base, hostif_imbx_limit;
  logic [CfgSramAddrWidth-1:0] imbx_sram_write_ptr;

  //////////////////////////////////////////////////////////////////////////////
  // Signals for the Outbox
  //////////////////////////////////////////////////////////////////////////////

  logic [CfgSramAddrWidth-1:0] hostif_ombx_base, hostif_ombx_limit;
  logic [CfgSramAddrWidth-1:0] ombx_sram_read_ptr;

  logic hostif_ombx_object_size_write, hostif_ombx_object_size_read;
  logic [10:0] hostif_ombx_object_size_wdata, hostif_ombx_object_size_rdata;

  mbx_hostif #(
    .AlertAsyncOn    ( AlertAsyncOn     ),
    .CfgSramAddrWidth( CfgSramAddrWidth ),
    .CfgSramDataWidth( CfgSramDataWidth )
  ) u_hostif (
    .clk_i                               ( clk_i                              ),
    .rst_ni                              ( rst_ni                             ),
    // Device port to the host side
    .tl_host_i                           ( tl_host_i                          ),
    .tl_host_o                           ( tl_host_o                          ),
    .intg_err_i                          ( alert_signal                       ),
    .event_intr_ready_i                  ( hostif_event_intr_ready            ),
    .event_intr_abort_i                  ( hostif_event_intr_abort            ),
    .intr_ready_o                        ( intr_mbx_ready_o                   ),
    .intr_abort_o                        ( intr_mbx_abort_o                   ),
    .alert_rx_i                          ( alert_rx_i                         ),
    .alert_tx_o                          ( alert_tx_o                         ),
    // Access to the control register
    .hostif_control_abort_set_o          ( hostif_control_abort_set           ),
    // Access to the status register
    .hostif_status_busy_clear_o          ( hostif_status_busy_clear           ),
    .hostif_status_busy_i                ( sysif_status_busy                  ),
    .hostif_status_doe_intr_status_set_o ( hostif_status_doe_intr_status_set   ),
    .hostif_status_doe_intr_status_i     ( sysif_status_doe_intr_status       ),
    .hostif_status_async_msg_status_set_o( hostif_status_async_msg_status_set ),
    .hostif_status_async_msg_status_i    ( sysif_status_async_msg_status      ),
    .hostif_status_error_set_o           ( hostif_status_error_set            ),
    .hostif_status_error_clear_o         ( hostif_status_error_clear          ),
    .hostif_status_error_i               ( sysif_status_error                 ),
    .hostif_status_ready_i               ( sysif_status_ready                 ),
    // Access to the IB/OB RD/WR Pointers
    .hostif_imbx_write_ptr_i             ( imbx_sram_write_ptr                ),
    .hostif_ombx_read_ptr_i              ( ombx_sram_read_ptr                 ),
    // Access to the memory region registers
    .hostif_address_range_valid_o        ( hostif_address_range_valid         ),
    .hostif_imbx_base_o                  ( hostif_imbx_base                   ),
    .hostif_imbx_limit_o                 ( hostif_imbx_limit                  ),
    .hostif_ombx_base_o                  ( hostif_ombx_base                   ),
    .hostif_ombx_limit_o                 ( hostif_ombx_limit                  ),
    // Read/Write access for the OB DW Count register
    .hostif_ombx_object_size_write_o      ( hostif_ombx_object_size_write     ),
    .hostif_ombx_object_size_o            ( hostif_ombx_object_size_wdata     ),
    .hostif_ombx_object_size_read_i       ( hostif_ombx_object_size_read      ),
    .hostif_ombx_object_size_i            ( hostif_ombx_object_size_rdata     ),
    // Alias of the interrupt address and data registers from the SYS interface
    .sysif_intr_msg_addr_i                ( sysif_intr_msg_addr               ),
    .sysif_intr_msg_data_i                ( sysif_intr_msg_data               ),
    // Control inputs coming from the system registers interface
    .sysif_control_abort_write_i          ( sysif_control_abort_write         )
  );

  //////////////////////////////////////////////////////////////////////////////
  // Control and Status signals of the system interface
  //////////////////////////////////////////////////////////////////////////////
  logic sysif_control_go_set, sysif_control_abort_set, sysif_control_async_msg_en;

  //////////////////////////////////////////////////////////////////////////////
  // Signals for the Inbox
  //////////////////////////////////////////////////////////////////////////////
  logic imbx_pending;
  logic imbx_status_busy_valid, imbx_status_busy;

  // Interface signals for SRAM host access to write the incoming data to memory
  logic imbx_sram_write_req, imbx_sram_write_gnt;
  logic imbx_sram_write_resp_vld;
  logic [CfgSramDataWidth-1:0] sysif_write_data;
  logic sysif_write_data_write_valid;

  //////////////////////////////////////////////////////////////////////////////
  // Signals for the Outbox
  //////////////////////////////////////////////////////////////////////////////
  logic ombx_pending;
  logic ombx_status_ready_valid, ombx_status_ready;

  // Interface signals for SRAM host access to read the memory and serve it to the outbox
  logic ombx_sram_read_req, ombx_sram_read_gnt;
  logic ombx_sram_read_resp_vld;
  logic [CfgSramDataWidth-1:0] sysif_read_data;
  logic sysif_read_data_read_valid, sysif_read_data_write_valid;

  mbx_sysif #(
    .CfgSramAddrWidth ( CfgSramAddrWidth ),
    .CfgSramDataWidth ( CfgSramDataWidth ),
    .DoeIrqSupport    ( DoeIrqSupport    )
  ) u_sysif (
    .clk_i                               ( clk_i                              ),
    .rst_ni                              ( rst_ni                             ),
    .tl_sys_i                            ( tl_sys_i                           ),
    .tl_sys_o                            ( tl_sys_o                           ),
    .intg_err_o                          ( sysif_intg_err                     ),
    // System interrupt support
    .doe_intr_support_o                  ( doe_intr_support_o                 ),
    .doe_intr_en_o                       ( doe_intr_en_o                      ),
    .doe_intr_o                          ( doe_intr_o                         ),
    // Access to the control register
    .sysif_control_abort_set_o           ( sysif_control_abort_set            ),
    .sysif_control_async_msg_en_o        ( sysif_control_async_msg_en         ),
    .sysif_control_go_set_o              ( sysif_control_go_set               ),
    // Access to the status register
    .sysif_status_busy_valid_i           ( imbx_status_busy_valid             ),
    .sysif_status_busy_i                 ( imbx_status_busy                   ),
    .sysif_status_busy_o                 ( sysif_status_busy                  ),


    .sysif_status_doe_intr_status_set_i  ( hostif_status_doe_intr_status_set   ),
    .sysif_status_doe_intr_status_o      ( sysif_status_doe_intr_status       ),

    .sysif_status_error_set_i            ( hostif_status_error_set            ),
    .sysif_status_error_clear_i          ( hostif_status_error_clear          ),
    .sysif_status_error_o                ( sysif_status_error          ),

    .sysif_status_async_msg_status_set_i ( hostif_status_async_msg_status_set  ),
    .sysif_status_async_msg_status_o     ( sysif_status_async_msg_status      ),

    .sysif_status_ready_valid_i          ( ombx_status_ready_valid            ),
    .sysif_status_ready_i                ( ombx_status_ready                  ),
    .sysif_status_ready_o                ( sysif_status_ready                 ),
    // Alias of the interrupt address and data registers to the host interface
    .sysif_intr_msg_addr_o               ( sysif_intr_msg_addr                ),
    .sysif_intr_msg_data_o               ( sysif_intr_msg_data                ),
    // Control lines for backpressuring the bus
    .imbx_pending_i                      ( imbx_pending                       ),
    .ombx_pending_i                      ( ombx_pending                       ),
    // Data interface for inbound and outbound mailbox
    .write_data_write_valid_o            ( sysif_write_data_write_valid       ),
    .write_data_o                        ( sysif_write_data                   ),
    .read_data_read_valid_o              ( sysif_read_data_read_valid         ),
    .read_data_write_valid_o             ( sysif_read_data_write_valid        ),
    .read_data_i                         ( sysif_read_data                    )
  );


  mbx_imbx #(
    .CfgSramAddrWidth( CfgSramAddrWidth ),
    .CfgSramDataWidth( CfgSramDataWidth )
  ) u_imbx (
    .clk_i                      ( clk_i                        ),
    .rst_ni                     ( rst_ni                       ),
    // Interface to the host port
    .imbx_state_error_o        ( imbx_state_error              ),
    .imbx_pending_o            ( imbx_pending                  ),
    .imbx_irq_ready_o          ( hostif_event_intr_ready       ),
    .imbx_irq_abort_o          ( hostif_event_intr_abort       ),
    .imbx_status_busy_update_o ( imbx_status_busy_valid        ),
    .imbx_status_busy_o        ( imbx_status_busy              ),

    .hostif_control_abort_set_i ( hostif_control_abort_set     ),
    .hostif_status_busy_clear_i ( hostif_status_busy_clear     ),
    .hostif_status_error_set_i  ( hostif_status_error_set      ),

    .hostif_range_valid_i       ( hostif_address_range_valid   ),
    .hostif_base_i              ( hostif_imbx_base             ),
    .hostif_limit_i             ( hostif_imbx_limit            ),
    // Interface to the system port
    .sysif_status_busy_i        ( sysif_status_busy            ),
    .sysif_control_go_set_i     ( sysif_control_go_set         ),
    .sysif_control_abort_set_i  ( sysif_control_abort_set      ),
    .sysif_data_write_valid_i   ( sysif_write_data_write_valid ),
    // Host interface to access private SRAM
    .hostif_sram_write_req_o    ( imbx_sram_write_req          ),
    .hostif_sram_write_gnt_i    ( imbx_sram_write_gnt          ),
    .hostif_sram_write_ptr_o    ( imbx_sram_write_ptr          )
  );

  // Host port connection to access the private SRAM.
  // Arbitrates between inbound and outbound mailbox
  mbx_sramrwarb #(
    .CfgSramAddrWidth( CfgSramAddrWidth ),
    .CfgSramDataWidth( CfgSramDataWidth )
  ) u_sramrwarb (
    .clk_i                     ( clk_i                    ),
    .rst_ni                    ( rst_ni                   ),
    .tl_host_o                 ( tl_sram_o                ),
    .tl_host_i                 ( tl_sram_i                ),
    .intg_err_o                ( tl_sram_intg_err         ),
    // Interface to the inbound mailbox
    .imbx_sram_write_req_i     ( imbx_sram_write_req      ),
    .imbx_sram_write_gnt_o     ( imbx_sram_write_gnt      ),
    .imbx_sram_write_ptr_i     ( imbx_sram_write_ptr      ),
    .imbx_sram_write_resp_vld_o( imbx_sram_write_resp_vld ),
    .imbx_write_data_i         ( sysif_write_data         ),
    // Interface to the outbound mailbox
    .ombx_sram_read_req_i      ( ombx_sram_read_req       ),
    .ombx_sram_read_gnt_o      ( ombx_sram_read_gnt       ),
    .ombx_sram_read_ptr_i      ( ombx_sram_read_ptr       ),
    .ombx_sram_read_resp_vld_o ( ombx_sram_read_resp_vld  ),
    .ombx_sram_read_resp_o     ( sysif_read_data          )
  );

endmodule
