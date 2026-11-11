// Transparent 8x16 cells. Counts are hexadecimal (00..40), matching commands.
module photo_album_osd #(parameter integer EXTERNAL_FONT=0)(
    input wire clk,rst_n,frame_start,de,album,
    input wire [11:0] x,y,
    input wire [5:0] index,input wire [6:0] count,input wire [3:0] status,
    output reg ink_d2,output reg region_d2,output reg error_d2,
    output wire [7:0] font_character,output wire [3:0] font_row,
    input wire [7:0] external_font_bits
);
    reg [6:0] count_l;
    reg [5:0] index_l;
    reg [3:0] status_l;
    reg album_l,ink_enable_q,region_q,error_q;
    reg [2:0] ink_bit_q;
    reg [7:0] ch;
    wire region=de && x>=16 && x<208 && y>=688 && y<704;
    wire [4:0] char_cell=(x-16)>>3;
    function [7:0] hexchar;input [3:0] h;begin hexchar=h<10 ? "0"+h : "A"+h-10;end endfunction
    wire [7:0] font_bits;
    // The synchronous font row replaces the old ink register stage.
    assign font_character=ch;
    assign font_row=y[3:0];
    generate if(EXTERNAL_FONT) begin : external_font
        assign font_bits=external_font_bits;
    end else begin : private_font
        hud_font_sync font(.clk(clk),.character(ch),.row(y[3:0]),.bits(font_bits));
    end endgenerate
    reg [63:0] message;

    always @*begin
        case(status_l)
            0:message="NO CARD ";1:message="FORMAT  ";2:message="READY   ";
            3:message="CAPTURE ";4:message="SAVING  ";5:message="LOADING ";
            6:message="ERROR 06";7:message="FULL    ";8:message="BUSY    ";
            9:message="EMPTY   ";10:message="ARMED   ";
            11:message="ERROR 0B";12:message="ERROR 0C";
            13:message="ERROR 0D";14:message="ERROR 0E";
            15:message="ERROR 0F";default:message="ERROR 06";
        endcase
        if(char_cell<5)case(char_cell)0:ch="P";1:ch="H";2:ch="O";3:ch="T";default:ch="O";endcase
        else if(char_cell==6)ch=hexchar({2'd0,index_l[5:4]});
        else if(char_cell==7)ch=hexchar(index_l[3:0]);
        else if(char_cell==8)ch="/";
        else if(char_cell==9)ch=hexchar({1'd0,count_l[6:4]});
        else if(char_cell==10)ch=hexchar(count_l[3:0]);
        else if(char_cell>=12 && char_cell<20)ch=message >> ((19-char_cell)*8);
        else ch=" ";

    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin count_l<=0;index_l<=0;status_l<=0;album_l<=0;ink_enable_q<=0;ink_bit_q<=0;ink_d2<=0;region_q<=0;region_d2<=0;error_q<=0;error_d2<=0;end
        else begin
            if(frame_start)begin count_l<=count;index_l<=index;status_l<=status;album_l<=album;end
            // Carry the bit position and visibility with this ROM request.
            ink_enable_q<=region && (album_l || (status_l!=2 && status_l!=0));
            ink_bit_q<=3'd7-x[2:0];
            ink_d2<=ink_enable_q && font_bits[ink_bit_q];
            region_q<=de && x>=12 && x<180 && y>=684 && y<708 &&
                (album_l || (status_l!=2 && status_l!=0));
            region_d2<=region_q;
            error_q<=(status_l==6 || status_l>=11);error_d2<=error_q;
        end
    end
endmodule
