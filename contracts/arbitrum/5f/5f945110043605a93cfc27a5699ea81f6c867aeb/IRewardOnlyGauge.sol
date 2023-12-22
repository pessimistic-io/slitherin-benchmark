// SPDX-License-Identifier: UNLICENSED

interface IRewardOnlyGauge {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function claim_rewards() external;
}

