//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeEsPegRewardPool {
    function allocatePegStaking(uint256 _amount) external;

    function allocatePegLocking(uint256 _amount) external;

    function withdrawPeg(uint256 amount) external;

    function updateStakingContract(address _staking) external;

    function updateLockUpContract(address _lockUp) external;
}

