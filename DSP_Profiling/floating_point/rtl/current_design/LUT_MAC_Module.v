`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Team 8 - Neuroprocessor
// Engineer: Josh Schrock
// 
// Create Date: 11/22/2024 03:16:17 PM
// Module Name: LUT_MAC_Module
// Description: Module to perform floating point multiplication and accumulation
// 
//////////////////////////////////////////////////////////////////////////////////


module LUT_MAC_Module #(parameter DataWidth=32)( 
input wire [DataWidth-1:0] M_value, B_value, X_value,
output wire Exception, Overflow, Underflow,
output wire [DataWidth-1:0] result
);

wire [DataWidth-1:0] multResult;
wire Mult_Exception, Add_Exception;

FloatingMultiplication multiplier(X_value, M_value, Mult_Exception, Overflow, Underflow, multResult);
FloatingAddition adder(multResult, B_value, Add_Exception, result);

assign Exception = Mult_Exception | Add_Exception;

endmodule
