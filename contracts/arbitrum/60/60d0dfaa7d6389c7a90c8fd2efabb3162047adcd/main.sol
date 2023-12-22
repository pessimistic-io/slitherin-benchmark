// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";

contract InstaFlashPayback {
    using SafeERC20 for IERC20;

    // The address of the flashloan aggregator V2
    address public constant FLASHLOAN_AGGREGATOR_V2 = 0x8d8B52e9354E2595425D00644178E2bA2257f42a;

    // Transfers tokens to flashloan aggregator V2
    function payback(address[] calldata tokens, uint256[] calldata amounts) external {
        require(tokens.length == amounts.length, "Tokens and amounts arrays must have the same length");

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 amount = amounts[i];

            // Transfer the specified amount of each token from the contract to the flash loan aggregator
            token.safeTransfer(FLASHLOAN_AGGREGATOR_V2, amount);
        }
    }
}

