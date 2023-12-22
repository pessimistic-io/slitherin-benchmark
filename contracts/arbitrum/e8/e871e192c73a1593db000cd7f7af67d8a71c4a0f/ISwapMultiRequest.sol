// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @title SwapMultiRequest Interface
/// @notice Interface for multi path swap requests
interface ISwapMultiRequest {
    /// @notice Structure to represent a swap request.
    struct SwapRequest {
        bool isAsk; // Whether the order is an ask order
        uint8 orderBookId; // The unique identifier of the order book associated with the swap request
    }

    /// @notice Structure to represent a multi-path swapExactInput request.
    struct MultiPathExactInputRequest {
        SwapRequest[] swapRequests; // Array of swap requests defining the sequence of swaps to be executed
        uint256 exactInput; // exactInput to pay for the first swap in the sequence
        uint256 minOutput; // Minimum output amount expected to recieve from last swap in the sequence
        address recipient; // The address of the recipient of the output
        bool unwrap; // Boolean indicator wheter to unwrap the wrapped native token output or not
    }

    /// @notice Structure to represent a multi-path swapExactOutput request.
    struct MultiPathExactOutputRequest {
        SwapRequest[] swapRequests; // Array of swap requests defining the multi-path swap sequence
        uint256 exactOutput; // exactOutput to receive from the last swap in the sequence
        uint256 maxInput; // Maximum input that the taker is willing to pay for the first swap in the sequence
        address recipient; // The address of the recipient of the output
        bool unwrap; // Boolean indicator wheter to unwrap the wrapped native token output or not
    }
}

