// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IVotesUpgradeable } from "./IVotesUpgradeable.sol";

interface IVoteLockArchi is IVotesUpgradeable {
    function wrappedToken() external view returns (address);

    function stake(uint256 amountIn, address _delegatee) external;

    function totalRewardTokens() external view returns (uint256);

    function claim() external returns (uint256[] memory);

    function pendingRewards(address recipient) external view returns (uint256[] memory);

    function getRewardToken(uint256 index) external view returns (address);

    struct RewardToken {
        address token;
        uint256 accRewardPerShare;
        uint256 queuedRewards;
    }
}

