// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ApeSwapZap.sol";
import "./ICustomBill.sol";

abstract contract ApeSwapZapTBills is ApeSwapZap {
    using SafeERC20 for IERC20;

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
            (lpTokens[0] == pair.token0() && lpTokens[1] == pair.token1()) ||
                (lpTokens[1] == pair.token0() && lpTokens[0] == pair.token1()),
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

        _depositTBill(bill, IERC20(address(pair)), maxPrice, msg.sender);
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
            (lpTokens[0] == pair.token0() && lpTokens[1] == pair.token1()) ||
                (lpTokens[1] == pair.token0() && lpTokens[0] == pair.token1()),
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

        _depositTBill(bill, IERC20(address(pair)), maxPrice, msg.sender);
        emit ZapTBillNative(msg.value, bill);
    }

    /// @notice Zap token to single asset Treasury Bill
    /// @param inputToken Input token to zap
    /// @param inputAmount Amount of input tokens to zap
    /// @param path Path from input token to stake token
    /// @param minAmountsSwap The minimum amount of output tokens that must be received for swap
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @param bill Pool address
    /// @param maxPrice MaxPrice for purchasing a bill
    function zapSingleAssetTBill(
        IERC20 inputToken,
        uint256 inputAmount,
        address[] calldata path,
        uint256 minAmountsSwap,
        uint256 deadline,
        ICustomBill bill,
        uint256 maxPrice
    ) external nonReentrant {
        IERC20 principalToken = IERC20(bill.principalToken());
        require(
            (address(inputToken) == path[0] &&
                address(principalToken) == path[path.length - 1]),
            "ApeSwapZapTBills: Wrong path for inputToken or principalToken"
        );

        uint256 balanceBefore = _getBalance(inputToken);
        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);
        inputAmount = _getBalance(inputToken) - balanceBefore;

        inputToken.approve(address(router), inputAmount);
        _routerSwap(inputAmount, minAmountsSwap, path, deadline);
        _depositTBill(bill, principalToken, maxPrice, msg.sender);

        emit ZapTBill(inputToken, inputAmount, bill);
    }

    /// @notice Zap native token to single asset Treasury Bill
    /// @param path Path from input token to stake token
    /// @param minAmountsSwap The minimum amount of output tokens that must be received for swap
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @param bill Pool address
    /// @param maxPrice MaxPrice for purchasing a bill
    function zapSingleAssetTBillNative(
        address[] calldata path,
        uint256 minAmountsSwap,
        uint256 deadline,
        ICustomBill bill,
        uint256 maxPrice
    ) external payable nonReentrant {
        (uint256 inputAmount, IERC20 inputToken) = _wrapNative();
        IERC20 principalToken = IERC20(bill.principalToken());
        require(
            (address(inputToken) == path[0] &&
                address(principalToken) == path[path.length - 1]),
            "ApeSwapZapTBills: Wrong path for inputToken or principalToken"
        );

        inputToken.approve(address(router), inputAmount);
        _routerSwap(inputAmount, minAmountsSwap, path, deadline);
        _depositTBill(bill, principalToken, maxPrice, msg.sender);

        emit ZapTBillNative(inputAmount, bill);
    }

    function _depositTBill(
        ICustomBill bill,
        IERC20 principalToken,
        uint256 maxPrice,
        address depositor
    ) private returns (uint256 depositAmount) {
        depositAmount = principalToken.balanceOf(address(this));
        require(depositAmount > 0, "ApeSwapZapTBills: Nothing to deposit");
        principalToken.approve(address(bill), depositAmount);
        bill.deposit(depositAmount, maxPrice, depositor);
        principalToken.approve(address(bill), 0);
    }
}

