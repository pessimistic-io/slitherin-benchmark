// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILevelDaoOmniStaking {
    function epochs(uint256 _epoch)
        external
        view
        returns (
            uint256 _startTime,
            uint256 _endTime,
            uint256 _allocationTime,
            uint256 _totalAccShare,
            uint256 _lastUpdateAccShareTime,
            uint256 _totalReward
        );
    function stakedAmounts(address _user) external view returns (uint256);

    function nextEpoch() external;
    function allocateReward(uint256 _epoch, uint256 _rewardAmount) external;
    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to) external;
}

