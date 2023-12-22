// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

enum SwapProtocol {
    None, //0
    UniswapV3, //1
    OneInch, //2
    ZeroX //3
}

enum SwapLocation {
    NONE,
    BEFORE_ACTION,
    AFTER_ACTION
}

struct SwapOperation {
    address inToken;
    uint256 maxInAmount;
    address outToken;
    uint256 minOutAmount;
    SwapProtocol protocol;
    bytes args;
}

struct InteractionOperation {
    bytes32[] callArgs;
    bytes4 methodSelector;
    address interactionAddress;
    uint8[4] amountPositions; // Maximum 32 elements to keep it in one slot please
    address[] inTokens;
}

/// @notice An operation can either be a set of swaps or a set of protocol interactions.
/// @notice Those operations will always be treated sequentially, on after the other in the order in which they were provided
/// @notive However, the tokens that come out of an operation don't necessarily have to match the input tokens of the next operation.
/// @notice We chose to provide the swap or interaction operations as arrays, to avoid sending a lot of placeholder data.
/// @notice We do that, because in EVM execution, we CAN send an empty array, but we CAN'T send empty data.
/// @dev When using those arrays, feel free to compose your swaps and interaction however you like.
/// @dev The function will revert if swap and interaction are non-empty simultaneously
struct Operation {
    SwapOperation[] swap;
    InteractionOperation[] interaction;
}

// Compressed InInformation
struct InInformation {
    InToken[] inTokens;
    uint80 fee;
    uint16 referral;
}

// Exactly 1 storage slot maximum 1e28 amount
struct InToken {
    address tokenAddress;
    uint96 amount;
}

struct OutInformation {
    address to;
    address[] tokens;
}

struct WrapperSelector {
    bytes4 methodSelector;
    uint8 amountPosition;
    address interactionAddress;
    address tokenIn;
    uint96 amount;
    address tokenOut;
    uint16 referral;
    uint80 fee;
}

struct WrapperSelectorAMM {
    bytes4 methodSelector;
    address interactionAddress;
    address poolToken;
    uint16 referral;
    uint80 fee;
    uint8[4] amountPositions;
}

struct OneTokenSwapAMM {
    address swapTokenIn;
    uint96 swapAmount;
    address swapTokenOut;
    uint96 amountMin;
}

