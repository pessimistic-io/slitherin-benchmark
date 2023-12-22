// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC721.sol";


interface INFTPool is IERC721 {
    function exists(uint256 tokenId) external view returns (bool);

    function hasDeposits() external view returns (bool);

    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address protocolToken,
            address sbtToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );

    function getStakingPosition(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );
}

