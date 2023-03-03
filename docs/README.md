# Video Framebuffer Gateware IP Core

The Video Framebuffer is a SystemVerilog module that is capable of holding a complete screen image before it is processed by the scandoubler and is useful for IP cores that require screen rotation or standard timings for HDMI.

## Features

- Vendor neutral
- Supports `640x480`, `720x480`, `800x600` and `1024x768` resolutions
- Supports `90º CW`, `180º CW` and `90º CCW` screen rotation
- Double buffering to avoid screen tearing
- Generate standard timings for HDMI/TMDS

## Usage

> Note: This module requires a significant amount of Block RAM (BRAM)

It is possible to use only the pixel clock to drive input and memory buffer
writes, which resolves the issue of a core missing the last line (eg. Donkey Kong).

However, some cores may not work properly with this method (eg. Galaga) and require the usage of the system clock.
If you want to use this approach, you can do so by enabling the `SYS_CLK`.

The formula `(WIDTH * HEIGHT * VIDEO_DATA_WIDTH)` can used to calculate the number of memory bits required for a framebuffer. If double buffering is enabled, the memory requirement will be double.

### VGA Video Clock

To use `clk_vga`, there are some rules you need to follow depending on whether
you are rotating the image or not.

#### If you're not rotating the image

| Width   | Height  | Required Clock | Scale Factor | Output Resolution |
| ------: | ------: | :------------- | ------------ | :---------------- |
| `<=320` | `<=240` | `25.2 MHz`     | 2x           | `640x480`         |
| `<=360` | `<=240` | `27.0 MHz`     | 2x           | `720x480` [2]     |
| `<=400` | `<=300` | `40.0 MHz`     | 2x           | `800x600`         |
| ` >400` | ` >300` | `25.2 MHz`     | 1x           | `640x480` [1]     |

#### If you're rotating the image

| Width   | Height  | Required Clock | Scale Factor | Output Resolution |
| ------: | ------: | :------------- | ------------ | :---------------- |
| `<=300` | `<=400` | `40.0 MHz`     | 2x           | `800x600`         |
| `<=384` | `<=512` | `65.0 MHz`     | 2x           | `1024x768`        |
| ` >384` | ` >512` | `40.0 MHz`     | 1x           | `800x600` [1]     |

- [1]: Image won't be scaled.
- [2]: When `WVGA` is set to `1`.

### Screen Rotation

| Rotation             | Value   |
| :------------------- | ------- |
| No Rotation          | `2'b00` |
| 90º Clockwise        | `2'b01` |
| 180º Clockwise       | `2'b10` |
| 90º Counterclockwise | `2'b11` |

### Instantiation

#### Verilog

```v
framebuffer
    #(
        .WIDHT        ( ), // Resolution Width
        .HEIGHT       ( ), // Resolution Height
        .DW           ( ), // Video Data Width
        .BUFF2X       ( ), // Use Double Buffering
        .SYS_CLK      ( ), // Use System Clock
        .WVGA         ( )  // Use Wide VGA 720x480 (3:2 AR)
    ) 
    framebuffer_dut (
        // Clock Input
        .clk_sys      ( ), // System Clock
        .clk_pix      ( ), // Core Pixel Clock
        .clk_vga      ( ), // VGA Output Clock
        // RGB Video Input
        .rgb_in       ( ), // RGB Video Input
        .hblank_in    ( ), // Horizontal Blank
        .vblank_in    ( ), // Vertical Blank
        // RGB Video Output
        .rgb_out      ( ), // RGB Video Output
        .hsync_out    ( ), // Horizontal Sync
        .vsync_out    ( ), // Vertical Sync
        .blank_out    ( ), // Video Blank
        // Control
        .rotate       ( ), // Screen Rotation
        .disable_db   ( ), // Disable Double Buffering (when BUFF2X is enable)
        .odd_line_out ( )  // Odd Line Detector
    );
```

#### VHDL

##### Instance

