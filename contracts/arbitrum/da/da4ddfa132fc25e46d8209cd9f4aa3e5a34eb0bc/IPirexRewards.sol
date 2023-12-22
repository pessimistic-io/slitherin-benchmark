// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";

interface IPirexRewards {
    function accrueStrategy()
        external
        returns (
            ERC20[] memory _producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        );
}

