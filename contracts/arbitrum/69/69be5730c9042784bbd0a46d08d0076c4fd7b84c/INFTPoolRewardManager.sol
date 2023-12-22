// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface INFTPoolRewardManager {
    function pendingAdditionalRewards(
        uint256 tokenId,
        uint256 positionAmountMultiplied,
        uint256 lpSupplyWithMultiplier,
        uint256 lastRewardTime
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts);

    function updateRewardsPerShare(uint256 lpSupplyMultiplied, uint256 lastRewardTime) external;

    function updatePositionRewardDebts(uint256 positionAmountMultiplied, uint256 tokenId) external;

    function harvestAdditionalRewards(uint256 positionAmountMultiplied, address to, uint256 tokenId) external;

    function addRewardToken(address token, uint256 sharesPerSecond) external;
}

