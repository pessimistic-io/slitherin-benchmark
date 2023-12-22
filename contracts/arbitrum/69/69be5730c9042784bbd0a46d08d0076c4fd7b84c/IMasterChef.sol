// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IMasterChef {
    function protocolToken() external view returns (address);

    function yieldBooster() external view returns (address);

    function emergencyUnlock() external view returns (bool);

    function getPoolInfo(
        address _poolAddress
    )
        external
        view
        returns (
            address poolAddress,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 poolEmissionRate
        );

    function claimRewards() external returns (uint256 rewardAmount);

    function isAdmin(address) external view returns (bool);

    function owner() external view returns (address);
}

