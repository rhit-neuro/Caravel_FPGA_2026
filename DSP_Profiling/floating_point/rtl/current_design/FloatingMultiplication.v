`timescale 1ns / 1ps
//https://github.com/akilm/FPU-IEEE-754/blob/main/srcs/sources/FloatingCompare.v
//https://github.com/nishthaparashar/Floating-Point-ALU-in-Verilog/blob/master/Multiplication/Multiplication.v
module FloatingMultiplication #(parameter XLEN=32)
                                (input [XLEN-1:0]A,
                                 input [XLEN-1:0]B,
                                 output Exception,Overflow,Underflow,
                                 output [XLEN-1:0] result);

wire [23:0] A_Mantissa, B_Mantissa;
wire [7:0] A_Exponent = A[30:23], B_Exponent = B[30:23];

wire [22:0] Mantissa;
wire [47:0] Product, Normalized_Product;
wire [8:0] Exponent, Temp_Exponent;  // one bit bigger because of potential overflow
wire Sign, Zero;

assign Sign = A[31] ^ B[31];

//Exception flag sets 1 if either one of the exponent is 255.
assign Exception = (&A[30:23]) | (&B[30:23]);

//If exponent is equal to zero then hidden bit will be 0 for that respective significand else it will be 1
assign A_Mantissa = (|A[30:23]) ? {1'b1,A[22:0]} : {1'b0,A[22:0]};
assign B_Mantissa = (|B[30:23]) ? {1'b1,B[22:0]} : {1'b0,B[22:0]};

assign Product = A_Mantissa*B_Mantissa;

wire Norm_Flag = Product[47] ? 1'b1 : 1'b0;
assign Normalized_Product = Norm_Flag ? Product : Product << 1;

wire Round_Flag = |Normalized_Product[22:0];  //Ending 22 bits are OR'ed for rounding operation.
assign Mantissa = Normalized_Product[46:24] + (Normalized_Product[23] & Round_Flag);

// IEEE-754 zero is exp==0 AND mantissa==0 
wire A_isZero = (A[30:23] == 8'h00) && (A[22:0] == 23'd0);
wire B_isZero = (B[30:23] == 8'h00) && (B[22:0] == 23'd0);

// updated zero status flag to follow IEEE standard 
assign Zero = (!Exception) && (A_isZero || B_isZero);

//assign Zero = Exception ? 1'b0 : (Mantissa == 23'd0) ? 1'b1 : 1'b0;    //Incorrect implemetation of the Zero Status flag from last years implementation

assign Temp_Exponent = A_Exponent + B_Exponent;

assign Exponent = Temp_Exponent - 8'd127 + Norm_Flag;

assign Overflow = ((Exponent[8] & !Exponent[7]) & !Zero) ; //If overall exponent is greater than 255 then Overflow condition.
//Exception Case when exponent reaches its maximu value that is 384.

//If sum of both exponents is less than 127 then Underflow condition.
assign Underflow = ((Exponent[8] & Exponent[7]) & !Zero) ? 1'b1 : 1'b0; 

assign result = Exception ? 32'd0 : Zero ? {Sign,31'd0} : Overflow ? {Sign,8'hFF,23'd0} : Underflow ? {Sign,31'd0} : {Sign,Exponent[7:0],Mantissa};

endmodule