// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAtlasMineStaker {
    // ============= Events ==============

    event UserDeposit(address indexed user, uint256 amount);
    event UserWithdraw(address indexed user, uint256 amount, uint256 reward);
    event UserClaim(address indexed user, uint256 reward);
    event MineStake(uint256 currentDepositId, uint256 unlockTime);
    event MineHarvest(uint256 earned, uint256 feeEarned);
    event StakeNFT(address nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event UnstakeNFT(address nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event SetFee(uint256 fee);
    event StakingPauseToggle(bool paused);

    // =============== View Functions ================

    function userStake(address user) external returns (uint256);

    function totalMagic() external returns (uint256);

    function totalPendingStake() external returns (uint256);

    function totalWithdrawableMagic() external returns (uint256);

    function totalRewardsEarned() external returns (uint256);

    // ============= Staking Operations ==============

    function deposit(uint256 _amount) external;

    function withdraw() external;

    function claim() external;

    function withdrawEmergency() external;

    function stakeScheduled() external;

    // ============= Hoard Operations ==============

    function stakeTreasure(uint256 _tokenId, uint256 _amount) external;

    function unstakeTreasure(uint256 _tokenId, uint256 _amount) external;

    function stakeLegion(uint256 _tokenId) external;

    function unstakeLegion(uint256 _tokenId) external;

    // ============= Owner Operations ==============

    function unstakeAllFromMine() external;

    function unstakeToTarget(uint256 target) external;

    function emergencyUnstakeAllFromMine() external;

    function setFee(uint256 _fee) external;

    function setHoard(address _hoard) external;

    function approveNFTs() external;

    function revokeNFTApprovals() external;

    function toggleSchedulePause(bool paused) external;

    function withdrawFees() external;
}

