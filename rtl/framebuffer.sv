//------------------------------------------------------------------------------
// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, Open Gateware authors and contributors
//------------------------------------------------------------------------------
//
// Copyright (c) 2023, Marcus Jordan Andrade <marcus@opengateware.org>
// Copyright (c) 2021, Oduvaldo Pavan Junior <ducasp@gmail.com>
// Copyright (c) 2017, Victor Trucco <victor.trucco@gmail.com>
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

`default_nettype none

module framebuffer
    #(
         parameter             WIDHT   = 320, //! Resolution Width
         parameter             HEIGHT  = 240, //! Resolution Height
         parameter             DW      = 8,   //! Video Data Width
         parameter             BUFF2X  = 0,   //! Use Double Buffering
         parameter             SYS_CLK = 0,   //! Use System Clock
         parameter             WVGA    = 0    //! Use Wide VGA 720x480 (3:2 AR)
     ) (
         // Clocks
         input  logic          clk_sys,       //! System Clock
         input  logic          clk_pix,       //! Core Pixel Clock
         input  logic          clk_vga,       //! VGA Output Clock
         // Video Input
         input  logic [DW-1:0] rgb_in,        //! RGB Video Input
         input  logic          hblank_in,     //! Horizontal Blank
         input  logic          vblank_in,     //! Vertical Blank
         // Video Output
         output logic [DW-1:0] rgb_out,       //! RGB Video Output
         output logic          hsync_out,     //! Horizontal Sync
         output logic          vsync_out,     //! Vertical Sync
         output logic          blank_out,     //! Video Blank
         // Control
         input  logic    [1:0] rotate,        //! Screen Rotation: [0] No Rotation - [1] 90 CW - [2] 180 CW - [3] 90 CCW
         input  logic          disable_db,    //! Disable Double Buffering
         output logic          odd_line_out   //! Odd Line Detector
     );

    // Video Data
    reg  [AW-1:0] pixel_wr_addr;              //! The input video process is responsible for writing the pixel data into the correct buffer address
    reg  [AW-1:0] pixel_rd_addr;              //! The output video process is responsible for reading the correct pixel data to display on the screen
    wire [DW-1:0] pixel_data1;                //! The pixel data that is currently being output from buffer 1
    wire [DW-1:0] pixel_data2;                //! The pixel data that is currently being output from buffer 2
    reg           pixel_de;                   //! The output video process is currently displaying the image on the screen
    wire          pixel_clock;                //! Internal Pixel Clock will use clk_pix or clk_sys if [SYS_CLK] is enable

    // Framebuffer Control
    reg           active_buffer  = 1'b1;      //! Using either buffer 1 or buffer 2 to output video

    // Framebuffer #1
    reg           buffer1_wren;               //! Buffer 1 is ready to receive new pixel data
    reg           buffer1_writing = 1'b0;     //! Writing new pixel data into buffer 1
    reg           buffer1_clr     = 1'b0;     //! The buffer has been fully used, so that it can be cleared and used again
    reg           buffer1_ready   = 1'b1;     //! First buffer is completely filled with pixel data

    // Framebuffer #2
    reg           buffer2_wren;               //! Buffer 2 is ready to receive new pixel data
    reg           buffer2_writing = 1'b1;     //! The system is currently writing new pixel data into buffer 2
    reg           buffer2_clr     = 1'b0;     //! The buffer has been fully used, so that it can be cleared and used again
    reg           buffer2_ready   = 1'b0;     //! Second buffer is completely filled with pixel data.

    // Counters
    reg     [9:0] window_hcnt = 0;            //! Horizontal position of the pixel currently being displayed on the screen, with a maximum width of 1024 pixels
    reg     [9:0] window_vcnt = 0;            //! Vertical position of the line currently being displayed on the screen, with a maximum height of 1024 lines
    reg    [10:0] hcnt        = 0;            //! Total number of pixels that are being output, including those that are not currently visible on the screen, with a maximum count of 2048 pixels
    reg    [10:0] vcnt        = 0;            //! Total number of lines that are being output, including those that are not currently visible on the screen, with a maximum count of 2048 lines
    reg     [9:0] i_hcnt      = 0;            //! Input Pixel Count, up to 1024 Pixels
    reg     [8:0] i_vcnt      = 0;            //! Input Line Count, up to 512 Lines

    // Modeline Variables
    integer h_active,     v_active;           //! Horizontal/Vertical Active Pixels
    integer h_sync_start, v_sync_start;       //! Horizontal/Vertical Sync Start
    integer h_sync_end,   v_sync_end;         //! Horizontal/Vertical Sync End
    integer h_total,      v_total;            //! Horizontal/Vertical Total Pixels

    // Output Scaling Factors
    integer h_scale, h_scale_cnt;             //! Horizontal Scale Factor and Counter
    integer v_scale, v_scale_cnt;             //! Vertical Scale Factor and Counter

    // Video Positioning
    integer h_pos_start, v_pos_start;         //! Initial X/Y Position on Output Screen
    integer h_pos_end,   v_pos_end;           //! Final   X/Y Position on Output Screen

    // Non-user-definable parameters
    localparam hc_max = WIDHT;                //! Number of Horizontal Visible Pixels (Before Scandoubler)
    localparam vc_max = HEIGHT;               //! Number of Vertical   Visible Pixels (Before Scandoubler)
    localparam AW = $clog2(WIDHT * HEIGHT);   //! Minimum width required to address the number of pixels for a given framebuffer.

    assign pixel_clock = SYS_CLK == 1 ? clk_sys : clk_pix;

    // Manages the process of buffer writing, and controls the horizontal and vertical counts with respect to the pixel clock and blank signals.
    // Additionally, it computes the memory address to write the next pixel from the input.
    always @(posedge pixel_clock) begin : BufferWriteControl
        reg  [1:0] edge_hs;
        reg  [1:0] edge_vs;
        reg  [1:0] edge_cb1;
        reg  [1:0] edge_cb2;
        reg  [1:0] edge_clk_ena;
        reg [18:0] wr_result_v;

        // Since the Write signal is only active for a short duration, we need to reset it after every pixel clock cycle.
        // This ensures that the Write signal is ready to be triggered again for the next pixel when it arrives.
        // In other words, resetting the Write signal at every pixel clock cycle guarantees that we don't miss any pixel
        // data and that the system is ready to receive new pixel data when it arrives.
        buffer1_wren <= 1'b0;
        buffer2_wren <= 1'b0;

        // The "buffer clear" operation is performed concurrently with the "buffer fill" operation.
        // The process responsible for "clearing" the buffer, which is the output process, operates
        // on a separate clock cycle. To ensure the proper functioning, we need to detect any changes
        // in the signal that the output process uses to indicate the need to clear the buffer.
        edge_cb1 = {edge_cb1[0],buffer1_clr};
        edge_cb2 = {edge_cb2[0],buffer2_clr};
        if(edge_cb1 == 2'b01) begin buffer1_ready <= 1'b0; end // Output is done with buffer 1, can be used to write new data
        if(edge_cb2 == 2'b01) begin buffer2_ready <= 1'b0; end // Output is done with buffer 2, can be used to write new data

        edge_clk_ena = {edge_clk_ena[0],clk_pix};

        if(edge_clk_ena == 2'b01 || SYS_CLK == 0) begin
            // new pixel, so, let's start getting the memory address on our register before we update counters
            wr_result_v = (i_vcnt * hc_max) + i_hcnt;
            // and move that value to the address vector of framebuffers write operation
            pixel_wr_addr <= wr_result_v[AW-1:0];

            edge_hs = {edge_hs[0], hblank_in}; // Are we on Hblank?
            edge_vs = {edge_vs[0], vblank_in}; // or on Vblank?

            i_hcnt <= i_hcnt + 1;              // Update horizontal input counter

            if(edge_vs == 2'b01) begin
                // Vertical Blanking started, that means, frame is done
                // Let's mark as ready any buffer that was being written
                if(buffer2_writing) begin
                    buffer2_writing <= 1'b0;
                    buffer2_ready   <= 1'b1;
                end
                else if(buffer1_writing) begin
                    buffer1_writing <= 1'b0;
                    buffer1_ready   <= 1'b1;
                end
            end

            if(edge_vs == 2'b10) begin
                // Once the Vertical Blanking period has finished, we request to write to any empty buffer that is available.
                // A buffer can be written to only if it satisfies the following conditions:
                // 1 - It is not currently being used by the display output. The flag active_buffer being high indicates that buffer 1 is currently being used, whereas being low indicates that buffer 2 is being used.
                // 2 - It is not currently being written to. Note that the flag set earlier will take effect only on the next edge, not the current one.
                // 3 - It is not marked as ready. This flag is cleared by the display output when it switches buffers to avoid tearing.
                if     (!buffer1_ready && !buffer1_writing) begin buffer1_writing <= 1'b1; end
                else if(!buffer2_ready && !buffer2_writing) begin buffer2_writing <= 1'b1; end
            end

            if(hblank_in) begin i_hcnt <= 0; end // Horizontal Blank, so after blank is finished, horizontal counter is back to 0
            if(vblank_in) begin i_vcnt <= 0; end // Vertical Blank, so after blank is finished, vertical input counter is back to 0

            // Horizontal Blanking started, so this line is finished and we are count to the next one
            if(edge_hs == 2'b01) begin i_vcnt <= i_vcnt + 1; end // update vertical input count

            // If there is no blank period, meaning that the display is currently active, the pixel should be written to the buffer.
            if(hblank_in == 1'b0 && vblank_in == 1'b0) begin
                // If a double frame buffer is being used, we need to determine which buffer is currently active.
                if(!disable_db && BUFF2X != 0) begin
                    if(buffer1_writing) begin      // If we are writing to the first buffer,
                        buffer1_wren <= 1'b1;      // we must enable memory buffer 1 to receive the pixel data
                        buffer2_wren <= 1'b0;      // and ensure that memory buffer 2 is not being written to at the same time.
                    end
                    else if(buffer2_writing) begin // On the other hand, if we are writing to the second buffer,
                        buffer1_wren <= 1'b0;      // we need to make sure that memory buffer 1 is not being written to
                        buffer2_wren <= 1'b1;      // and enable memory buffer 2 to receive the pixel data.
                    end
                    else begin
                        // If neither buffer is ready to be used, due to both buffers being occupied or otherwise unavailable,
                        // the pixel data cannot be stored and must be discarded.
                        buffer1_wren <= 1'b0;
                        buffer2_wren <= 1'b0;
                    end
                end
                else begin
                    // If only a single buffer is being used and there is no synchronization required, we are always writing to buffer number 1.
                    buffer1_wren    <= 1'b1; // We need to set the buffer1_wren signal to 1 to indicate that we are writing to buffer 1.
                    buffer1_ready   <= 1'b1; // Buffer 1 is always ready to be displayed in single buffer mode, so we set buffer1_ready signal to 1.
                    buffer2_ready   <= 1'b0; // On the other hand, since we are not using buffer 2, we set buffer2_ready signal to 0.
                    buffer1_writing <= 1'b0; // Additionally, we need to set the buffer1_writing signal to 0 to indicate that we are not currently writing to buffer 1.
                    buffer2_writing <= 1'b1; // Moreover, to avoid any potential issues in case a double framebuffer is later enabled, we set the buffer2_writing signal to 1.
                                             // This will ensure that the logic won't get stuck, and the system can be easily switched to double buffer mode if required.
                end
            end
            else begin
                // if on any blank period, nothing to write to any memory buffer
                buffer1_wren <= 1'b0;
                buffer2_wren <= 1'b0;
            end
        end
    end

    // The timings follow the VESA Discrete Monitor Timings (DMT) standard
    // ModeLine " 640x480@60"  25.20  640  656  752  800  480  490  492  525 -HSync -VSync
    // ModeLine " 720x480@60"  27.00  720  736  798  858  480  489  495  525 -HSync -VSync
    // Modeline " 800x600@60"  40.00  800  840  968 1056  600  601  605  628 +HSync +VSync
    // ModeLine "1024x768@60"  65.00 1024 1048 1184 1344  768  771  777  806 -HSync -VSync

    // This process will update the output parameters based on the rotation and input information
    // Driven by the output pixel clock
    always @(posedge clk_vga) begin : ModelineSelection
        if(vcnt == v_total[10:0]) begin
            if(rotate[0]) begin
                // Time to check for rotated resolution we should be using....
                if((vc_max <= 400) && (hc_max <= 300)) begin
                    // Will use 800x600
                    h_active     <= 800 - 1;                    // Visible Area
                    h_sync_start <= 840 - 1;                    // HSYNC pulse starts
                    h_sync_end   <= 968 - 1;                    // HSYNC pulse ends
                    h_total      <= 1056 - 1;                   // Total Pixels per line
                    v_active     <= 600 - 1;                    // Visible Area
                    v_sync_start <= 601 - 1;                    // VSYNC pulse starts
                    v_sync_end   <= 605 - 1;                    // VSYNC pulse ends
                    v_total      <= 628 - 1;                    // Total lines per screen
                    h_pos_start  <= (800 - (HEIGHT * 2)) / 2;   // Initial X Position to center image
                    v_pos_start  <= (600 - (WIDHT * 2)) / 2;    // Initial Y Position to center image
                    h_pos_end    <= h_pos_start + (vc_max * 2); // Final X position
                    v_pos_end    <= v_pos_start + (hc_max * 2); // Final Y position
                    h_scale      <= 2;                          // Horizontal Scale
                    v_scale      <= 2;                          // Vertical Scale
                end
                else if((vc_max <= 512) && (hc_max <= 384)) begin
                    // Will use 1024x768
                    h_active     <= 1024 - 1;
                    h_sync_start <= 1048 - 1;
                    h_sync_end   <= 1184 - 1;
                    h_total      <= 1344 - 1;
                    v_active     <= 768 - 1;
                    v_sync_start <= 771 - 1;
                    v_sync_end   <= 777 - 1;
                    v_total      <= 806 - 1;
                    h_pos_start  <= (1024 - (HEIGHT * 2)) / 2;
                    v_pos_start  <= (768 - (WIDHT * 2)) / 2;
                    h_pos_end    <= h_pos_start + (vc_max * 2); 
                    v_pos_end    <= v_pos_start + (hc_max * 2); 
                    h_scale      <= 2;
                    v_scale      <= 2;
                end
                else begin // Large resolution, won't scale
                    // Will use 800x600
                    h_active     <= 800 - 1;
                    h_sync_start <= 840 - 1;
                    h_sync_end   <= 968 - 1;
                    h_total      <= 1056 - 1;
                    v_active     <= 600 - 1;
                    v_sync_start <= 601 - 1;
                    v_sync_end   <= 605 - 1;
                    v_total      <= 628 - 1;
                    h_pos_start  <= (800 - HEIGHT) / 2;
                    v_pos_start  <= (600 - WIDHT) / 2;
                    h_pos_end    <= h_pos_start + vc_max;
                    v_pos_end    <= v_pos_start + hc_max;
                    h_scale      <= 1;
                    v_scale      <= 1;
                end
            end
            else begin
                // Time to check for non-rotated resolution we should be using....
                if((hc_max <= 320) && (vc_max <= 240) && (WVGA == 0)) begin
                    // Will use 640x480
                    h_active     <= 640 - 1;
                    h_sync_start <= 656 - 1;
                    h_sync_end   <= 752 - 1;
                    h_total      <= 800 - 1;
                    v_active     <= 480 - 1;
                    v_sync_start <= 490 - 1;
                    v_sync_end   <= 492 - 1;
                    v_total      <= 525 - 1;
                    h_pos_start  <= (640 - (WIDHT * 2)) / 2;
                    v_pos_start  <= (480 - (HEIGHT * 2)) / 2;
                    h_pos_end    <= h_pos_start + (hc_max * 2); 
                    v_pos_end    <= v_pos_start + (vc_max * 2); 
                    h_scale      <= 2;
                    v_scale      <= 2;
                end
                else if((hc_max <= 360) && (vc_max <= 240) && (WVGA == 1)) begin
                    // Will use 720x480
                    h_active     <= 720 - 1;
                    h_sync_start <= 736 - 1;
                    h_sync_end   <= 798 - 1;
                    h_total      <= 858 - 1;
                    v_active     <= 480 - 1;
                    v_sync_start <= 489 - 1;
                    v_sync_end   <= 495 - 1;
                    v_total      <= 525 - 1;
                    h_pos_start  <= (720 - (WIDHT * 2)) / 2;
                    v_pos_start  <= (480 - (HEIGHT * 2)) / 2;
                    h_pos_end    <= h_pos_start + (hc_max * 2);
                    v_pos_end    <= v_pos_start + (vc_max * 2);
                    h_scale      <= 2;
                    v_scale      <= 2;
                end
                else if((hc_max <= 400) && (vc_max <= 300)) begin
                    // Will use 800x600
                    h_active     <= 800 - 1;
                    h_sync_start <= 840 - 1;
                    h_sync_end   <= 968 - 1;
                    h_total      <= 1056 - 1;
                    v_active     <= 600 - 1;
                    v_sync_start <= 601 - 1;
                    v_sync_end   <= 605 - 1;
                    v_total      <= 628 - 1;
                    h_pos_start  <= (800 - (WIDHT * 2)) / 2;
                    v_pos_start  <= (600 - (HEIGHT * 2)) / 2;
                    h_pos_end    <= h_pos_start + (hc_max * 2);
                    v_pos_end    <= v_pos_start + (vc_max * 2);
                    h_scale      <= 2;
                    v_scale      <= 2;
                end
                else begin // Large resolution, won't scale
                    // Will use 640x480
                    h_active     <= 640 - 1;
                    h_sync_start <= 656 - 1;
                    h_sync_end   <= 752 - 1;
                    h_total      <= 800 - 1;
                    v_active     <= 480 - 1;
                    v_sync_start <= 490 - 1;
                    v_sync_end   <= 492 - 1;
                    v_total      <= 525 - 1;
                    h_pos_start  <= (640 - WIDHT) / 2;
                    v_pos_start  <= (480 - HEIGHT) / 2;
                    h_pos_end    <= h_pos_start + hc_max;
                    v_pos_end    <= v_pos_start + vc_max;
                    h_scale      <= 1;
                    v_scale      <= 1;
                end
            end
        end
    end

    // Buffer #1
    framebuffer_vram #(.WIDHT(WIDHT),.HEIGHT(HEIGHT),.DW(DW)) framebuffer1
                     (
                         .wr_clk  ( pixel_clock   ),
                         .wr_en   ( buffer1_wren  ),
                         .wr_addr ( pixel_wr_addr ),
                         .wr_d    ( rgb_in        ),

                         .rd_clk  ( clk_vga       ),
                         .rd_addr ( pixel_rd_addr ),
                         .rd_q    ( pixel_data1   )
                     );

    // Buffer #2 (when using double buffering)
    generate
        if (BUFF2X != 0) begin
            framebuffer_vram #(.WIDHT(WIDHT),.HEIGHT(HEIGHT),.DW(DW)) framebuffer2
                             (
                                 .wr_clk  ( pixel_clock   ),
                                 .wr_en   ( buffer2_wren  ),
                                 .wr_addr ( pixel_wr_addr ),
                                 .wr_d    ( rgb_in        ),

                                 .rd_clk  ( clk_vga       ),
                                 .rd_addr ( pixel_rd_addr ),
                                 .rd_q    ( pixel_data2   )
                             );
        end
    endgenerate

    // This process keep the pixel and line count, as well keep our internal window count
    always @(posedge clk_vga) begin : PixelCounter
        if(hcnt == h_total) begin
            hcnt <= 0; // We went through all pixels in that line, so cycle back to 0
        end
        else begin
            hcnt <= hcnt + 1; // not in the last pixel, so next pixel
            if(hcnt == h_pos_start) begin
                window_hcnt <= 0; // start of visible area that we are going to draw, our window
                h_scale_cnt <= 1;
            end
            else begin
                if((h_scale_cnt == h_scale)) begin
                    window_hcnt <= window_hcnt + 1; // not the start, just keep increasing it
                    h_scale_cnt <= 1;
                end
                else begin
                    h_scale_cnt <= h_scale_cnt + 1;
                end
            end
        end

        if(hcnt == h_sync_start) begin // Time to make horizontal sync?

            if(vcnt == v_total) begin
                vcnt <= 0; // If last line, then back to first line
                v_scale_cnt <= 1;
            end
            else begin
                vcnt <= vcnt + 1; // not first line, so increase line count
                if(vcnt == v_pos_start) begin
                    window_vcnt <= 0; // start of visible area that we are going to draw, our window
                    v_scale_cnt <= 1;
                end
                else begin
                    if((v_scale_cnt == v_scale)) begin
                        window_vcnt <= window_vcnt + 1; // not the start, just keep increasing it
                        v_scale_cnt <= 1;
                    end
                    else begin
                        v_scale_cnt <= v_scale_cnt + 1;
                    end
                end
            end
        end
    end

    // Computes the memory address to be accessed in the buffer for output.
    // It assumes that the vertical and horizontal window counts are twice the memory count.
    // Therefore, the output will retrieve data from the same location in the buffer twice,
    // effectively doubling both the horizontal and vertical resolution.
    always @(posedge clk_vga) begin : CalculateReadAddress
        reg [18:0] rd_result_v;
        case (rotate)
            // Just the number of pixel being written in the window, so (vcount * number of pixels in line) + hcount
            2'b00: begin rd_result_v = ((                  window_vcnt[8:0])  *  (hc_max)) + (window_hcnt[9:0]);      end // No Rotation
            2'b01: begin rd_result_v = ((((vc_max) - 1) - (window_hcnt[9:0])) *  (hc_max)) + (window_vcnt[8:0]);      end // 90deg  CW
            2'b10: begin rd_result_v = ((( vc_max)      - (window_vcnt[8:0])) *  (hc_max)) - (window_hcnt[9:0])  - 2; end // 180deg CW
            2'b11: begin rd_result_v = ((  hc_max)      * (window_hcnt[9:0])) + ((hc_max)  - (window_vcnt[8:0])) - 1; end // 90deg CCW
        endcase
        // Assign the calculated address position to the buffer read address vector
        pixel_rd_addr <= rd_result_v[AW-1:0];
    end

    // This procedure has the following functions:
    // 1 - Check whether the current position is at the end of the vertical blanking period for the output.
    //     If it is, check whether the buffer being displayed needs to be changed and request that the other buffer be released for input use.
    // 2 - Automatically clear the clear request after a few lines of output have been generated.
    // 3 - Determine the RGB output value, which is 0 if it is in the output blank period or not in the window display area.
    //     Otherwise, assign the output from the appropriate frame buffer to it.
    always @(posedge clk_vga) begin : SetOutputs
        // General output signals assignments

        // Display output blanks after writing visible pixels or reaching end of visible lines.
        blank_out <= ((hcnt > h_active) || (vcnt > v_active)) ? 1'b1 : 1'b0;
        // Display Enable state retrieves visible window data from buffer memory.
        pixel_de  <= ((hcnt > (h_pos_start + 1) && hcnt <= h_pos_end) && (vcnt > v_pos_start && vcnt <= v_pos_end)) ? 1'b1 : 1'b0;
        // Pulse HSYNC in the proper pixel area as defined
        hsync_out <= ((hcnt <= h_sync_start) || (hcnt > h_sync_end)) ? 1'b1 : 1'b0;
        // Pulse VSYNC in the proper line area as defined
        vsync_out <= ((vcnt <= v_sync_start) || (vcnt > v_sync_end)) ? 1'b1 : 1'b0;
        // Odd line detector
        odd_line_out <= vcnt[0];

        if(vcnt == v_total) begin
            // End of output VBLANK
            // Switch buffers as needed so the next output uses the proper buffer
            if(disable_db || BUFF2X == 0) begin
                // Not using double framebuffer, so it is always buffer1, no buffer to clear
                active_buffer <= 1'b1;
                buffer1_clr   <= 1'b0;
                buffer2_clr   <= 1'b0;
            end
            // When switching buffer memory, if the current buffer used for output is available, mark the other buffer as available and request
            // it to be freed for use in the next input frame.
            else if(active_buffer && buffer2_ready) begin
                active_buffer <= 1'b0;
                buffer1_clr   <= 1'b1;
            end
            else if(!active_buffer && buffer1_ready) begin
                active_buffer <= 1'b1;
                buffer2_clr   <= 1'b1;
            end
            // If both buffers are being used or neither, do nothing.
        end

        // Auto clear the buffer_clr request after a few lines have been outputed
        if(vcnt == 30) begin
            buffer1_clr <= 1'b0;
            buffer2_clr <= 1'b0;
        end

        if(pixel_de && (hcnt <= h_active) && (vcnt <= v_active)) begin
            // If the "beam" is on a visible area and the blank signal is not active, then the appropriate buffer memory is redirected to the output.
            rgb_out <= active_buffer ? pixel_data1 : pixel_data2;
        end
        else begin
            // If the system is currently in a blank period, or the "beam" is not on a visible area, then the output will be black, i.e., the value 0.
            rgb_out <= 0;
        end

    end

endmodule
