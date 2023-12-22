// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ApeSwapZap.sol";
import "./ICustomBill.sol";

abstract contract ApeSwapZapTBills is ApeSwapZap {
    event ZapTBill(IERC20 inputToken, uint256 inputAmount, ICustomBill bill);
    event ZapTBillNative(uint256 inputAmount, ICustomBill bill);

    /// @notice Zap single token to LP
    /// @param inputToken Input token to zap
    /// @param inputAmount Amount of input tokens to zap
    /// @param lpTokens Tokens of LP to zap to
    /// @param path0 Path from input token to LP token0
    /// @param path1 Path from input token to LP token1
    /// @param minAmountsSwap The minimum amount of output tokens that must be received for swap
    /// @param minAmountsLP AmountAMin and amountBMin for adding liquidity
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @param bill Treasury bill address
    /// @param maxPrice Max price of treasury bill
    function zapTBill(
        IERC20 inputToken,
        uint256 inputAmount,
        address[] memory lpTokens, //[tokenA, tokenB]
        address[] calldata path0,
        address[] calldata path1,
        uint256[] memory minAmountsSwap, //[A, B]
        uint256[] memory minAmountsLP, //[amountAMin, amountBMin]
        uint256 deadline,
        ICustomBill bill,
        uint256 maxPrice
    ) external nonReentrant {
        IApePair pair = IApePair(bill.principalToken());
        require(
            (lpTokens[0] == pair.token0() &&
                lpTokens[1] == pair.token1()) ||
                (lpTokens[1] == pair.token0() &&
                    lpTokens[0] == pair.token1()),
            "ApeSwapZap: Wrong LP pair for TBill"
        );

        _zapInternal(
            inputToken,
            inputAmount,
            lpTokens,
            path0,
            path1,
            minAmountsSwap,
            minAmountsLP,
            address(this),
            deadline
        );

        uint256 balance = pair.balanceOf(address(this));
        pair.approve(address(bill), balance);
        bill.deposit(balance, maxPrice, msg.sender);
        pair.approve(address(bill), 0);
        emit ZapTBill(inputToken, inputAmount, bill);
    }

    /// @notice Zap native token to Treasury Bill
    /// @param lpTokens Tokens of LP to zap to
    /// @param path0 Path from input token to LP token0
    /// @param path1 Path from input token to LP token1
    /// @param minAmountsSwap The minimum amount of output tokens that must be received for swap
    /// @param minAmountsLP AmountAMin and amountBMin for adding liquidity
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @param bill Treasury bill address
    /// @param maxPrice Max price of treasury bill
    function zapTBillNative(
        address[] memory lpTokens, //[tokenA, tokenB]
        address[] calldata path0,
        address[] calldata path1,
        uint256[] memory minAmountsSwap, //[A, B]
        uint256[] memory minAmountsLP, //[amountAMin, amountBMin]
        uint256 deadline,
        ICustomBill bill,
        uint256 maxPrice
    ) external payable nonReentrant {
        IApePair pair = IApePair(bill.principalToken());
        require(
            (lpTokens[0] == pair.token0() &&
                lpTokens[1] == pair.token1()) ||
                (lpTokens[1] == pair.token0() &&
                    lpTokens[0] == pair.token1()),
            "ApeSwapZap: Wrong LP pair for TBill"
        );

        _zapNativeInternal(
            lpTokens,
            path0,
            path1,
            minAmountsSwap,
            minAmountsLP,
            address(this),
            deadline
        );

        uint256 balance = pair.balanceOf(address(this));
        pair.approve(address(bill), balance);
        bill.deposit(balance, maxPrice, msg.sender);
        pair.approve(address(bill), 0);
        emit ZapTBillNative(msg.value, bill);
    }
}

