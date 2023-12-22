pragma solidity ^0.5.16;

interface ITierLocker {
    function getAvailableUnlock(address _account)
        external
        view
        returns (uint256);

    function getUserTier(address account) external view returns (uint256);

    function getUserTierInfos(address account)
        external
        view
        returns (
            uint256 _tier,
            uint256 _lockedTimestamp,
            uint256 _amount
        );

    function getTierLockedAmount() external view returns (uint256[5] memory);

    function getTierCounts() external view returns (uint256[5] memory);

    function getTierBP(uint256 _userTier) external view returns (uint256);

    function calculateUserTierReward(address account, uint256 rewardToken)
        external
        view
        returns (uint256);

    function requestPool(string calldata _poolLink) external payable;

    function getRequestPools() external view returns (address[] memory);
}

