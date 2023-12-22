//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract MyContract{
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function withdraw() public {
        require(msg.sender == owner);
        uint value = address(this).balance;
        (bool success, ) = msg.sender.call{value:value}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    function withdrawToken(address token) public {
        require(msg.sender == owner);
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender,balance);
    }
}

