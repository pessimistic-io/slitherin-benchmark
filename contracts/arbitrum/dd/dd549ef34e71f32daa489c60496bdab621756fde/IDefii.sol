// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

interface IDefii is IERC20 {
    enum InstructionType {
        SWAP,
        BRIDGE,
        SWAP_BRIDGE, // SwapInstruction + BridgeInstruction
        REMOTE_CALL,
        MIN_LIQUIDITY_DELTA // Just uint256
    }

    struct Instruction {
        InstructionType type_;
        bytes data;
    }

    struct SwapInstruction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes routerCalldata;
    }
    struct BridgeInstruction {
        address token;
        uint256 amount;
        uint256 slippage;
        address bridgeAdapter;
        uint256 value;
        bytes bridgeParams;
    }
    struct SwapBridgeInstruction {
        // swap
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes routerCalldata;
        // bridge
        address bridgeAdapter;
        uint256 value;
        bytes bridgeParams;
        uint256 slippage; // bps
    }

    function enter(
        uint256 amount,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable;

    function exit(
        uint256 shares,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable;

    function withdrawLiquidity(
        address recipieint,
        uint256 shares,
        Instruction[] calldata instructions
    ) external payable;

    function notion() external view returns (address);
}

