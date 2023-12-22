// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20.sol";
import "./IMasterOfCoin.sol";
import "./ITestERC20.sol";

contract MasterOfCoinMock is IMasterOfCoin {
    ITestERC20 public immutable magic;
    uint256 public previousWithdrawStamp;
    bool public staticAmount;

    constructor(address magic_) {
        magic = ITestERC20(magic_);
        previousWithdrawStamp = block.timestamp;
        staticAmount = true;
    }

    function requestRewards() external override returns (uint256 rewardsPaid) {
        if (staticAmount) {
            magic.mint(500 ether, msg.sender);
            return 500 ether;
        }
        uint256 secondsPassed = block.timestamp - previousWithdrawStamp;
        uint256 rewards = secondsPassed * 11574074e8;
        previousWithdrawStamp = block.timestamp;
        magic.mint(rewards, msg.sender);
        return rewards;
    }

    function getPendingRewards(address) external view override returns (uint256 pendingRewards) {
        if (staticAmount) {
            return 500 ether;
        }
        uint256 secondsPassed = block.timestamp - previousWithdrawStamp;
        uint256 rewards = secondsPassed * 11574074e8;
        return rewards;
    }

    function setWithdrawStamp() external override {
        previousWithdrawStamp = block.timestamp;
    }

    function setStaticAmount(bool set) external override {
        staticAmount = set;
    }
}

