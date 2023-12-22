// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 as IStandardERC20 } from "./ERC20_IERC20.sol";
import { IERC20 as IBalancerERC20 } from "./IFlashLoanRecipient.sol";

function castTokens(IStandardERC20[] memory inputTokens) pure returns (IBalancerERC20[] memory outputTokens) {
    // solhint-disable no-inline-assembly
    assembly {
        outputTokens := inputTokens
    }
    // solhint-enable no-inline-assembly
}

