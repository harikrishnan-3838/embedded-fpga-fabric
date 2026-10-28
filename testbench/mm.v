
`timescale 1ns/1ps

module tb_efpga_alu4;

    // Configuration constant: no external .vh file required.
    localparam [955:0] ALU4_EFPGA_CONFIG =
        956'hCDB6DB2491802493892693493893C94063BE656516FBFE179A0BA6FF0D32D9D37F8B2E82712693493893C94063BE656516FBFE179A0BA6FF0D32D9D37F8B2E824E2693493893C94067BE656516FBFE179A0BA6FF0D32D9D37F8B2E82492693492492494063BE656516FBFE179A0BBEFF0D32D9DF7F8B2E8;

    reg cfg_clk, cfg_data, cfg_valid, cfg_write;
    reg user_clk, rst_n;

    reg [11:0] user_inputs;
    wire [7:0] user_outputs;

    reg [955:0] config_word;
    wire [955:0] cfg_monitor;

    // Explicit input drivers
    reg [3:0] A_drive, B_drive;
    reg Cin_drive;
    reg [2:0] opcode_drive;
    reg sub_select;

    integer i;
    integer op_i, a_i, b_i, cin_i;
    integer passed, failed, shown_failures;

    reg [4:0] arithmetic;
    reg [3:0] expected_result;
    reg expected_cout;
    reg [3:0] logic_result;

    efpga_top #(
        .N_USER_IN(12),
        .N_USER_OUT(8)
    ) dut (
        .cfg_clk(cfg_clk),
        .cfg_data(cfg_data),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .user_clk(user_clk),
        .rst_n(rst_n),
        .user_inputs(user_inputs),
        .user_outputs(user_outputs)
    );

    assign cfg_monitor = dut.cfg_out;

    always #5 cfg_clk = ~cfg_clk;
    always #5 user_clk = ~user_clk;

    initial begin
        cfg_clk = 0;
        cfg_data = 0;
        cfg_valid = 0;
        cfg_write = 0;
        user_clk = 0;
        rst_n = 0;
        user_inputs = 0;

        A_drive = 0;
        B_drive = 0;
        Cin_drive = 0;
        opcode_drive = 0;
        sub_select = 0;

        config_word = ALU4_EFPGA_CONFIG;

        passed = 0;
        failed = 0;
        shown_failures = 0;

        $display("============================================");
        $display("CUSTOM 4x4 eFPGA - 4-BIT ALU TEST");
        $display("4096 combinations");
        $display("============================================");

        // Reset, then configure the fabric.
        repeat (3) @(posedge cfg_clk);
        @(negedge cfg_clk);
        rst_n = 1;

        $display("Loading 956 configuration bits...");

        for (i = 0; i < 956; i = i + 1) begin
            @(negedge cfg_clk);
            cfg_write = 1;
            cfg_valid = 0;
            cfg_data = config_word[i];
            @(posedge cfg_clk);
        end

        // Latch the configuration.
        @(negedge cfg_clk);
        cfg_write = 0;
        cfg_data = 0;
        cfg_valid = 1;

        @(posedge cfg_clk);
        #1;

        if (cfg_monitor === config_word) begin
            $display("PASS: all 956 configuration bits loaded.");
        end else begin
            $display("FAIL: configuration register mismatch.");
            $display("Expected = %h", config_word);
            $display("Actual   = %h", cfg_monitor);
            failed = failed + 1;
        end

        @(negedge cfg_clk);
        cfg_valid = 0;

        // Opcode mapping:
        // 0,1: ADD; 2,3: SUB; 4: AND; 5: OR; 6: XOR; 7: NOT A.

        for (op_i = 0; op_i < 8; op_i = op_i + 1) begin
            for (a_i = 0; a_i < 16; a_i = a_i + 1) begin
                for (b_i = 0; b_i < 16; b_i = b_i + 1) begin
                    for (cin_i = 0; cin_i < 2; cin_i = cin_i + 1) begin

                        @(negedge user_clk);

                        // Convert the loop indices into known-width registers.
                        opcode_drive = op_i;
                        A_drive = a_i;
                        B_drive = b_i;
                        Cin_drive = cin_i;

                        // Drive each input field separately.
                        user_inputs[11:9] = opcode_drive;
                        user_inputs[8] = Cin_drive;
                        user_inputs[7:4] = B_drive;
                        user_inputs[3:0] = A_drive;

                        #2;

                        // Stop immediately if the testbench itself drives X/Z.
                        if ((^user_inputs) === 1'bx) begin
                            $display(
                                "FATAL: unknown test input detected: %h",
                                user_inputs
                            );
                            $finish;
                        end

                        expected_result = 0;
                        expected_cout = 0;
                        arithmetic = 0;
                        logic_result = 0;

                        if (op_i < 4) begin
                            // ADD: A + B + Cin
                            // SUB: A + (~B) + Cin
                            sub_select = (op_i >= 2);

                            arithmetic =
                                {1'b0, A_drive} +
                                {1'b0, (B_drive ^ {4{sub_select}})} +
                                Cin_drive;

                            expected_result = arithmetic[3:0];
                            expected_cout = arithmetic[4];

                            if ((user_outputs[7:4] === expected_result) &&
                                (user_outputs[2] === expected_cout)) begin
                                passed = passed + 1;
                            end else begin
                                failed = failed + 1;

                                if (shown_failures < 20) begin
                                    $display(
                                        "FAIL op=%b A=%h B=%h Cin=%b expR=%h gotR=%h expC=%b gotC=%b input=%h",
                                        opcode_drive, A_drive, B_drive,
                                        Cin_drive, expected_result,
                                        user_outputs[7:4], expected_cout,
                                        user_outputs[2], user_inputs
                                    );
                                    shown_failures = shown_failures + 1;
                                end
                            end

                        end else begin
                            case (op_i)
                                4: logic_result = A_drive & B_drive;
                                5: logic_result = A_drive | B_drive;
                                6: logic_result = A_drive ^ B_drive;
                                7: logic_result = ~A_drive;
                                default: logic_result = 0;
                            endcase

                            expected_result = logic_result;

                            if (user_outputs[7:4] === expected_result) begin
                                passed = passed + 1;
                            end else begin
                                failed = failed + 1;

                                if (shown_failures < 20) begin
                                    $display(
                                        "FAIL op=%b A=%h B=%h Cin=%b expR=%h gotR=%h input=%h",
                                        opcode_drive, A_drive, B_drive,
                                        Cin_drive, expected_result,
                                        user_outputs[7:4], user_inputs
                                    );
                                    shown_failures = shown_failures + 1;
                                end
                            end
                        end

                    end
                end
            end

            $display("Finished opcode %0d: passed=%0d failed=%0d",
                     op_i, passed, failed);
        end

        $display("============================================");
        $display("FINAL: passed=%0d failed=%0d", passed, failed);

        if ((passed == 4096) && (failed == 0))
            $display("PASS: all ALU tests passed.");
        else
            $display("FAIL: inspect the first mismatch.");

        $display("============================================");
        $finish;
    end

endmodule
