// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {IDefii} from "./IDefii.sol";

contract LocalInstructions {
    using SafeERC20 for IERC20;

    event Swap(
        address tokenIn,
        address tokenOut,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut
    );

    address immutable swapRouter;

    constructor(address swapRouter_) {
        swapRouter = swapRouter_;
    }

    function _doSwap(
        IDefii.SwapInstruction memory swapInstruction
    ) internal returns (uint256 amountOut) {
        IERC20(swapInstruction.tokenIn).safeApprove(
            swapRouter,
            swapInstruction.amountIn
        );
        (bool success, ) = swapRouter.call(swapInstruction.routerCalldata);

        amountOut = IERC20(swapInstruction.tokenOut).balanceOf(address(this));
        require(success && amountOut >= swapInstruction.minAmountOut);

        emit Swap(
            swapInstruction.tokenIn,
            swapInstruction.tokenOut,
            swapRouter,
            swapInstruction.amountIn,
            amountOut
        );
    }

    function _returnFunds(
        address fundsCollector,
        address recipient,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }

        if (amount > 0) {
            IERC20(token).safeIncreaseAllowance(fundsCollector, amount);
            IFundsCollector(fundsCollector).collectFunds(
                address(this),
                recipient,
                token,
                amount
            );
        }
    }
}

abstract contract Instructions is LocalInstructions {
    using SafeERC20 for IERC20;

    event Bridge(
        address token,
        address bridgeAdapter,
        uint256 amount,
        uint256 chainId
    );

    uint256 immutable remoteChainId;

    constructor(
        address swapRouter_,
        uint256 remoteChainId_
    ) LocalInstructions(swapRouter_) {
        remoteChainId = remoteChainId_;
    }

    function _doBridge(
        address withdrawalAddress,
        address owner,
        IDefii.BridgeInstruction memory bridgeInstruction
    ) internal {
        IERC20(bridgeInstruction.sendTokenParams.token).safeTransfer(
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.sendTokenParams.amount
        );
        IBridgeAdapter(bridgeInstruction.bridgeAdapter).bridgeToken{
            value: bridgeInstruction.value
        }(
            IBridgeAdapter.GeneralParams({
                fundsCollector: address(this),
                withdrawalAddress: withdrawalAddress,
                owner: owner,
                chainId: remoteChainId,
                bridgeParams: bridgeInstruction.bridgeParams
            }),
            bridgeInstruction.sendTokenParams
        );

        emit Bridge(
            bridgeInstruction.sendTokenParams.token,
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.sendTokenParams.amount,
            remoteChainId
        );
    }

    function _doSwapBridge(
        address withdrawalAddress,
        address owner,
        IDefii.SwapBridgeInstruction memory swapBridgeInstruction
    ) internal {
        _doBridge(
            withdrawalAddress,
            owner,
            IDefii.BridgeInstruction({
                bridgeAdapter: swapBridgeInstruction.bridgeAdapter,
                value: swapBridgeInstruction.value,
                bridgeParams: swapBridgeInstruction.bridgeParams,
                sendTokenParams: IBridgeAdapter.SendTokenParams({
                    token: swapBridgeInstruction.tokenOut,
                    amount: _doSwap(
                        IDefii.SwapInstruction({
                            tokenIn: swapBridgeInstruction.tokenIn,
                            tokenOut: swapBridgeInstruction.tokenOut,
                            amountIn: swapBridgeInstruction.amountIn,
                            minAmountOut: swapBridgeInstruction.minAmountOut,
                            routerCalldata: swapBridgeInstruction.routerCalldata
                        })
                    ),
                    slippage: swapBridgeInstruction.slippage
                })
            })
        );
    }
}

