// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IMuchoToken.sol";

struct VaultInfo {
        IERC20Metadata depositToken;    //token deposited in the vault
        IMuchoToken muchoToken; //muchoToken receipt that will be returned to the investor

        uint256 totalStaked;    //Total depositToken staked, including rewards in backing
        uint256 stakedFromDeposits; //depositToken staked from deposits, excluding rewards

        uint256 lastUpdate;         //Last time the totalStaked amount was updated

        bool stakable;          //Inverstors can deposit

        uint16 depositFee;
        uint16 withdrawFee;

        uint256 maxDepositUser; //Maximum amount a user without NFT can invest
        uint256 maxCap; //Maximum total deposit (0 = no limit)
}
