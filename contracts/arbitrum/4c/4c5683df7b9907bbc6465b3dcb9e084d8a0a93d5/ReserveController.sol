// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "./Owned.sol";
import {ERC20} from "./ERC20.sol";
import "./KEIManager.sol";

contract ReserveController is Owned {

    KEIManager KEIMgr;

    uint256 maxPenalty = 9000;
    uint256 a = 1500; // Coefficient for quadratic term (scaled as 0.15)
    uint256 b = 250;  // Coefficient for linear term (scaled as 0.025)

    bool public redemptionsAllowed = true;
    bool public penaltyEnabled = false;

    mapping(address => uint8) public stablecoinWeights;

    uint8 public allowedDeviation = 5;

    constructor (address _owner, address _KEIMgr) Owned(_owner) {
        KEIMgr = KEIManager(_KEIMgr);
    }

    function calculatePenalty(address _stablecoin, uint256 depositAmount) public view returns (uint256) {
        uint256 currentReserves = KEIMgr.getStablecoinReserve(_stablecoin);
        uint256 newReserves = currentReserves + depositAmount;
        uint256 totalReserves = KEIMgr.getTotalUserDeposits();

        // Calculate current and new weight percentages
        uint256 currentWeight = (currentReserves * 100) / totalReserves;
        uint256 newWeight = (newReserves * 100) / totalReserves;
        uint256 deviation;

        // Calculate deviation
        if (newWeight > currentWeight) {
            deviation = newWeight - currentWeight;
        } else {
            deviation = currentWeight - newWeight;
        }

        if (deviation <= allowedDeviation * 100) { // 5%, correctly scaled
            return 0;
        } else {
            // Polynomial fee calculation
            uint256 penalty = ((a * (deviation ** 2) + b * deviation)) / 100;

                // Maximum penalty is 90% of balance deposited.
            if (penalty > maxPenalty) {
                return maxPenalty;
            } else {
                return penalty;
            }
        }
    }

    // Function to calculate the max deposit without penalty for a stablecoin
    function maxDepositWithoutPenalty(address _stablecoin, uint256 totalReserves) public view returns (uint256) {
        uint256 reserves = KEIMgr.getStablecoinReserve(_stablecoin);
        uint256 weight = stablecoinWeights[_stablecoin];

        // If weight is zero, return zero
        if (weight == 0) {
            return 0;
        } else {
            uint256 upperLimitPercentage = weight + allowedDeviation;

            // Calculate the maximum reserves allowed for this stablecoin without penalty
            uint256 maxReservesWithoutPenalty = upperLimitPercentage * totalReserves / 100;

            // Calculate the maximum deposit allowed without penalty
            if (maxReservesWithoutPenalty > reserves) {
                return maxReservesWithoutPenalty - reserves;
            } else {
                return 0;
            }
        }
    }

    /*function calculateRedemtion(uint256 _amountRedeemed, address _stablecoin) public view returns(uint256[] memory) {
        uint256[] memory reserves = new uint256[](KEIMgr.getSupportedStablecoins().length);
        uint256 userShare = getTotalSupply(_stablecoin) / _amountRedeemed;

        for (uint256 i=0; i < KEIMgr.getSupportedStablecoins().length; i++) {
            uint256 amount = KEIMgr.getStablecoinReserve(KEIMgr.getSupportedStablecoins()[i]) / userShare;
            reserves[i] = amount;   
        }

        return reserves;
    } */

    function calculatePercentage(address _stablecoin) public view returns (uint256) {
        uint256 totalReserves = KEIMgr.getTotalUserDeposits();

        if (totalReserves == 0) {
            return 0;
        }

        return (KEIMgr.getStablecoinReserve(_stablecoin) * 100) / totalReserves;
    }

    function isPenaltyEnabled() public view returns(bool) {
        if (penaltyEnabled) {
            return true;
        }

        return false;
    }

    function setPenaltyParameters(uint256 _a, uint256 _b, uint256 _maxPenalty) public {
        a = _a;
        b = _b;
        maxPenalty = _maxPenalty;
    }

    function setWeight(address _stablecoin, uint8 _weight) public {
        stablecoinWeights[_stablecoin] = _weight;
    }

    function setMaxDeviation(uint8 _deviation) public {
        allowedDeviation = _deviation;
    }

    function enablePenalty(bool _switch) public {
        penaltyEnabled = _switch;
    }

    function allowRedemptions(bool _enabled) public onlyOwner() {
        redemptionsAllowed = _enabled;
    }

    function getTotalSupply(address _token) private view returns(uint256) {
        return ERC20(_token).totalSupply();
    }
}

