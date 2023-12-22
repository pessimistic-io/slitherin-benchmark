// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./console.sol";
import "./Ownable.sol";

contract BehaviorSafetyMethods is Ownable {
    constructor() {}

    function safetyEthWithdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}

