//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
@title AttackRewardCalculator

Just a lil weighted distrubution for distributing attack rewards weighted by tier
 */

import "./Math.sol";

contract AttackRewardCalculator {
    uint256 public constant MULDIV_FACTOR = 10000;

    function calculateTotalWeight(uint256 tier1Attacks, uint256 tier2Attacks, uint256 tier3Attacks, uint256 tier1Weight, uint256 tier2Weight, uint256 tier3Weight) internal pure returns(uint256){
        return Math.mulDiv(tier1Attacks, tier1Weight, 1) +
            Math.mulDiv(tier2Attacks, tier2Weight, 1) +
            Math.mulDiv(tier3Attacks, tier3Weight, 1);
    }

    function calculateShare(uint256 totalKarrotsDepositedThisEpoch, uint256 tierAttacks, uint256 tierWeight, uint256 totalWeight) internal pure returns(uint256){
        if(tierAttacks > 0){
            return Math.mulDiv(
                totalKarrotsDepositedThisEpoch * tierAttacks,
                tierWeight * MULDIV_FACTOR,
                totalWeight * MULDIV_FACTOR
            );
        }
        return 0;
    }

    function calculateRewardPerAttack(uint256 tierShare, uint256 tierAttacks) internal pure returns(uint256){
        if(tierAttacks > 0){
            return Math.mulDiv(tierShare, 1, tierAttacks);
        }
        return 0;
    }

    function calculateRewardPerAttackByTier(
        uint256 tier1Attacks,
        uint256 tier2Attacks,
        uint256 tier3Attacks,
        uint256 tier1Weight,
        uint256 tier2Weight,
        uint256 tier3Weight,
        uint256 totalKarrotsDepositedThisEpoch
    ) external view returns (uint256[] memory) {
        
        uint256 totalWeight = calculateTotalWeight(tier1Attacks, tier2Attacks, tier3Attacks, tier1Weight, tier2Weight, tier3Weight);
        uint256 tier1Share = calculateShare(totalKarrotsDepositedThisEpoch, tier1Attacks, tier1Weight, totalWeight);
        uint256 tier2Share = calculateShare(totalKarrotsDepositedThisEpoch, tier2Attacks, tier2Weight, totalWeight);
        uint256 tier3Share = calculateShare(totalKarrotsDepositedThisEpoch, tier3Attacks, tier3Weight, totalWeight);

        uint256[] memory rewards = new uint256[](3);
        rewards[0] = calculateRewardPerAttack(tier1Share, tier1Attacks);
        rewards[1] = calculateRewardPerAttack(tier2Share, tier2Attacks);
        rewards[2] = calculateRewardPerAttack(tier3Share, tier3Attacks);

        return rewards;
    }
}

// pragma solidity ^0.8.19;

// /**
// @title AttackRewardCalculator

// Just a lil weighted distrubution for distributing attack rewards weighted by tier
//  */

// import "@openzeppelin/contracts/utils/math/Math.sol";

// contract AttackRewardCalculator {
//     uint256 public constant MULDIV_FACTOR = 10000;

//     //hook for formula to be changed later if need be
//     //this outputs reward per attack by tier based on input balance since the last epoch started
//     function calculateRewardPerAttackByTier(
//         uint256 tier1Attacks,
//         uint256 tier2Attacks,
//         uint256 tier3Attacks,
//         uint256 tier1Weight,
//         uint256 tier2Weight,
//         uint256 tier3Weight,
//         uint256 totalKarrotsDepositedThisEpoch
//     ) external view returns (uint256[] memory) {

//         uint256[] memory rewards = new uint256[](3);
        
//         uint256 tier1Share;
//         uint256 tier2Share;
//         uint256 tier3Share;
//         uint256 tier1RewardsPerAttack;
//         uint256 tier2RewardsPerAttack;
//         uint256 tier3RewardsPerAttack;
        
//         uint256 totalWeight = Math.mulDiv(tier1Attacks, tier1Weight, 1) +
//             Math.mulDiv(tier2Attacks, tier2Weight, 1) +
//             Math.mulDiv(tier3Attacks, tier3Weight, 1);

//         if (tier1Attacks > 0) {
//             tier1Share = Math.mulDiv(
//                 totalKarrotsDepositedThisEpoch * tier1Attacks,
//                 tier1Weight * MULDIV_FACTOR,
//                 totalWeight * MULDIV_FACTOR
//             );
//         } else {
//             tier1Share = 0;
//         }

//         if (tier2Attacks > 0) {
//             tier2Share = Math.mulDiv(
//                 totalKarrotsDepositedThisEpoch * tier2Attacks,
//                 tier2Weight * MULDIV_FACTOR,
//                 totalWeight * MULDIV_FACTOR
//             );
//         } else {
//             tier2Share = 0;
//         }

//         if (tier3Attacks > 0) {
//             tier3Share = Math.mulDiv(
//                 totalKarrotsDepositedThisEpoch * tier3Attacks,
//                 tier3Weight * MULDIV_FACTOR,
//                 totalWeight * MULDIV_FACTOR
//             );
//         } else {
//             tier3Share = 0;
//         }

//         if (tier1Attacks > 0) {
//             tier1RewardsPerAttack = Math.mulDiv(tier1Share, 1, tier1Attacks);
//         } else {
//             tier1RewardsPerAttack = 0;
//         }

//         if (tier2Attacks > 0) {
//             tier2RewardsPerAttack = Math.mulDiv(tier2Share, 1, tier2Attacks);
//         } else {
//             tier2RewardsPerAttack = 0;
//         }

//         if (tier3Attacks > 0) {
//             tier3RewardsPerAttack = Math.mulDiv(tier3Share, 1, tier3Attacks);
//         } else {
//             tier3RewardsPerAttack = 0;
//         }

//         rewards[0] = tier1RewardsPerAttack;
//         rewards[1] = tier2RewardsPerAttack;
//         rewards[2] = tier3RewardsPerAttack;

//         return rewards;
//     }
// }

