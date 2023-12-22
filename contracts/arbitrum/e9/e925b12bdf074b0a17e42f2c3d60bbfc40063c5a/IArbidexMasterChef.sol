// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

struct ArbidexPoolUserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 arxRewardDebt;
    uint256 WETHRewardDebt;
}

struct ArbidexPoolInfo {
    address lpToken; // Address of LP token contract.
    uint256 arxAllocPoint; // How many allocation points assigned to this pool. ARXs to distribute per block.
    uint256 WETHAllocPoint;
    uint256 lastRewardTime; // Last block number that ARXs distribution occurs.
    uint256 accArxPerShare; // Accumulated ARXs per share, times 1e12.
    uint256 accWETHPerShare;
    uint256 totalDeposit;
}

interface IArbidexMasterChef {
    function arx() external view returns (address);

    function WETH() external view returns (address);

    function pendingArx(uint256 poolId, address user) external view returns (uint256);

    function pendingWETH(uint256 poolId, address user) external view returns (uint256);

    function deposit(uint256 poolId, uint256 amount) external;

    function withdraw(uint256 poolId, uint256 amount) external;

    function emergencyWithdraw(uint256 poolId) external;

    function arxPerSec() external view returns (uint256);

    function WETHPerSec() external view returns (uint256);

    function poolInfo(uint256) external view returns (ArbidexPoolInfo memory);

    function arxTotalAllocPoint() external view returns (uint256);

    function WETHTotalAllocPoint() external view returns (uint256);

    function userInfo(uint256 poolId, address user) external view returns (ArbidexPoolUserInfo memory);
}