```vhdl
framebuffer_inst : entity work.framebuffer
    generic map (
        WIDHT        => WIDHT,       -- Resolution Width
        HEIGHT       => HEIGHT,      -- Resolution Height
        DW           => DW,          -- Video Data Width
        BUFF2X       => BUFF2X,      -- Use Double Buffering
        SYS_CLK      => SYS_CLK,     -- Use System Clock
        WVGA         => WVGA         -- Use Wide VGA 720x480 (3:2 AR)
    )
    port map (
        -- Clock Input
        clk_sys      => clk_sys,     -- System Clock
        clk_pix      => clk_pix,     -- Core Pixel Clock
        clk_vga      => clk_vga,     -- VGA Output Clock
        -- RGB Video Input
        rgb_in       => rgb_in,      -- RGB Video Input
        hblank_in    => hblank_in,   -- Horizontal Blank
        vblank_in    => vblank_in,   -- Vertical Blank
        -- RGB Video Output
        rgb_out      => rgb_out,     -- RGB Video Output
        hsync_out    => hsync_out,   -- Horizontal Sync
        vsync_out    => vsync_out,   -- Vertical Sync
        blank_out    => blank_out,   -- Video Blank
        -- Control
        rotate       => rotate,      -- Screen Rotation
        disable_db   => disable_db,  -- Disable Double Buffering (when BUFF2X is enable)
        odd_line_out => odd_line_out -- Odd Line Detector
    );
```

##### Component

```vhdl
component framebuffer
    generic (
        WIDHT   : 320;
        HEIGHT  : 240;
        DW      : 8;
        BUFF2X  : 0;
        SYS_CLK : 0;
        WVGA    : 0
    );
    port (
        -- Clock Input
        clk_sys      : in std_logic;
        clk_pix      : in std_logic;
        clk_vga      : in std_logic;
        -- RGB Video Input
        rgb_in       : in std_logic_vector (DW-1 downto 0);
        hblank_in    : in std_logic;
        vblank_in    : in std_logic;
        -- RGB Video Output
        rgb_out      : out std_logic_vector (DW-1 downto 0);
        hsync_out    : out std_logic;
        vsync_out    : out std_logic;
        blank_out    : out std_logic;
        -- Control
        rotate       : in std_logic_vector (1 downto 0);
        disable_db   : in std_logic;
        odd_line_out : out std_logic
    );
end component;
```

## Documentation

- [Framebuffer](./modules/framebuffer.md)
- [Framebuffer VRAM](./modules/framebuffer_vram.md)
- [Module Netlist](./modules/netlist.svg)

## Changelog

All notable changes are documented in the [CHANGELOG](CHANGELOG.md).

## Credits and acknowledgment

- [Oduvaldo Pavan Junior](https://github.com/ducasp)
- [Victor Trucco](https://gitlab.com/victor.trucco)

## Legal Notices

Copyright (c) 2023, Open Gateware authors and contributors (see AUTHORS file)

This work is licensed under multiple licenses.

- All original source code is licensed under [BSD 3-Clause "New" or "Revised" License](https://spdx.org/licenses/BSD-3-Clause.html) unless implicit indicated.
- All documentation is licensed under [Creative Commons Attribution Share Alike 4.0 International](https://spdx.org/licenses/CC-BY-SA-4.0.html) Public License.
- Some configuration and data files are licensed under [Creative Commons Zero v1.0 Universal](https://spdx.org/licenses/CC0-1.0.html).

Open Gateware and any contributors reserve all others rights, whether under their respective copyrights, patents, or trademarks, whether by implication, estoppel or otherwise.

Individual files may contain the following SPDX license tags as a shorthand for the above copyright and warranty notices:

```text
SPDX-License-Identifier: BSD-3-Clause
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-License-Identifier: CC0-1.0
```

This eases machine processing of licensing information based on the SPDX License Identifiers that are available at [spdx.org/licenses](https://spdx.org/licenses/).

The Open Gateware authors and contributors or any of its maintainers are in no way associated with or endorsed by Intel®, Altera®, AMD®, Xilinx®, Lattice®, GOWIN® or any other company not implicit indicated. All other brands or product names are the property of their respective holders.
