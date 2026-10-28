`timescale 1ns / 1ps

module efpga_alu4_basys3_top (
    input  wire        clk100mhz,
    input  wire        btnC,
    input  wire [15:0] sw,
    output wire [15:0] led
);

    // =====================================================
    // CUSTOM eFPGA ALU CONFIGURATION: 956 BITS
    // =====================================================
    localparam [955:0] ALU4_EFPGA_CONFIG =
        956'hCDB6DB2491802493892693493893C94063BE656516FBFE179A0BA6FF0D32D9D37F8B2E82712693493893C94063BE656516FBFE179A0BA6FF0D32D9D37F8B2E824E2693493893C94067BE656516FBFE179A0BA6FF0D32D9D37F8B2E82492693492492494063BE656516FBFE179A0BBEFF0D32D9DF7F8B2E8;

    // =====================================================
    // RESET
    // Basys 3 center button BTN C is active HIGH.
    // The custom fabric reset rst_n is active LOW.
    // =====================================================
    wire rst_n = ~btnC;

    // =====================================================
    // CONFIGURATION LOADER
    // Loads all 956 bits into the custom eFPGA.
    // =====================================================
    localparam [1:0] ST_LOAD  = 2'd0;
    localparam [1:0] ST_LATCH = 2'd1;
    localparam [1:0] ST_DONE  = 2'd2;

    reg [9:0] cfg_index;
    reg [1:0] cfg_state;

    reg cfg_write;
    reg cfg_valid;
    reg config_done;

    wire cfg_data = ALU4_EFPGA_CONFIG[cfg_index];

    always @(posedge clk100mhz or negedge rst_n) begin
        if (!rst_n) begin
            cfg_index   <= 10'd0;
            cfg_state   <= ST_LOAD;
            cfg_write   <= 1'b1;
            cfg_valid   <= 1'b0;
            config_done <= 1'b0;
        end
        else begin
            case (cfg_state)

                ST_LOAD: begin
                    cfg_write <= 1'b1;
                    cfg_valid <= 1'b0;

                    if (cfg_index == 10'd955) begin
                        cfg_write <= 1'b0;
                        cfg_valid <= 1'b1;
                        cfg_state <= ST_LATCH;
                    end
                    else begin
                        cfg_index <= cfg_index + 10'd1;
                    end
                end

                ST_LATCH: begin
                    cfg_write   <= 1'b0;
                    cfg_valid   <= 1'b0;
                    config_done <= 1'b1;
                    cfg_state   <= ST_DONE;
                end

                ST_DONE: begin
                    cfg_write <= 1'b0;
                    cfg_valid <= 1'b0;
                end

                default: begin
                    cfg_write <= 1'b0;
                    cfg_valid <= 1'b0;
                    cfg_state <= ST_LOAD;
                end

            endcase
        end
    end

    // =====================================================
    // SWITCH INPUT MAPPING
    //
    // SW[3:0]   = Operand A
    // SW[7:4]   = Operand B
    // SW[8]     = Carry input
    // SW[11:9]  = ALU opcode
    // =====================================================
    wire [11:0] user_inputs;

    assign user_inputs = {
        sw[11:9],
        sw[8],
        sw[7:4],
        sw[3:0]
    };

    wire [7:0] user_outputs;

    // =====================================================
    // CUSTOM 4x4 eFPGA FABRIC
    // Module efpga_top is defined in efpga.v.
    // =====================================================
    efpga_top #(
        .N_USER_IN  (12),
        .N_USER_OUT (8)
    ) u_custom_efpga (
        .cfg_clk      (clk100mhz),
        .cfg_data     (cfg_data),
        .cfg_valid    (cfg_valid),
        .cfg_write    (cfg_write),
        .user_clk     (clk100mhz),
        .rst_n        (rst_n),
        .user_inputs  (user_inputs),
        .user_outputs (user_outputs)
    );

    // =====================================================
    // LED OUTPUT MAPPING
    //
    // LED[3:0]  = ALU result
    // LED[4]    = Arithmetic carry output
    // LED[15]   = Configuration complete
    // Other LEDs = OFF
    // =====================================================
    assign led[3:0]  = user_outputs[7:4];
    // LD4 displays carry only for ADD and SUB opcodes.
assign led[4] = (sw[11:9] <= 3'b011)
                ? user_outputs[2]
                : 1'b0;
    assign led[14:5] = 10'b0;
    assign led[15]   = config_done;

endmodule
