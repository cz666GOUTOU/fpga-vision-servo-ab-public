// Fixed 1000BASE-T full-duplex advertisement, autonegotiation retained.
// No forced master/slave role. PHY address=4 follows supplied board strapping.
// EXT 0x0C RMW: TX bits[7:4]=15 (~2ns); RX bit0=1 (~1.8ns at 1G).
module target_yt8511_ctrl #(
    parameter integer MGMT_CLK_HZ=50000000,
    parameter [4:0] PHY_ADDR=5'd4
)(
    input clk, input rst_n, output reg phy_reset_n,
    output mdc, inout mdio, output reg link_ready,
    output reg phy_error, output reg [31:0] phy_id
);
    wire reset_n;
    target_reset_sync r0(clk,rst_n,reset_n);
    localparam integer DIV0=(MGMT_CLK_HZ+4999999)/5000000;
    localparam integer DIV=(DIV0<1)?1:DIV0;
    reg start;
    wire busy, done, error;
    wire [15:0] rdata;
    reg read_op;
    reg [4:0] addr;
    reg [15:0] wdata, delay_config;
    reg [3:0] step;
    reg [2:0] state;
    reg [31:0] count;
    target_mdio_master #(.HALF_PERIOD(DIV)) m (
        .clk(clk),.reset_n(reset_n),.start(start),.read_op(read_op),
        .phy_addr(PHY_ADDR),.reg_addr(addr),.write_data(wdata),.busy(busy),
        .done(done),.error(error),.read_data(rdata),.mdc(mdc),.mdio(mdio)
    );
    always @* begin
        read_op=0; addr=0; wdata=0;
        case(step)
            0:begin read_op=1; addr=2; end
            1:begin read_op=1; addr=3; end
            2:begin addr=5'h1e; wdata=16'h000c; end
            3:begin read_op=1; addr=5'h1f; end
            4:begin addr=5'h1f; wdata=delay_config; end
            5:begin read_op=1; addr=5'h1f; end
            6:begin addr=4; wdata=16'h0001; end
            7:begin addr=9; wdata=16'h0200; end
            8:begin addr=0; wdata=16'h1200; end
            9:begin read_op=1; addr=5'h11; end
            default:begin read_op=1; addr=2; end
        endcase
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            phy_reset_n<=0; link_ready<=0; phy_error<=0; phy_id<=0;
            start<=0; delay_config<=0; step<=0; state<=0; count<=0;
        end else begin
            start<=0;
            case(state)
                0:begin
                    phy_reset_n<=0; link_ready<=0;
                    if(count>=MGMT_CLK_HZ/10-1) begin
                        phy_reset_n<=1; count<=0; state<=1;
                    end else count<=count+1'b1;
                end
                1:if(count>=MGMT_CLK_HZ/100-1) begin count<=0; step<=0; state<=2; end
                  else count<=count+1'b1;
                2:if(!busy) begin start<=1; state<=3; end
                3:if(done) begin
                    if(error || ((step==0 || step==1) && (rdata==0 || rdata==16'hffff)) ||
                       (step==5 && (rdata & 16'h00f1)!=(delay_config & 16'h00f1))) begin
                        phy_error<=1; link_ready<=0; state<=0; count<=0;
                    end else begin
                        if(step==0) phy_id[31:16]<=rdata;
                        if(step==1) phy_id[15:0]<=rdata;
                        if(step==3) delay_config<=(rdata & 16'hff0e) | 16'h00f1;
                        if(step==9) begin
                            link_ready<=rdata[10] && rdata[11] && rdata[13] && rdata[15:14]==2'b10;
                            state<=4; count<=0;
                        end else begin step<=step+1'b1; state<=2; end
                    end
                end
                4:if(count>=MGMT_CLK_HZ/1000-1) begin count<=0; state<=2; end
                  else count<=count+1'b1;
                default:state<=0;
            endcase
        end
    end
endmodule

// Official-board-compatible PHY control: assert the active-low reset for
// 100 ms, release it, and allow the YT8511 to use its strap/default
// auto-negotiation. No MDIO transaction is used in this startup mode.
// link_ready means the PHY reset/startup sequence is complete; it is not a
// substitute for reading the PHY-specific link status register.
module target_yt8511_ctrl_reset_only #(
    parameter integer MGMT_CLK_HZ=50000000,
    parameter [4:0] PHY_ADDR=5'd4
)(
    input clk, input rst_n, output reg phy_reset_n,
    output mdc, inout mdio, output reg link_ready,
    output reg phy_error, output reg [31:0] phy_id
);
    localparam integer RESET_CYCLES = (MGMT_CLK_HZ/10 < 1) ? 1 : MGMT_CLK_HZ/10;
    localparam integer READY_CYCLES = (MGMT_CLK_HZ/100 < 1) ? 1 : MGMT_CLK_HZ/100;
    reg [31:0] count;
    assign mdc = 1'b0;
    assign mdio = 1'bz;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phy_reset_n <= 1'b0;
            link_ready  <= 1'b0;
            phy_error   <= 1'b0;
            phy_id      <= 32'b0;
            count       <= 32'b0;
        end else if (!phy_reset_n) begin
            link_ready <= 1'b0;
            if (count >= RESET_CYCLES-1) begin
                phy_reset_n <= 1'b1;
                count <= 32'b0;
            end else begin
                count <= count + 1'b1;
            end
        end else if (!link_ready) begin
            if (count >= READY_CYCLES-1) begin
                link_ready <= 1'b1;
                count <= 32'b0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
