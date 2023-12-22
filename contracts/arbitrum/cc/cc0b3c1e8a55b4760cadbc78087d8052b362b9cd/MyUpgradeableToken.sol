// SPDX-License-Identifier: UNLICENSED

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

pragma solidity ^0.8.16;
contract MyUpgradeableToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    
    address public implementation;
    address public admin;
    uint public count;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC20_init("STEST", "STEST");
        __Ownable_init();
    }

    function increment() external {
         count += 1;
    }

}
