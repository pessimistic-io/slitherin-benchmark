// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

interface ILpVault {
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 lastClaimTime; // keeps track of claimed time for lockup and potential penalty
        uint256 pendingGrvAmount; // pending grv amount
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amiunt);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartTimestamp(uint256 startTimestamp);
    event NewBonusEndTimestamp(uint256 bonusEndTimestamp);
    event NewRewardPerInterval(uint256 rewardPerInterval);
    event RewardsStop(uint256 blockTimestamp);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event Compound(address indexed user, uint256 amount);
    event LogSetTreasury(address indexed prevTreasury, address indexed newTreasury);
    event LogSetHarvestFee(uint256 prevHarvestFee, uint256 newHarvestFee);
    event LogSetHarvestFeePeriod(uint256 prevHarvestFeePeriod, uint256 newHarvestFeePeriod);
    event LogSetLockupPeriod(uint256 prevHarvestPeriod, uint256 newHarvestPeriod);

    function rewardPerInterval() external view returns (uint256);
    function claimableGrvAmount(address userAddress) external view returns (uint256);
    function depositLpAmount(address userAddress) external view returns (uint256);
    function userInfo(address _user) external view returns (uint256, uint256, uint256, uint256);

    function lockupPeriod() external view returns (uint256);
    function harvestFeePeriod() external view returns (uint256);

    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;

    function claim() external;
    function harvest() external;
    function compound() external;
    function emergencyWithdraw() external;
}

