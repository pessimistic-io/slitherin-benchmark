//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { EsPegLock } from "./Structs.sol";

interface IPepeEsPegLockUp {
    function lock(uint256 wethAmount, uint256 esPegAmount, uint256 minBlpOut) external;

    function unlock(uint256 lockId) external;

    ///@notice update rewards accumulated to this contract.
    function updateRewards() external;

    function claimUsdcRewards(uint256 lockId) external;

    function claimAllUsdcRewards() external;

    function getTotalPendingUsdcRewards(address user) external view returns (uint256);

    function pendingUsdcRewards(address user, uint256 lockId) external view returns (uint256);

    function setRewardPool(address _rewardPool) external;

    function updateLockGroupId(uint8 _lockGroupId) external;

    function setLockDuration(uint48 _lockDuration) external;

    function getLockDetails(address _user, uint256 lockId) external view returns (EsPegLock memory);

    function getAllUsers() external view returns (address[] memory);

    function setFeeDistributor(address _feeDistributor) external;
}

