// SPDX-License-Identifier: None
pragma solidity 0.8.20;

import "./IERC20.sol";

contract Locker {

    address public gov;
    uint256 public countdown;

    constructor() public {
        gov = msg.sender;
        countdown = block.timestamp + 30 days;
    }

    function moreTime (uint256 _time) public {
        require(msg.sender == gov);
        countdown = countdown + _time;
    }

    function withdraw(address _assetAddress) public {
        require(msg.sender == gov);
        require(block.timestamp > countdown);

        uint256 assetBalance = IERC20(_assetAddress).balanceOf(address(this));
        IERC20(_assetAddress).transfer(msg.sender, assetBalance);
    }
}

