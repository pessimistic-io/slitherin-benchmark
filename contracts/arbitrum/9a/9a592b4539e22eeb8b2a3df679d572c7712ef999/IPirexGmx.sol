// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";

interface IPirexGmx {
    function depositFsGlp(uint256 amount, address receiver)
        external
        returns (uint256, uint256);

    function claimRewards()
        external
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        );

    function claimUserReward(
        address rewardTokenAddress,
        uint256 rewardAmount,
        address recipient
    ) external returns (uint256 postFeeAmount, uint256 feeAmount);
}

