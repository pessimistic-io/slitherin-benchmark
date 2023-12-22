// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IVault} from "./IVault.sol";
import {IDefii} from "./IDefii.sol";

contract LocalInstructions {
    using SafeERC20 for IERC20;

    address immutable SWAP_ROUTER;

    event Swap(
        address tokenIn,
        address tokenOut,
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut
    );

    error WrongInstructionType(
        IDefii.InstructionType provided,
        IDefii.InstructionType required
    );
    error InstructionFailed();

    constructor(address swapRouter) {
        SWAP_ROUTER = swapRouter;
    }

    function _doSwap(
        IDefii.SwapInstruction memory swapInstruction
    ) internal returns (uint256 amountOut) {
        if (swapInstruction.tokenIn == swapInstruction.tokenOut) {
            return swapInstruction.amountIn;
        }
        amountOut = IERC20(swapInstruction.tokenOut).balanceOf(address(this));
        IERC20(swapInstruction.tokenIn).safeIncreaseAllowance(
            SWAP_ROUTER,
            swapInstruction.amountIn
        );
        (bool success, ) = SWAP_ROUTER.call(swapInstruction.routerCalldata);

        amountOut =
            IERC20(swapInstruction.tokenOut).balanceOf(address(this)) -
            amountOut;

        if (!success || amountOut < swapInstruction.minAmountOut)
            revert InstructionFailed();

        emit Swap(
            swapInstruction.tokenIn,
            swapInstruction.tokenOut,
            SWAP_ROUTER,
            swapInstruction.amountIn,
            amountOut
        );
    }

    function _returnAllFunds(
        address vault,
        uint256 positionId,
        address token
    ) internal {
        _returnFunds(
            vault,
            positionId,
            token,
            IERC20(token).balanceOf(address(this))
        );
    }

    function _returnFunds(
        address vault,
        uint256 positionId,
        address token,
        uint256 amount
    ) internal {
        if (amount > 0) {
            IERC20(token).safeIncreaseAllowance(vault, amount);
            IVault(vault).depositToPosition(positionId, token, amount, 0);
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

    /* solhint-disable named-return-values */
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

    function _decodeMinTokensDelta(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.MinTokensDeltaInstruction memory) {
        _checkInstructionType(
            instruction,
            IDefii.InstructionType.MIN_TOKENS_DELTA
        );
        return abi.decode(instruction.data, (IDefii.MinTokensDeltaInstruction));
    }
}

