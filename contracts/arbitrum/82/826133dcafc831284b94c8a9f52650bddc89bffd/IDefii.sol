// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";

interface IDefii is IERC20 {
    enum InstructionType {
        SWAP,
        BRIDGE,
        SWAP_BRIDGE, // swap and bridge all tokenOut
        REMOTE_MESSAGE
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
        address bridgeAdapter;
        uint256 value;
        bytes bridgeParams;
        IBridgeAdapter.SendTokenParams sendTokenParams;
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
        address account,
        Instruction[] calldata instructions
    ) external payable;

    function exit(
        uint256 defiiLpAmount,
        address recipient,
        Instruction[] calldata instructions
    ) external payable;

    function notion() external view returns (address);
}

