// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract testUSDC is ERC20Upgradeable, OwnableUpgradeable{

    function initialize() external initializer{
        __Ownable_init();
        __ERC20_init('tUSDC', 'tUSDC');
    }
    
    /**
        * @notice This function mint 1000 tUSDC to the caller's accounts
        * @dev Mint 1000 tUSDC tokens to the caller
    */
    function mintTestUSDC() external {
        _mint(msg.sender, 1000 ether);
    }
    
    
}

