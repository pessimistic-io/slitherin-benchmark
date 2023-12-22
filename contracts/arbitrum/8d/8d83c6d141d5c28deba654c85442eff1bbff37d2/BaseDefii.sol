// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ISwapHelper} from "./ISwapHelper.sol";
import {IDefii} from "./IDefii.sol";

abstract contract BaseDefii {
    using SafeERC20 for IERC20;

    address immutable swapHelper;

    constructor(address swapHelper_) {
        swapHelper = swapHelper_;
    }

    function simulateExit(
        uint256 defiiLpAmount,
        address[] calldata tokens
    ) external returns (int256[] memory balanceChanges) {
        uint256 lpAmount = defiiLpAmountToLpAmount(defiiLpAmount);

        (, bytes memory result) = address(this).call(
            abi.encodeWithSelector(
                this.simulateExitAndRevert.selector,
                lpAmount,
                tokens
            )
        );
        balanceChanges = abi.decode(result, (int256[]));
    }

    function simulateExitAndRevert(
        uint256 lpAmount,
        address[] calldata tokens
    ) external {
        int256[] memory balanceChanges = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balanceChanges[i] = int256(
                IERC20(tokens[i]).balanceOf(address(this))
            );
        }

        _exit(lpAmount);

        for (uint256 i = 0; i < tokens.length; i++) {
            balanceChanges[i] =
                int256(IERC20(tokens[i]).balanceOf(address(this))) -
                balanceChanges[i];
        }

        bytes memory returnData = abi.encode(balanceChanges);
        uint256 returnDataLength = returnData.length;
        assembly {
            revert(add(returnData, 0x20), returnDataLength)
        }
    }

    function ownedLpAmount() public view virtual returns (uint256);

    function defiiLpAmountToLpAmount(
        uint256 defiiLpAmount
    ) public virtual returns (uint256 lpAmount);

    function _doInstructions(
        IDefii.Instruction[] calldata instructions
    ) internal {
        uint256 n = instructions.length;

        IDefii.Instruction memory instruction;
        for (uint256 i = 0; i < n; i++) {
            instruction = instructions[i];

            if (instruction.type_ == IDefii.InstructionType.SWAP) {
                _doSwap(
                    abi.decode(
                        instruction.instruction,
                        (IDefii.SwapInstruction)
                    )
                );
            } else if (instruction.type_ == IDefii.InstructionType.BRIDGE) {
                _doBridge(
                    abi.decode(
                        instruction.instruction,
                        (IDefii.BridgeInstruction)
                    )
                );
            }
        }
    }

    function _doSwap(IDefii.SwapInstruction memory swapInstruction) internal {
        IERC20(swapInstruction.tokenIn).safeTransfer(
            swapHelper,
            swapInstruction.amountIn
        );
        ISwapHelper(swapHelper).swap(
            swapInstruction.tokenIn,
            swapInstruction.tokenOut,
            swapInstruction.amountIn,
            swapInstruction.minAmountOut,
            swapInstruction.router,
            swapInstruction.callData
        );
    }

    function _doBridge(
        IDefii.BridgeInstruction memory bridgeInstruction
    ) internal {
        IERC20(bridgeInstruction.sendTokenParams.token).safeTransfer(
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.sendTokenParams.amount
        );
        IBridgeAdapter(bridgeInstruction.bridgeAdapter).bridgeToken{
            value: bridgeInstruction.value
        }(bridgeInstruction.generalParams, bridgeInstruction.sendTokenParams);
    }

    function _enter() internal virtual;

    function _exit(uint256 lpAmount) internal virtual;
}

