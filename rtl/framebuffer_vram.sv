//------------------------------------------------------------------------------
// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, Open Gateware authors and contributors
//------------------------------------------------------------------------------
//
// Copyright (c) 2023, Marcus Jordan Andrade <marcus@opengateware.org>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
// 
//   * Redistributions in synthesized form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in the
//     documentation and/or other materials provided with the distribution.
// 
//   * Neither the name of the author nor the names of other contributors may
//     be used to endorse or promote products derived from this software without
//     specific prior written permission.
//
// THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
//------------------------------------------------------------------------------
// Generic Simple Dual-Port RAM (Dual Clock)
//
// Defines a dual-ported memory with separate write and read ports.
// Uses 1-write-1-read (1W1R) architecture with common data width on both ports.
// Each port has its own clock and is separately addressed.
//------------------------------------------------------------------------------

`default_nettype none

module framebuffer_vram
    #(
         parameter WIDHT           = 320,     //! Data Port Width
         parameter HEIGHT          = 240,     //! Data Port Width
         parameter DW              = 8,       //! Data Port Width
         // Used as attributes, not values
         parameter rStyle          = "no_rw_check",
         parameter rwAddrCollision = "auto"
     ) (
         // Port A (Write)
         input  logic          wr_clk,  //! Write Clock
         input  logic          wr_en,   //! Write Enable
         input  logic [AW-1:0] wr_addr, //! Write Address
         input  logic [DW-1:0] wr_d,    //! Write Data Bus
         // Port B (Read)
         input  logic          rd_clk,  //! Read Clock
         input  logic [AW-1:0] rd_addr, //! Read Address
         output logic [DW-1:0] rd_q     //! Read Data Bus
     );

    initial begin
        rd_q = {DW{1'b0}};
    end

    // Non-user-definable parameters
    localparam AW        = $clog2(WIDHT * HEIGHT); //! Address Port Width

    // Set the ram style to control implementation.
    (* ramstyle          = rStyle *)           // Quartus
    (* ram_style         = rStyle *)           // Vivado
    (* rw_addr_collision = rwAddrCollision *)  // Vivado
    logic [DW-1:0] ram[0:((WIDHT * HEIGHT)-1)]; //! Register to Hold Data

    // Write to Memory on Port A
    always @(posedge wr_clk) begin : WriteToMem
        if(wr_en) begin
            ram[wr_addr] <= wr_d;
        end
    end

    // Read from Memory on Port B
    always @(posedge rd_clk) begin : ReadFromMem
        rd_q <= ram[rd_addr];
    end

endmodule
