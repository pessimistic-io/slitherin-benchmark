// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IVester} from "./IVester.sol";
import {Util} from "./Util.sol";

contract TokenStakingDividends is Util {
    struct Reward {
        IERC20 token;
        uint256 perShare;
    }

    uint256 public total;
    uint256 public usersCount;
    mapping(address => uint256) public balances;
    mapping(address => mapping(uint256 => int256)) public debts;
    mapping(uint256 => Reward) public rewards;

    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event SetToken(uint256 indexed index, address token);
    event Donate(uint256 indexed index, uint256 amount);
    event Claim(address indexed who, uint256 index, uint256 amount);
    event Allocate(address indexed who, uint256 amount);
    event Deallocate(address indexed who, uint256 amount);

    constructor() {
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        emit File(what, data);
    }

    function setReward(uint256 index, address token) external auth {
        require(index < 10, "only 10 reward tokes supported");
        rewards[index].token = IERC20(token);
        emit SetToken(index, token);
    }

    function donate(uint256 index, uint256 amount) external auth {
        Reward storage reward = rewards[index];
        reward.token.transferFrom(msg.sender, address(this), amount);
        reward.perShare += amount * 1e12 / total;
        emit Donate(index, amount);
    }

    function claimable(address user, uint256 index) external view returns (uint256, int256) {
        uint256 earned = balances[user] * rewards[index].perShare / 1e12;
        int256 claimed = debts[user][index];
        uint256 owed = uint256(int256(earned) - claimed);
        return (owed, claimed);
    }

    function claim() external live {
        for (uint256 i = 0; i < 10; i++) {
            int256 earned = int256(balances[msg.sender] * rewards[i].perShare / 1e12);
            int256 owed = earned - debts[msg.sender][i];
            debts[msg.sender][i] = earned;
            if (owed != 0) {
                rewards[i].token.transfer(msg.sender, uint256(owed));
                emit Claim(msg.sender, i, uint256(owed));
            }
        }
    }

    function onAllocate(address who, uint256 amount) external auth live {
        total += amount;
        if (balances[who] == 0) usersCount++;
        balances[who] += amount;
        for (uint256 i = 0; i < 10; i++) {
            debts[who][i] += int256(amount * rewards[i].perShare / 1e12);
        }
        emit Allocate(who, amount);
    }

    function onDeallocate(address who, uint256 amount) external auth live {
        amount = min(balances[who], amount);
        total -= amount;
        balances[who] -= amount;
        if (balances[who] == 0) usersCount--;
        for (uint256 i = 0; i < 10; i++) {
            debts[who][i] -= int256(amount * rewards[i].perShare / 1e12);
        }
        emit Deallocate(who, amount);
    }
}

