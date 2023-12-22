// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {Execution} from "./Execution.sol";

abstract contract ExitSimulation is Execution {
    function simulateExit(
        uint256 shares,
        address[] calldata tokens
    ) external returns (int256[] memory balanceChanges) {
        (, bytes memory result) = address(this).call(
            abi.encodeWithSelector(
                this.simulateExitAndRevert.selector,
                shares,
                tokens
            )
        );
        balanceChanges = abi.decode(result, (int256[]));
    }

    function simulateExitAndRevert(
        uint256 shares,
        address[] calldata tokens
    ) external {
        int256[] memory balanceChanges = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balanceChanges[i] = int256(
                IERC20(tokens[i]).balanceOf(address(this))
            );
        }

        _exitLogic(_toLiquidity(shares));

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
}

