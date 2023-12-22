// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";
import "./KEIManager.sol";
import "./KEI.sol";

contract Staking {
    KEI KEIToken = KEI(0xf43e6f98C9f89b032f369742A331911B4d2C4E65);
    KEIManager KEIMgr = KEIManager(0xd26800A483A3A7181464023Ea19882d5e1c962f4);

    uint256 public stakingStart;
    uint256 public currentEpoch = 0;
    uint256 public epochDuration = 5 minutes;
    uint256 currentYieldCheckpoint;

    bool public stakingPaused;

    mapping(uint256 => uint256) public totalYieldPerEpoch;
    mapping(uint256 => uint256) public totalPoolSizePerEpoch;
    mapping(address => Staker) public stakers;

    struct Staker {
        uint256 stakeAmount;
        uint256 depositEpoch;
    }

    function stakeKEI(uint256 _amount) public {
        require(_amount >= 100, "Minimum deposit is 300 KEI");

        Staker storage staker = stakers[msg.sender];
        updateEpochState(); // Ensure we're working with the correct epoch

        if (staker.stakeAmount == 0) {
            staker.depositEpoch = currentEpoch;
        }

        staker.stakeAmount += _amount;

        // Update the pool size for the next epoch, as staking mid-epoch shouldn't affect the current epoch's rewards
        totalPoolSizePerEpoch[currentEpoch + 1] += _amount;
        ERC20(KEIToken).transferFrom(msg.sender, address(this), _amount);
    }

    function unstakeKEI(uint256 _amount, bool _forfeit) public {
        Staker storage staker = stakers[msg.sender];

        require(_amount > 0, "Amount must be greater than 0");
        require(staker.stakeAmount >= _amount, "Insufficient stake amount");

        updateEpochState();
        uint256 reward = calculateReward(msg.sender);

        if (_forfeit || totalSupplyInvariant(reward) == false) {
            staker.stakeAmount -= _amount;
            totalPoolSizePerEpoch[currentEpoch] -= _amount;

            KEIToken.transfer(msg.sender, _amount);

        } else {
            staker.stakeAmount -= _amount;
            totalPoolSizePerEpoch[currentEpoch] -= _amount;

            KEIToken.mint(address(this), reward);
            KEIToken.transfer(msg.sender, _amount + reward);
        }
    }

    function calculateReward(address stakerAddress) internal view returns (uint256) {
        Staker memory staker = stakers[stakerAddress];
        uint256 reward = 0;

        for (uint256 i = staker.depositEpoch; i < currentEpoch; i++) {
            uint256 yield = totalYieldPerEpoch[i];
            uint256 poolSize = totalPoolSizePerEpoch[i];
            if (poolSize > 0) {
                uint256 stakerShare = staker.stakeAmount * 1e18 / poolSize; // multiplied by 1e18 for precision
                reward += yield * stakerShare / 1e18; // divide by 1e18 to correct units
            }
        }

        return reward;
    }

    function updateEpochState() internal {
        uint256 elapsedTime = block.timestamp - stakingStart;
        uint256 newEpoch = elapsedTime / epochDuration + 1;

        if (newEpoch > currentEpoch) {
            uint256 yield = calculateEpochYield(); // Implement this based on your yield-generating strategy
            totalYieldPerEpoch[currentEpoch] = yield;
            currentEpoch = newEpoch;
        }
    }

    function calculateEpochYield() internal returns (uint256) {
        uint256 newCheckpoint = KEIMgr.calculateAccruedYield();
        uint256 epochYield = newCheckpoint - currentYieldCheckpoint;

        currentYieldCheckpoint = newCheckpoint;
        return epochYield;
        
    }

    function totalSupplyInvariant(uint256 _reward) internal returns (bool) {
        uint256 totalSupplyAfterMint = KEIToken.totalSupply() + _reward;
        uint256 totalReserves = KEIMgr.getTotalReserves(); // Implement this function to return the total reserves

        return totalSupplyAfterMint <= totalReserves;
    }

    function startStaking() public {
        currentYieldCheckpoint = KEIMgr.calculateAccruedYield();
        stakingStart = block.timestamp;
        currentEpoch += 1; 
    }

    function pauseStaking() public {
        if (stakingPaused) {
            stakingPaused = false;
        }

        stakingPaused = true;
    }
}
