`timescale 1ns / 1ps
//https://github.com/akilm/FPU-IEEE-754/blob/main/srcs/sources/FloatingCompare.v
//https://github.com/nishthaparashar/Floating-Point-ALU-in-Verilog/blob/master/ALU/Addition-Subtraction.v
module FloatingAddition #(parameter XLEN=32)
                        (input [XLEN-1:0]A,
                         input [XLEN-1:0]B,
                         output Exception,
                         output [XLEN-1:0] result);


wire operation_sub_addBar;
wire output_sign;

wire [31:0] A_swap,B_swap;
wire [7:0] A_Exponent, B_Exponent;
wire [23:0] A_Mantissa, B_Mantissa;
wire [7:0] exponent_diff;


wire [23:0] B_Mantissa_shifted;
wire [7:0] B_Exponent_shifted;

wire [24:0] Mantissa_add;
wire [30:0] add_sum;

wire [23:0] Mantissa_sub_complement;
wire [24:0] Mantissa_sub;
wire [30:0] sub_diff;
wire [24:0] subtraction_diff; 
wire [7:0] exponent_sub;

//for operations always operand_a must not be less than b_operand
assign {A_swap, B_swap} = (A[30:0] < B[30:0]) ? {B,A} : {A,B};

assign A_Exponent = A_swap[30:23];
assign B_Exponent = B_swap[30:23];

//Exception flag sets 1 if either one of the exponent is 255.
assign Exception = (&A_swap[30:23]) | (&B_swap[30:23]);

assign output_sign = A_swap[31];

assign operation_sub_addBar = ~(A_swap[31] ^ B_swap[31]);

//Assigining significand values according to Hidden Bit.
//If exponent is equal to zero then hidden bit will be 0 for that respective significand else it will be 1
assign A_Mantissa = (|A_Exponent) ? {1'b1,A_swap[22:0]} : {1'b0,A_swap[22:0]};
assign B_Mantissa = (|B_Exponent) ? {1'b1,B_swap[22:0]} : {1'b0,B_swap[22:0]};

//Evaluating Exponent Difference
assign exponent_diff = A_Exponent - B_Exponent;

//Shifting significand_b according to exponent_diff
assign B_Mantissa_shifted = B_Mantissa >> exponent_diff;

assign B_Exponent_shifted = B_Exponent + exponent_diff; 

//Checking exponents are same or not
assign perform = (A_Exponent == B_Exponent_shifted);

///////////////////////////////////////////////////////////////////////////////////////////////////////
//------------------------------------------------ADD BLOCK------------------------------------------//

assign Mantissa_add = (perform & operation_sub_addBar) ? (A_Mantissa + B_Mantissa_shifted) : 25'd0; 

//Result will be equal to Most 23 bits if carry generates else it will be Least 22 bits.
assign add_sum[22:0] = Mantissa_add[24] ? Mantissa_add[23:1] : Mantissa_add[22:0];

//If carry generates in sum value then exponent must be added with 1 else feed as it is.
assign add_sum[30:23] = Mantissa_add[24] ? (1'b1 + A_Exponent) : A_Exponent;

///////////////////////////////////////////////////////////////////////////////////////////////////////
//------------------------------------------------SUB BLOCK------------------------------------------//

assign Mantissa_sub_complement = (perform & !operation_sub_addBar) ? ~(B_Mantissa_shifted) + 24'd1 : 24'd0 ; 

assign Mantissa_sub = perform ? (A_Mantissa + Mantissa_sub_complement) : 25'd0;

Priority_Encoder pe(Mantissa_sub,A_Exponent,subtraction_diff,exponent_sub);

assign sub_diff[30:23] = exponent_sub;

assign sub_diff[22:0] = subtraction_diff[22:0];

///////////////////////////////////////////////////////////////////////////////////////////////////////
//-------------------------------------------------OUTPUT--------------------------------------------//

//If there is no exception and operation will evaluate


assign result = Exception ? 32'b0 : ((!operation_sub_addBar) ? {output_sign,sub_diff} : {output_sign,add_sum});

endmodule