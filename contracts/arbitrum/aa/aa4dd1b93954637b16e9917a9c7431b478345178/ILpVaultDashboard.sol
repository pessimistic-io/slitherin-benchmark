// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface ILpVaultDashboard {

    struct LpVaultData {
        uint256 totalLiquidity;
        uint256 apr;
        uint256 stakedLpAmount;
        uint256 stakedLpValueInUSD;
        uint256 claimableReward;
        uint256 pendingGrvAmount;
        uint256 penaltyDuration;
        uint256 lockDuration;
    }

    function getLpVaultInfo(address _user) external view returns (LpVaultData memory);
    function calculateLpValueInUSD(uint256 _amount) external view returns (uint256);
}

