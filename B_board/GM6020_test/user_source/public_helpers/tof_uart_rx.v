// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module tof_uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 921_600
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sensor_tx,
    output reg         distance_valid,
    output reg         frame_error,
    output reg [23:0]  distance_mm
);

    // A fractional NCO gives an accurate 16x UART sampling tick at 50 MHz:
    // 50 MHz / (921600 * 16) is not an integer.
    localparam integer NCO_WIDTH = 32;
    localparam [63:0] NCO_MODULUS = 64'd4294967296;
    localparam [63:0] BAUD_TICK_INC =
        ((64'd1 << NCO_WIDTH) * BAUD_RATE * 16) / CLK_FREQ_HZ;

    reg [31:0] baud_accum;
    reg        baud_tick;

    reg sensor_tx_meta;
    reg sensor_tx_sync;

    localparam [1:0] UART_IDLE  = 2'd0;
    localparam [1:0] UART_START = 2'd1;
    localparam [1:0] UART_DATA  = 2'd2;
    localparam [1:0] UART_STOP  = 2'd3;

    reg [1:0] uart_state;
    reg [3:0] oversample_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;
    reg [7:0] rx_byte;
    reg       rx_byte_valid;
    reg       uart_error;

    reg [7:0] frame_buf [0:15];
    reg [4:0] frame_index;
    reg [7:0] frame_sum;
    reg       frame_active;
    reg measurement_valid;
    reg measurement_error;
    integer   i;

    // Synchronize the sensor input and generate the fractional baud tick.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sensor_tx_meta <= 1'b1;
            sensor_tx_sync <= 1'b1;
            baud_accum     <= 32'd0;
            baud_tick      <= 1'b0;
        end else begin
            sensor_tx_meta <= sensor_tx;
            sensor_tx_sync <= sensor_tx_meta;

            baud_tick <= 1'b0;
            if (({32'd0, baud_accum} + BAUD_TICK_INC) >= NCO_MODULUS) begin
                baud_accum <= {32'd0, baud_accum} + BAUD_TICK_INC - NCO_MODULUS;
                baud_tick  <= 1'b1;
            end else begin
                baud_accum <= baud_accum + BAUD_TICK_INC;
            end
        end
    end

    // 16x oversampled, 8N1 UART receiver.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_state       <= UART_IDLE;
            oversample_count <= 4'd0;
            bit_index        <= 3'd0;
            rx_shift         <= 8'd0;
            rx_byte          <= 8'd0;
            rx_byte_valid    <= 1'b0;
            uart_error       <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            uart_error    <= 1'b0;

            case (uart_state)
                UART_IDLE: begin
                    oversample_count <= 4'd0;
                    if (!sensor_tx_sync) begin
                        uart_state <= UART_START;
                    end
                end

                UART_START: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd7) begin
                            oversample_count <= 4'd0;
                            if (!sensor_tx_sync) begin
                                uart_state <= UART_DATA;
                                bit_index  <= 3'd0;
                            end else begin
                                uart_state <= UART_IDLE;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                UART_DATA: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd15) begin
                            oversample_count       <= 4'd0;
                            rx_shift[bit_index]   <= sensor_tx_sync;
                            if (bit_index == 3'd7) begin
                                uart_state <= UART_STOP;
                            end else begin
                                bit_index <= bit_index + 3'd1;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                UART_STOP: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd15) begin
                            oversample_count <= 4'd0;
                            uart_state       <= UART_IDLE;
                            if (sensor_tx_sync) begin
                                rx_byte       <= rx_shift;
                                rx_byte_valid <= 1'b1;
                            end else begin
                                uart_error <= 1'b1;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                default: uart_state <= UART_IDLE;
            endcase
        end
    end

    // Parse NLink_TOFSense_Frame0. The byte layout is:
    // 57 00 reserved id time[31:0] distance[23:0] status
    // signal_strength[15:0] range_precision checksum
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_index    <= 5'd0;
            frame_sum      <= 8'd0;
            frame_active   <= 1'b0;
            measurement_valid <= 1'b0;
            distance_mm    <= 24'd0;
            measurement_error <= 1'b0;
            distance_valid <= 1'b0;
            frame_error    <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                frame_buf[i] <= 8'd0;
            end
        end else begin
            measurement_valid <= 1'b0;
            measurement_error <= uart_error;
            distance_valid    <= 1'b0;
            frame_error       <= uart_error;

            if (rx_byte_valid) begin
                if (!frame_active) begin
                    if (rx_byte == 8'h57) begin
                        frame_active    <= 1'b1;
                        frame_index     <= 5'd1;
                        frame_sum       <= 8'h57;
                        frame_buf[0]    <= 8'h57;
                    end
                end else begin
                    frame_buf[frame_index[3:0]] <= rx_byte;

                    if (frame_index < 5'd15) begin
                        frame_sum  <= frame_sum + rx_byte;
                        frame_index <= frame_index + 5'd1;
                    end else begin
                        // At index 15 rx_byte is the checksum, so frame_sum
                        // still contains the sum of bytes 0..14.
                        // Require function 0x00 and a valid checksum.  The
                        // sensor's status byte is retained in the frame but
                        // is model-dependent, so it must not reject a frame.
                        if ((frame_sum == rx_byte) &&
                            (frame_buf[1] == 8'h00)) begin
                            distance_mm    <= {frame_buf[10], frame_buf[9], frame_buf[8]};
                            measurement_valid <= 1'b1;
                            distance_valid <= 1'b1;
                        end else begin
                            measurement_error <= 1'b1;
                            frame_error <= 1'b1;
                        end
                        frame_active <= 1'b0;
                        frame_index  <= 5'd0;
                        frame_sum    <= 8'd0;
                    end
                end
            end
        end
    end

endmodule
