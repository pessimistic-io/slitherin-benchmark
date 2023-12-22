// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./AddressUpgradeable.sol";

contract Treasury is OwnableUpgradeable {

    function initialize() public initializer {
        __Ownable_init();
    }

    function withdraw(uint256 amount) public onlyOwner {
        AddressUpgradeable.sendValue(payable(_msgSender()), amount);
    }

    receive() external payable {}
    
}

