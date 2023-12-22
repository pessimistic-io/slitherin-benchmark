// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

/// @title PeripheryErrors
/// @notice Library containing errors that Lighter V2 Periphery functions may revert with
library PeripheryErrors {
    /*//////////////////////////////////////////////////////////////////////////
                                      LIGHTER-V2-ROUTER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when there is not enough WETH to unwrap in the router contract
    error LighterV2Router_InsufficientWETH9();

    /// @notice Thrown when router tries to fetch an order book with invalid id
    error LighterV2Router_InvalidOrderBookId();

    /// @notice Thrown when router receives eth with no calldata provided
    error LighterV2Router_ReceiveNotSupported();

    /// @notice Thrown when input required for multi path exact output swap is too big
    error LighterV2Router_SwapExactOutputMultiTooMuchRequested();

    /// @notice Thrown when amount of native token provided is not enough to wrap and use as input for the swap
    error LighterV2Router_NotEnoughNative();

    /// @notice Thrown when router callback function is called from an address that is not a registered valid order book
    error LighterV2Router_TransferCallbackCallerIsNotOrderBook();

    /// @notice Thrown when native token refund fails
    error LighterV2Router_NativeRefundFailed();

    /*//////////////////////////////////////////////////////////////////////////
                                      LIGHTER-V2-PARSE-CALLDATA
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when function selector is not valid in fallback
    error LighterV2ParseCallData_InvalidFunctionSelector();

    /// @notice Thrown when parseLength exceeds 32-Bytes
    error LighterV2ParseCallData_ByteSizeLimit32();

    /// @notice Thrown when parse range exceeds the messageData byte length
    error LighterV2ParseCallData_CannotReadPastEndOfCallData();

    /// @notice Thrown when mantissa representation values are invalid
    error LighterV2ParseCallData_InvalidMantissa();

    /// @notice Thrown when padded number representation values are invalid
    error LighterV2ParseCallData_InvalidPaddedNumber();

    /*//////////////////////////////////////////////////////////////////////////
                                  LIGHTER-V2-QUOTER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when quoter tries to fetch an order book with invalid id
    error LighterV2Quoter_InvalidOrderBookId();

    /// @notice Thrown when there is not enough available liquidity in the order book to get quote from
    error LighterV2Quoter_NotEnoughLiquidity();

    /// @notice Thrown when path given for multi path swap is invalid
    error LighterV2Quoter_InvalidSwapExactMultiRequestCombination();
}

