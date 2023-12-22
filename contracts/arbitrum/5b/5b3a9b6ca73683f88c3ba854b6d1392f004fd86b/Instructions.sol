// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ITokenWithMessageReceiver} from "./ITokenWithMessageReceiver.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {IDefii} from "./IDefii.sol";

contract LocalInstructions {
    using SafeERC20 for IERC20;

    error WrongInstructionType(
        IDefii.InstructionType provided,
        IDefii.InstructionType required
    );

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
        if (swapInstruction.tokenIn == swapInstruction.tokenOut) {
            return swapInstruction.amountIn;
        }
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

    function _checkInstructionType(
        IDefii.Instruction memory instruction,
        IDefii.InstructionType requiredType
    ) internal pure {
        if (instruction.type_ != requiredType) {
            revert WrongInstructionType(instruction.type_, requiredType);
        }
    }

    function _decodeSwap(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.SwapInstruction memory) {
        _checkInstructionType(instruction, IDefii.InstructionType.SWAP);
        return abi.decode(instruction.data, (IDefii.SwapInstruction));
    }

    function _decodeMinLiquidityDelta(
        IDefii.Instruction memory instruction
    ) internal pure returns (uint256) {
        _checkInstructionType(
            instruction,
            IDefii.InstructionType.MIN_LIQUIDITY_DELTA
        );
        return abi.decode(instruction.data, (uint256));
    }
}

abstract contract Instructions is LocalInstructions, ITokenWithMessageReceiver {
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
        IERC20(bridgeInstruction.token).safeTransfer(
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.amount
        );

        IBridgeAdapter(bridgeInstruction.bridgeAdapter).sendTokenWithMessage{
            value: bridgeInstruction.value
        }(
            IBridgeAdapter.Token({
                address_: bridgeInstruction.token,
                amount: bridgeInstruction.amount,
                slippage: bridgeInstruction.slippage
            }),
            IBridgeAdapter.Message({
                dstChainId: remoteChainId,
                content: abi.encode(withdrawalAddress, owner),
                bridgeParams: bridgeInstruction.bridgeParams
            })
        );

        emit Bridge(
            bridgeInstruction.token,
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.amount,
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
                slippage: swapBridgeInstruction.slippage,
                bridgeAdapter: swapBridgeInstruction.bridgeAdapter,
                value: swapBridgeInstruction.value,
                bridgeParams: swapBridgeInstruction.bridgeParams
            })
        );
    }

    function _decodeBridge(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.BridgeInstruction memory) {
        _checkInstructionType(instruction, IDefii.InstructionType.BRIDGE);
        return abi.decode(instruction.data, (IDefii.BridgeInstruction));
    }

    function _decodeSwapBridge(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.SwapBridgeInstruction memory) {
        _checkInstructionType(instruction, IDefii.InstructionType.SWAP_BRIDGE);
        return abi.decode(instruction.data, (IDefii.SwapBridgeInstruction));
    }
}

