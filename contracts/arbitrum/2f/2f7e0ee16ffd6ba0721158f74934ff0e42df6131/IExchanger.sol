pragma solidity 0.8.9;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SharwaFinance
 * Copyright (C) 2023 SharwaFinance
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

interface IExchanger {
    // STRUCTS //

    /**
     * @dev A struct representing data related to token swaps.
     * 
     * This struct encapsulates information necessary for token swaps, including the token path, input and output tokens,
     * input amount, minimum expected output amount, flags to indicate whether tokens are ETH and if the swap should be executed.
     * 
     * @param path The path of tokens to follow in the swap.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to swap.
     * @param amountOutMinimum The minimum amount of output tokens expected from the swap.
     * @param isETH A boolean indicating whether the input token is ETH (true if it is).
     * @param swap A boolean indicating whether the swap should be executed (true if it should).
     */
    struct ExchangeData {
        bytes path;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        bool isETH;
        bool swap;
    }
    
    // EXTERNAL FUNCTIONS //

    /**
     * @dev Allows a trader to perform a swap operation or a direct token transfer between addresses.
     * 
     * This function can be used by traders to perform token swaps through a decentralized exchange or directly transfer tokens between addresses.
     * If the 'swap' flag in the provided data is set to true, a token swap is executed with specific details such as input and output tokens,
     * minimum expected output, and other swap-related parameters. If the 'swap' flag is set to false, a direct token transfer is performed between 'from' and 'to'.
     * 
     * @param data The encoded swap or transfer data that includes information about the operation.
     * @param from The address from which tokens are transferred or swapped.
     * @param to The address that receives the tokens in the transfer or swap operation.
     * 
     * Requirements:
     * - The caller must have the 'TRADER_ROLE'.
     */
    function swap(bytes memory data, address from, address to) external payable;

    // PURE FUNCTIONS //

    /**
     * @dev Verifies if the provided `msg.value` matches the calculated value based on a series of swap operations.
     * 
     * This function checks if the provided `msg.value` matches the calculated value obtained by summing the input amounts of ETH for each swap operation.
     * It is used to ensure the correctness of `msg.value` when performing multiple swaps, preventing errors or discrepancies.
     * 
     * @param swapDataArray An array of encoded swap data, each containing information about swap or transfer operations.
     * @param msgValue The expected `msg.value` to be validated against the calculated value.
     * 
     * Requirements:
     * - The `msg.value` must match the calculated value based on the provided `swapDataArray`.
     */
    function checkMsgValue(bytes[] memory swapDataArray, uint256 msgValue) external pure;
    
    /**
     * @dev Calculates the expected `msg.value` for a given swap operation encoded in swapData.
     * 
     * This function calculates the expected `msg.value` based on the information provided in the swapData.
     * It checks if the swap operation involves ETH and is indeed a swap (not just a transfer).
     * If these conditions are met, it returns the calculated `msg.value`.
     * 
     * @param swapData The encoded swap data that describes the swap operation.
     * 
     * @return value The calculated `msg.value` for the swap operation. If it's not a swap involving ETH, the value is 0.
     */
    function calculateMsgValue(bytes memory swapData) external pure returns (uint256 value);
    
    /**
     * @dev Encodes the ExchangeData struct into a bytes array.
     * 
     * This function takes the ExchangeData struct as input and encodes it into a bytes array using ABI encoding.
     * The resulting bytes array, `paramData`, can be used to store or transmit the struct's data.
     * 
     * @param data The ExchangeData struct to be encoded.
     * 
     * @return paramData The encoded data in the form of a bytes array.
     */
    function encodeFromExchange(ExchangeData memory data) external pure returns (bytes memory paramData);
    
    /**
     * @dev Decodes the ExchangeData struct from a bytes array.
     * 
     * This function decodes the ExchangeData struct from a given bytes array (`paramData`) using ABI decoding.
     * The decoded struct, `data`, is returned for further use and processing.
     * 
     * @param paramData The bytes array containing the encoded ExchangeData struct.
     * 
     * @return data The decoded ExchangeData struct.
     */
    function decodeFromExchange(bytes memory paramData) external pure returns (ExchangeData memory data);
}
