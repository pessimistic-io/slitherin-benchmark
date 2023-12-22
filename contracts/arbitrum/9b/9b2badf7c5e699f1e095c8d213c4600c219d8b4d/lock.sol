// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract lock {
    IERC20 public token;

    struct UserInfo {
        uint startTime;
        uint endTime;
        uint amount;
        uint claimed;
        uint lastTime;
        uint rate;
    }

    mapping(address => UserInfo) public userInfo;
    constructor(address token_){
        token = IERC20(token_);
    }
    uint256 constant times = 2 * 365 days;
    //    uint times = 120;
    event Stake(address indexed player, uint indexed amount);
    event Claim(address indexed player, uint indexed amount);

    function stake(uint amount) external {
        UserInfo storage info = userInfo[msg.sender];
        require(info.amount == 0, 'staked');
        token.transferFrom(msg.sender, address(this), amount);
        info.startTime = block.timestamp;

        info.endTime = block.timestamp + times;
        info.lastTime = block.timestamp;
        info.amount = amount;
        info.rate = amount / times;
        emit Stake(msg.sender, amount);
    }

    function calculateReward(address addr) public view returns (uint){
        UserInfo storage info = userInfo[addr];
        if (info.amount == 0) return 0;
        uint out = (block.timestamp - info.lastTime) * info.rate;
        if (out + info.claimed >= info.amount || block.timestamp >= info.endTime) {
            out = info.amount - info.claimed;
        }
        return out;
    }

    function claim() external {
        UserInfo storage info = userInfo[msg.sender];
        require(info.amount != 0, 'NOT STAKE');
        uint rew = calculateReward(msg.sender);
        require(rew > 0, 'no reward');
        token.transfer(msg.sender, rew);
        info.claimed += rew;
        info.lastTime = block.timestamp;
        if (info.claimed >= info.amount || block.timestamp >= info.endTime) {
            delete userInfo[msg.sender];
        }
        emit Claim(msg.sender, rew);
    }
}

