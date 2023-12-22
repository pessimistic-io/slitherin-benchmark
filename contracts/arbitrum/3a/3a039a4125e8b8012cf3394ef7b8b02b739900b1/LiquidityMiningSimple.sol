// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IPool} from "./IPool.sol";
import {IERC20} from "./IERC20.sol";

// Incentivize liquidity with token rewards, based on SushiSwap's MiniChef, really simplified, single pool
contract LiquidityMiningSimple is Util {
    struct User {
        uint256 deposit;
        int256 claimed;
    }

    IERC20 public tokenFarmed;
    IERC20 public tokenReward;
    uint256 public rate; // tokens distributed per day
    uint256 public time; // last time earnedPerShare updated
    int256 public earnedPerShare;
    mapping(address => User) public users;

    event FileInt(bytes32 what, uint256 data);
    event FileAddress(bytes32 what, address data);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 amount);

    constructor(address _tokenFarmed) {
        time = block.timestamp;
        exec[msg.sender] = true;
        tokenFarmed = IERC20(_tokenFarmed);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        if (what == "rate") rate = data;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "tokenReward") tokenReward = IERC20(data);
        emit FileAddress(what, data);
    }

    function getPending(address target) external view returns (uint256) {
        User memory user = users[target];
        int256 earnedPerShareLatest = earnedPerShare;
        uint256 deposits = tokenFarmed.balanceOf(address(this));
        if (deposits > 0) {
            earnedPerShareLatest += int256(((block.timestamp - time) * rate / 1 days) * 1e12 / deposits);
        }
        return uint256((int256(user.deposit) * earnedPerShareLatest / 1e12) - user.claimed);
    }

    function deposit(uint256 amount, address to) public loop live {
        update();
        tokenFarmed.transferFrom(msg.sender, address(this), amount);
        User storage user = users[to];
        user.deposit += amount;
        user.claimed += (int256(amount) * earnedPerShare) / 1e12;
        emit Deposit(to, amount);
    }

    function withdraw(uint256 amount, address to) public loop live {
        update();
        User storage user = users[to];
        user.deposit -= amount;
        user.claimed -= int256((int256(amount) * earnedPerShare) / 1e12);
        tokenFarmed.transfer(to, amount);
        emit Withdraw(msg.sender, amount);
    }

    function harvest(address target) public loop live {
        update();
        User storage user = users[target];
        int256 updated = (int256(user.deposit) * earnedPerShare) / 1e12;
        uint256 amount = uint256(updated - user.claimed);
        user.claimed = updated;
        if (amount != 0) tokenReward.transfer(target, amount);
        emit Harvest(target, amount);
    }

    function update() internal {
        uint256 deposits = tokenFarmed.balanceOf(address(this));
        if (deposits > 0 && block.timestamp > time) {
            earnedPerShare += int256((block.timestamp - time) * rate / 1 days) * 1e12 / int256(deposits);
            time = block.timestamp;
        }
    }
}

