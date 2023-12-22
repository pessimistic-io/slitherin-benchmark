// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";

interface IDefii is IERC20 {
    enum InstructionType {
        SWAP,
        BRIDGE
    }

    struct Instruction {
        InstructionType type_;
        bytes instruction;
    }

    struct SwapInstruction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address router;
        bytes callData;
    }
    struct BridgeInstruction {
        address bridgeAdapter;
        uint256 value;
        IBridgeAdapter.GeneralParams generalParams;
        IBridgeAdapter.SendTokenParams sendTokenParams;
    }

    error EnterFailed();
    error ExitFailed();
    error InstructionsFailed();

    function enter(
        address token,
        uint256 amount,
        uint256 id,
        Instruction[] calldata instructions
    ) external payable;

    function exit(
        uint256 defiiLpAmount,
        address toToken,
        uint256 id,
        Instruction[] calldata instructions
    ) external payable;
}

