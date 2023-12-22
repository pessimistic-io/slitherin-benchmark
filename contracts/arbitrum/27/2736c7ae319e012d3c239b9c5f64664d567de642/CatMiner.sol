//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ICatMiner.sol";
import "./TokenWithdrawable.sol";

contract CatMiner is ICatMiner, TokenWithdrawable {
    uint private constant BPS = 10000;
    uint private constant BREAK_EVEN_TIME = 3456000;
    uint public fee = 0;
    uint public refInBps = 1000;
    mapping(address => address) public refAddresses;
    mapping(address => uint) public depositedBalances;
    mapping(address => uint) public lastUpdatedTimes;
    mapping(address => uint) public totalClaimedAmounts;

    function setRefInBps(uint value) external onlyOwner {
        require(value <= 1000);
        refInBps = value;
    }

    function deposit(address refAddress) external override payable {
        require(msg.value > 0, "Miner: invalid value");

        if (refAddresses[msg.sender] == address(0)) {
            if (refAddress == address(0) || refAddress == msg.sender) {
                refAddresses[msg.sender] = owner();
            } else {
                refAddresses[msg.sender] = refAddress;
            }
        }

        uint totalAmount = calculateReward(msg.sender) + msg.value;
        _distributeRefBonus(msg.sender, totalAmount);

        emit Deposited(msg.sender, totalAmount, refAddresses[msg.sender]);
    }

    function claimReward() external override {
        uint reward = calculateReward(msg.sender);

        lastUpdatedTimes[msg.sender] = block.timestamp;
        totalClaimedAmounts[msg.sender] += reward;
        (bool isSuccess,) = msg.sender.call{value: reward}("");
        require(isSuccess);

        emit RewardClaimed(msg.sender, reward);
    }

    function compoundReward() external override {
        uint reward = calculateReward(msg.sender);
        _distributeRefBonus(msg.sender, reward);
        emit Compounded(msg.sender, reward);
    }

    function calculateReward(address account) public view returns (uint) {
        return (block.timestamp - lastUpdatedTimes[account]) * (depositedBalances[account] / BREAK_EVEN_TIME);
    }

    function collectFee(address to) external onlyOwner {
        (bool isSuccess,) = to.call{value: fee}("");
        require(isSuccess);
        fee = 0;
    }

    function _distributeRefBonus(address account, uint depositedAmount) private {
        depositedBalances[account] += depositedAmount;
        lastUpdatedTimes[account] = block.timestamp;

        uint refBonus = depositedAmount * refInBps / BPS;

        if (refAddresses[account] == owner()) {
            fee += refBonus;
        } else {
            fee += refBonus / 2;
            (bool isSuccess,) = refAddresses[account].call{value : refBonus / 2}("");
            require(isSuccess);
        }
    }
}
