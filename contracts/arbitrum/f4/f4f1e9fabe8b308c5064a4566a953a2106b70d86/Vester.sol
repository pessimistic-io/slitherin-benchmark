// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";

contract Vester is Util {
    struct Schedule {
        address token;
        uint256 initial;
        uint256 time;
        uint256 amount;
        uint256 start;
        uint256 claimed;
    }

    mapping(address => uint256) public schedulesCount;
    mapping(address => mapping(uint256 => Schedule)) public schedules;

    event Vest(address target, uint256 index, address token, uint256 amount, uint256 initial, uint256 time);
    event Claim(address target, uint256 index, uint256 amount);

    function vest(address target, address token, uint256 amount, uint256 initial, uint256 time) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint256 index = schedulesCount[target];
        schedulesCount[target] += 1;
        Schedule storage s = schedules[target][index];
        s.token = token;
        s.initial = initial;
        s.time = time;
        s.amount = amount;
        s.start = block.timestamp;
        emit Vest(target, index, token, amount, initial, time);
    }

    function claim(uint256 index) external {
        Schedule storage s = schedules[msg.sender][index];
        uint256 available = getAvailable(msg.sender, index);
        uint256 amount = available - s.claimed;
        s.claimed += amount;
        IERC20(s.token).transfer(msg.sender, amount);
        emit Claim(msg.sender, index, amount);
    }

    // TODO exit mechanic

    function getAvailable(address target, uint256 index) public view returns (uint256) {
        Schedule memory s = schedules[target][index];
        uint256 initial = s.amount * s.initial / 1e18;
        uint256 progress = (block.timestamp - s.start) * 1e18 / s.time;
        if (progress > 1e18) progress = 1e18;
        uint256 rest = (s.amount - initial) * progress / 1e18;
        return initial + rest;
    }

    function getSchedulesInfo(address target, uint256 first, uint256 last)
        external
        view
        returns (address[] memory, uint256[] memory, uint256[] memory, uint256[] memory)
    {
        address[] memory token = new address[](last-first);
        uint256[] memory initial = new uint256[](last-first);
        uint256[] memory time = new uint256[](last-first);
        uint256[] memory start = new uint256[](last-first);
        for (uint256 i = first; i < last; i++) {
            Schedule memory s = schedules[target][i];
            token[i] = s.token;
            initial[i] = s.initial;
            time[i] = s.time;
            start[i] = s.start;
        }
        return (token, initial, time, start);
    }

    function getSchedules(address target, uint256 first, uint256 last)
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory)
    {
        uint256[] memory amount = new uint256[](last-first);
        uint256[] memory claimed = new uint256[](last-first);
        uint256[] memory available = new uint256[](last-first);
        for (uint256 i = first; i < last; i++) {
            Schedule memory s = schedules[target][i];
            amount[i] = s.amount;
            claimed[i] = s.claimed;
            available[i] = getAvailable(target, i);
        }
        return (amount, claimed, available);
    }
}

