//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOdosRouter {
    /// @dev Contains all information needed to describe the input and output for a swap
    //solhint-disable-next-line contract-name-camelcase
    struct swapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address inputReceiver;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }
    /// @dev Contains all information needed to describe an intput token for swapMulti
    //solhint-disable-next-line contract-name-camelcase
    struct inputTokenInfo {
        address tokenAddress;
        uint256 amountIn;
        address receiver;
    }
    /// @dev Contains all information needed to describe an output token for swapMulti
    //solhint-disable-next-line contract-name-camelcase
    struct outputTokenInfo {
        address tokenAddress;
        uint256 relativeValue;
        address receiver;
    }

    /// @notice Custom decoder to swap with compact calldata for efficient execution on L2s
    function swapCompact() external payable returns (uint256);

    /// @notice Externally facing interface for swapping two tokens
    /// @param tokenInfo All information about the tokens being swapped
    /// @param pathDefinition Encoded path definition for executor
    /// @param executor Address of contract that will execute the path
    /// @param referralCode referral code to specify the source of the swap
    function swap(
        swapTokenInfo memory tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256 amountOut);

    /// @notice Externally facing interface for swapping between two sets of tokens
    /// @param inputs list of input token structs for the path being executed
    /// @param outputs list of output token structs for the path being executed
    /// @param valueOutMin minimum amount of value out the user will accept
    /// @param pathDefinition Encoded path definition for executor
    /// @param executor Address of contract that will execute the path
    /// @param referralCode referral code to specify the source of the swap
    function swapMulti(
        inputTokenInfo[] memory inputs,
        outputTokenInfo[] memory outputs,
        uint256 valueOutMin,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256[] memory amountsOut);
}

