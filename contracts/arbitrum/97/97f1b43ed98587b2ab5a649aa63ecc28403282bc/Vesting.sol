// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";

contract Vesting {
    IERC20 public immutable token;
    uint256 public constant vestingPeriod = 180 days;
    mapping(address => uint256) public allocation;
    mapping(address => uint256) public claimed;
    uint256 public start;
    bool public started;

    constructor() {
        token = IERC20(0x3A33473d7990a605a88ac72A78aD4EFC40a54ADB);
        allocation[0x8c807CDdB6fAADF96956353f70ea60D63fAb69D5] = 72766666666666666666666;
        allocation[0xa77fEaE6752429a7ef263B40479Df84971F7d230] = 72766666666666666666666;
        allocation[0xE46DBa60D38AAEc41CdF19f2c0779E48cf51D939] = 72766666666666666666666;
    }

    function begin() external {
        require(!started, "Started");
        started = true;
        start = block.timestamp;
    }

    function claim() external {
        require(started, "!Started");
        uint256 _claimable = pending(msg.sender);
        require(_claimable > 0, "Nothing to claim");
        claimed[msg.sender] += _claimable;
        token.transfer(msg.sender, _claimable);
    }

    function pending(address _user) public view returns (uint256) {
        if (!started) return 0;
        if (block.timestamp - start > vestingPeriod)
            return allocation[_user] - claimed[_user];
        return (allocation[_user] * (block.timestamp - start)) / vestingPeriod - claimed[_user];
    }
}
