
// 4x4 eFPGA fabric with:
//   - 16 LUT4 + DFF tiles
//   - 5x5 switch-box array at routing intersections
//   - continuous horizontal and vertical routing channels
//   - 4 routing tracks per channel direction
//   - four-sided connection to every tile
//   - no wired-OR routing buses
//   - point-to-point routing links between neighboring switch boxes
//   - point-to-point local tile-output links into surrounding switch boxes
//
// Configuration budget:
//   Tile = 16 LUT bits + 1 FF/combinational bit +
//          20 LUT-input select bits + 4 tile-output enable bits = 41 bits
//   SB   = 4 outputs x 3-bit source select = 12 bits
//
//   16 x 41 = 656 bits
//   25 x 12 = 300 bits
//   TOTAL   = 956 bits
module efpga_top #(
    parameter TILE_BITS  = 41,
    parameter SB_BITS    = 12,
    parameter ROW_BITS   = 4*TILE_BITS + 5*SB_BITS, // 224
    parameter TOTAL_BITS = 4*ROW_BITS + 5*SB_BITS,
    parameter N_USER_IN  = 12,
    parameter N_USER_OUT = 8
)(
    input  wire                    cfg_clk,
    input  wire                    cfg_data,
    input  wire                    cfg_valid,
    input  wire                    cfg_write,
    input  wire                    user_clk,
    input  wire                    rst_n,
    input  wire [N_USER_IN-1:0]    user_inputs,
    output wire [N_USER_OUT-1:0]   user_outputs
);

    // ------------------------------------------------------------------------
    // Configuration shift register
    // ------------------------------------------------------------------------
    wire [TOTAL_BITS-1:0] cfg_out;

    config_shift_register #(.TOTAL_BITS(TOTAL_BITS)) u_csr (
        .cfg_clk   (cfg_clk),
        .cfg_data  (cfg_data),
        .shift_en  (cfg_write),
        .cfg_valid (cfg_valid),
        .rst_n     (rst_n),
        .cfg_out   (cfg_out)
    );

    // ------------------------------------------------------------------------
    // Configuration offsets
    // One packed row contains:
    //   4 tile configurations + 5 switch-box configurations
    // ------------------------------------------------------------------------
    function integer tile_offset(input integer row, input integer col);
        tile_offset = (row * ROW_BITS) + (col * TILE_BITS);
    endfunction

    function integer sb_offset(input integer row, input integer col);
        if (row < 4)
            sb_offset = (row * ROW_BITS) + (4*TILE_BITS) + (col * SB_BITS);
        else
            sb_offset = (4 * ROW_BITS) + (col * SB_BITS);
    endfunction

    // ------------------------------------------------------------------------
    // Tile-side channel inputs/outputs
    //
    // Each tile sees BOTH directions of the routing channel on each side:
    //   [7:4] = first direction of the channel (eastbound / southbound)
    //   [3:0] = reverse direction (westbound / northbound)
    //
    // The connection box can select any of 32 channel sources for each LUT
    // input: 8 per side x 4 sides.
    // ------------------------------------------------------------------------
    wire [7:0] tile_north_in [0:3][0:3];
    wire [7:0] tile_east_in  [0:3][0:3];
    wire [7:0] tile_south_in [0:3][0:3];
    wire [7:0] tile_west_in  [0:3][0:3];

    wire tile_north_out [0:3][0:3];
    wire tile_east_out  [0:3][0:3];
    wire tile_south_out [0:3][0:3];
    wire tile_west_out  [0:3][0:3];

    // ------------------------------------------------------------------------
    // Continuous routing channels
    //
    // Horizontal channels live between adjacent SBs in the same row.
    // Vertical channels live between adjacent SBs in the same column.
    // Each physical channel has two explicit directions, so there is never
    // a shared wire with multiple OR-ed drivers.
    // ------------------------------------------------------------------------
    wire [3:0] h_east [0:4][0:3]; // SB(r,c)      -> SB(r,c+1)
    wire [3:0] h_west [0:4][0:3]; // SB(r,c+1)    -> SB(r,c)
    wire [3:0] v_south[0:3][0:4]; // SB(r,c)      -> SB(r+1,c)
    wire [3:0] v_north[0:3][0:4]; // SB(r+1,c)    -> SB(r,c)

    // ------------------------------------------------------------------------
    // Switch-box ports
    // ------------------------------------------------------------------------
    wire [3:0] sb_north_in  [0:4][0:4];
    wire [3:0] sb_south_in  [0:4][0:4];
    wire [3:0] sb_east_in   [0:4][0:4];
    wire [3:0] sb_west_in   [0:4][0:4];

    wire [3:0] sb_north_out [0:4][0:4];
    wire [3:0] sb_south_out [0:4][0:4];
    wire [3:0] sb_east_out  [0:4][0:4];
    wire [3:0] sb_west_out  [0:4][0:4];

    // Four one-bit local tile-output sources available at every SB.
    // A source is tied to 0 when the corresponding surrounding tile does
    // not exist at the fabric boundary.
    wire [3:0] sb_local_in [0:4][0:4];

    genvar r, c;

    // ------------------------------------------------------------------------
    // Point-to-point horizontal channels
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 5; r = r + 1) begin : gen_h_row
            for (c = 0; c < 4; c = c + 1) begin : gen_h_col
                assign h_east[r][c]    = sb_east_out[r][c];
                assign sb_west_in[r][c+1] = h_east[r][c];

                assign h_west[r][c]    = sb_west_out[r][c+1];
                assign sb_east_in[r][c] = h_west[r][c];
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Point-to-point vertical channels
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_v_row
            for (c = 0; c < 5; c = c + 1) begin : gen_v_col
                assign v_south[r][c]    = sb_south_out[r][c];
                assign sb_north_in[r+1][c] = v_south[r][c];

                assign v_north[r][c]    = sb_north_out[r+1][c];
                assign sb_south_in[r][c] = v_north[r][c];
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Tile taps into the routing channels
    //
    // Every tile has four sides. Each side sees both directions of the
    // channel running along that side:
    //
    //   NORTH/SOUTH: horizontal channel pair
    //   EAST/WEST:   vertical channel pair
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_tile_channel_taps_r
            for (c = 0; c < 4; c = c + 1) begin : gen_tile_channel_taps_c
                assign tile_north_in[r][c] = {h_east[r][c], h_west[r][c]};
                assign tile_south_in[r][c] = {h_east[r+1][c], h_west[r+1][c]};
                assign tile_west_in[r][c]  = {v_south[r][c], v_north[r][c]};
                assign tile_east_in[r][c]  = {v_south[r][c+1], v_north[r][c+1]};
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Dedicated point-to-point tile-output links into surrounding SBs.
    //
    // Local source mapping at SB(r,c):
    //   local[0] <- TILE(r,c)       NORTH output
    //   local[1] <- TILE(r,c-1)     EAST output
    //   local[2] <- TILE(r-1,c-1)   SOUTH output
    //   local[3] <- TILE(r-1,c)     WEST output
    //
    // This uses dedicated one-bit wires. No tile outputs are OR-ed together.
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 5; r = r + 1) begin : gen_local_r
            for (c = 0; c < 5; c = c + 1) begin : gen_local_c

                if ((r < 4) && (c < 4)) begin : have_local0
                    assign sb_local_in[r][c][0] = tile_north_out[r][c];
                end else begin : no_local0
                    assign sb_local_in[r][c][0] = 1'b0;
                end

                if ((r < 4) && (c > 0)) begin : have_local1
                    assign sb_local_in[r][c][1] = tile_east_out[r][c-1];
                end else begin : no_local1
                    assign sb_local_in[r][c][1] = 1'b0;
                end

                if ((r > 0) && (c > 0)) begin : have_local2
                    assign sb_local_in[r][c][2] = tile_south_out[r-1][c-1];
                end else begin : no_local2
                    assign sb_local_in[r][c][2] = 1'b0;
                end

                if ((r > 0) && (c < 4)) begin : have_local3
                    assign sb_local_in[r][c][3] = tile_west_out[r-1][c];
                end else begin : no_local3
                    assign sb_local_in[r][c][3] = 1'b0;
                end

            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Tile array
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_tiles_r
            for (c = 0; c < 4; c = c + 1) begin : gen_tiles_c
                tile u_tile (
                    .clk         (user_clk),
                    .rst_n       (rst_n),
                    .north_in    (tile_north_in[r][c]),
                    .east_in     (tile_east_in[r][c]),
                    .south_in    (tile_south_in[r][c]),
                    .west_in     (tile_west_in[r][c]),
                    .north_out   (tile_north_out[r][c]),
                    .east_out    (tile_east_out[r][c]),
                    .south_out   (tile_south_out[r][c]),
                    .west_out    (tile_west_out[r][c]),
                    .cfg_bits    (cfg_out[tile_offset(r,c) +: TILE_BITS])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Switch-box array
    // ------------------------------------------------------------------------
    generate
        for (r = 0; r < 5; r = r + 1) begin : gen_sbs_r
            for (c = 0; c < 5; c = c + 1) begin : gen_sbs_c
                switch_box u_sb (
                    .north_in   (sb_north_in[r][c]),
                    .south_in   (sb_south_in[r][c]),
                    .east_in    (sb_east_in[r][c]),
                    .west_in    (sb_west_in[r][c]),
                    .local_in   (sb_local_in[r][c]),
                    .north_out  (sb_north_out[r][c]),
                    .south_out  (sb_south_out[r][c]),
                    .east_out   (sb_east_out[r][c]),
                    .west_out   (sb_west_out[r][c]),
                    .cfg_bits   (cfg_out[sb_offset(r,c) +: SB_BITS])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Boundary I/O for the 4-bit ALU demonstration
    //
    // user_inputs[3:0]   = A[3:0]
    // user_inputs[7:4]   = B[3:0]
    // user_inputs[8]     = Cin
    // user_inputs[11:9]  = ALU_Sel[2:0]
    //
    // The ALU demo injects A[i], B[i], Sel[1], and (Cin for bit 0 only)
    // at each west-edge SB. Sel[2] and Sel[0] are injected along the east
    // edge on redundant tracks. These are fixed edge-I/O taps for this demo;
    // internal ALU-to-ALU routing still uses the configured switch boxes.
    // ------------------------------------------------------------------------

    // Top boundary inputs are unused by this ALU edge-I/O mapping.
    assign sb_north_in[0][0] = 4'b0000;
    assign sb_north_in[0][1] = 4'b0000;
    assign sb_north_in[0][2] = 4'b0000;
    assign sb_north_in[0][3] = 4'b0000;
    assign sb_north_in[0][4] = 4'b0000;

    // Bottom boundary inputs are unused.
    assign sb_south_in[4][0] = 4'b0000;
    assign sb_south_in[4][1] = 4'b0000;
    assign sb_south_in[4][2] = 4'b0000;
    assign sb_south_in[4][3] = 4'b0000;
    assign sb_south_in[4][4] = 4'b0000;

    // Left boundary: track 0=A[i], track 1=Sel[1], track 2=Cin on row 0
    // (otherwise 0), track 3=B[i]. This gives each bit-slice its operands.
    assign sb_west_in[0][0] = {user_inputs[4], user_inputs[8], user_inputs[10], user_inputs[0]};
    assign sb_west_in[1][0] = {user_inputs[5], 1'b0,             user_inputs[10], user_inputs[1]};
    assign sb_west_in[2][0] = {user_inputs[6], 1'b0,             user_inputs[10], user_inputs[2]};
    assign sb_west_in[3][0] = {user_inputs[7], 1'b0,             user_inputs[10], user_inputs[3]};
    assign sb_west_in[4][0] = 4'b0000;

    // Right boundary: Sel[2] duplicated on tracks 0/1; Sel[0] on tracks 2/3.
    // Duplicating Sel[2] keeps one copy accessible when a result is injected
    // onto one track at a downstream switch box.
    assign sb_east_in[0][4] = {user_inputs[9], user_inputs[9], user_inputs[11], user_inputs[11]};
    assign sb_east_in[1][4] = {user_inputs[9], user_inputs[9], user_inputs[11], user_inputs[11]};
    assign sb_east_in[2][4] = {user_inputs[9], user_inputs[9], user_inputs[11], user_inputs[11]};
    assign sb_east_in[3][4] = {user_inputs[9], user_inputs[9], user_inputs[11], user_inputs[11]};
    assign sb_east_in[4][4] = 4'b0000;

    // Outputs: user_outputs[7:4] = {Result[3:0]}, user_outputs[2] = Cout.
    assign user_outputs[3:0] = sb_south_out[4][1];
    assign user_outputs[7:4] = sb_south_out[4][3];

endmodule


// ============================================================================
// Configuration shift register
// ============================================================================
module config_shift_register #(
    parameter TOTAL_BITS = 956
)(
    input  wire                    cfg_clk,
    input  wire                    cfg_data,
    input  wire                    shift_en,
    input  wire                    cfg_valid,
    input  wire                    rst_n,
    output reg  [TOTAL_BITS-1:0]   cfg_out
);

    (* shreg_extract = "no" *) reg [TOTAL_BITS-1:0] shift_reg;

    always @(posedge cfg_clk or negedge rst_n) begin
        if (!rst_n)
            shift_reg <= {TOTAL_BITS{1'b0}};
        else if (shift_en)
            shift_reg <= {cfg_data, shift_reg[TOTAL_BITS-1:1]};
    end

    always @(posedge cfg_clk or negedge rst_n) begin
        if (!rst_n)
            cfg_out <= {TOTAL_BITS{1'b0}};
        else if (cfg_valid)
            cfg_out <= shift_reg;
    end

endmodule


// ============================================================================
// Four-sided tile
// ============================================================================
module tile (
    input  wire        clk,
    input  wire        rst_n,

    // Eight candidate routing signals on each side:
    // [7:4] = forward direction, [3:0] = reverse direction
    input  wire [7:0]  north_in,
    input  wire [7:0]  east_in,
    input  wire [7:0]  south_in,
    input  wire [7:0]  west_in,

    // One-bit programmable output stub per side
    output wire        north_out,
    output wire        east_out,
    output wire        south_out,
    output wire        west_out,

    // 41 bits:
    //   [15:0] = LUT4 truth table
    //   [16]    = combinational/registered BLE output select
    //   [36:17] = 4 x 5-bit LUT input selectors
    //   [40:37] = north/east/south/west output enables
    input  wire [40:0] cfg_bits
);

    wire        ble_out_wire;
    wire [3:0]  lut_in_wire;

    ble u_ble (
        .lut_in      (lut_in_wire),
        .clk         (clk),
        .rst_n       (rst_n),
        .cfg_lut     (cfg_bits[15:0]),
        .cfg_mux_sel (cfg_bits[16]),
        .ble_out     (ble_out_wire)
    );

    connection_box u_cb (
        .north_in    (north_in),
        .east_in     (east_in),
        .south_in    (south_in),
        .west_in     (west_in),
        .ble_out     (ble_out_wire),
        .cfg_bits    (cfg_bits[40:17]),
        .lut_in      (lut_in_wire),
        .north_out   (north_out),
        .east_out    (east_out),
        .south_out   (south_out),
        .west_out    (west_out)
    );

endmodule


// ============================================================================
// Basic BLE = LUT4 + DFF + output mode select
// ============================================================================
module ble (
    input  wire [3:0]  lut_in,
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_lut,
    input  wire        cfg_mux_sel,
    output wire        ble_out
);

    wire lut_out;
    wire dff_out;

    lut4 u_lut4 (
        .in       (lut_in),
        .cfg_bits (cfg_lut),
        .out      (lut_out)
    );

    dff u_dff (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (lut_out),
        .q     (dff_out)
    );

    assign ble_out = cfg_mux_sel ? dff_out : lut_out;

endmodule


// ============================================================================
// LUT4
// ============================================================================
module lut4 (
    input  wire [3:0]  in,
    input  wire [15:0] cfg_bits,
    output wire        out
);

    assign out = cfg_bits[in];

endmodule


// ============================================================================
// DFF
// ============================================================================
module dff (
    input  wire clk,
    input  wire rst_n,
    input  wire d,
    output reg  q
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= 1'b0;
        else
            q <= d;
    end

endmodule


// ============================================================================
// Four-sided connection box
//
// Each LUT input can select any one of 32 routing candidates:
//   0..7   = west_in[7:0]
//   8..15  = south_in[7:0]
//   16..23 = east_in[7:0]
//   24..31 = north_in[7:0]
//
// Four one-bit output enables independently inject the BLE output into the
// dedicated local wire going to each neighboring switch box.
// ============================================================================
module connection_box (
    input  wire [7:0]  north_in,
    input  wire [7:0]  east_in,
    input  wire [7:0]  south_in,
    input  wire [7:0]  west_in,
    input  wire        ble_out,

    // [19:0] = four 5-bit LUT input selectors
    // [23:20] = north/east/south/west output enables
    input  wire [23:0] cfg_bits,

    output wire [3:0]  lut_in,
    output wire        north_out,
    output wire        east_out,
    output wire        south_out,
    output wire        west_out
);

    wire [31:0] routing_sources;

    assign routing_sources = {north_in, east_in, south_in, west_in};

    assign lut_in[0] = routing_sources[cfg_bits[4:0]];
    assign lut_in[1] = routing_sources[cfg_bits[9:5]];
    assign lut_in[2] = routing_sources[cfg_bits[14:10]];
    assign lut_in[3] = routing_sources[cfg_bits[19:15]];

    assign north_out = ble_out & cfg_bits[20];
    assign east_out  = ble_out & cfg_bits[21];
    assign south_out = ble_out & cfg_bits[22];
    assign west_out  = ble_out & cfg_bits[23];

endmodule


// ============================================================================
// Four-sided switch box
//
// Four output tracks, each with a 3-bit source selector:
//
//   000 = disconnected (safe reset/default state)
//   001 = opposite/straight directional input
//   010 = first turn direction
//   011 = second turn direction
//   100 = local tile source 0
//   101 = local tile source 1
//   110 = local tile source 2
//   111 = local tile source 3
//
// The same-direction input is deliberately not selected, preserving the
// original no-U-turn rule from the 2-bit switch-box version. The disconnected
// code is zero so a reset configuration cannot create a default routing loop.
// ============================================================================
module switch_box (
    input  wire [3:0] north_in,
    input  wire [3:0] south_in,
    input  wire [3:0] east_in,
    input  wire [3:0] west_in,
    input  wire [3:0] local_in,

    output wire [3:0] north_out,
    output wire [3:0] south_out,
    output wire [3:0] east_out,
    output wire [3:0] west_out,

    input  wire [11:0] cfg_bits
);

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : track
            wire [2:0] code = cfg_bits[3*i +: 3];

            // NORTH output: off / S / E / W / local0..3
            assign north_out[i] =
                (code == 3'b000) ? 1'b0      :
                (code == 3'b001) ? south_in[i] :
                (code == 3'b010) ? east_in[i]  :
                (code == 3'b011) ? west_in[i]  :
                (code == 3'b100) ? local_in[0] :
                (code == 3'b101) ? local_in[1] :
                (code == 3'b110) ? local_in[2] :
                                     local_in[3];

            // SOUTH output: off / N / W / E / local0..3
            assign south_out[i] =
                (code == 3'b000) ? 1'b0      :
                (code == 3'b001) ? north_in[i] :
                (code == 3'b010) ? west_in[i]  :
                (code == 3'b011) ? east_in[i]  :
                (code == 3'b100) ? local_in[0] :
                (code == 3'b101) ? local_in[1] :
                (code == 3'b110) ? local_in[2] :
                                     local_in[3];

            // EAST output: off / W / N / S / local0..3
            assign east_out[i] =
                (code == 3'b000) ? 1'b0      :
                (code == 3'b001) ? west_in[i]  :
                (code == 3'b010) ? north_in[i] :
                (code == 3'b011) ? south_in[i] :
                (code == 3'b100) ? local_in[0] :
                (code == 3'b101) ? local_in[1] :
                (code == 3'b110) ? local_in[2] :
                                     local_in[3];

            // WEST output: off / E / S / N / local0..3
            assign west_out[i] =
                (code == 3'b000) ? 1'b0      :
                (code == 3'b001) ? east_in[i]  :
                (code == 3'b010) ? south_in[i] :
                (code == 3'b011) ? north_in[i] :
                (code == 3'b100) ? local_in[0] :
                (code == 3'b101) ? local_in[1] :
                (code == 3'b110) ? local_in[2] :
                                     local_in[3];
        end
    endgenerate

endmodule
