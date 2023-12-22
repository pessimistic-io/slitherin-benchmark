// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFactorGaugeController {

    event VaultClaimReward(
        address indexed vault, 
        uint256 amount
    );

    event ReceiveVotingResults(
        uint128 indexed wTime, 
        address[] vaults, 
        uint256[] fctrAmounts
    );

    event UpdateVaultReward(
        address indexed vault,
        uint256 fctrPerSec,
        uint256 incentiveEndsAt
    );

    event AddVault(address indexed vault);

    event RemoveVault(address indexed vault);

    function fundEsFctr(uint256 amount) external;

    function withdrawEsFctr(uint256 amount) external;

    function esFctr() external returns (address);

    function redeemVaultReward() external;

    function rewardData(
        address pool
    ) external view returns (uint128 fctrPerSec, uint128, uint128, uint128);
}

