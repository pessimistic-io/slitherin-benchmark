// SPDX-License-Identifier: MIT
// Metaline Contracts (CapedERC20.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract MTTGold is 
    Context, 
    ERC20Burnable
{
    bool public _sealed;
    address public _bridgeAddr;
    address public _owner;
    
    constructor(address bridgeAddr) 
        ERC20("MetaLine Gold", "MTG") 
    {
        _bridgeAddr = bridgeAddr;
        _owner = _msgSender();
        _sealed = false;
    }

    // seal it when bridge contract is stable
    function changeBridgeAddr(address bridgeAddr, bool isSealed) external {
        require(!_sealed, "MTTGold: sealed");
        require(_msgSender() == _owner, "MTTGold: must be owner");
        _bridgeAddr = bridgeAddr;
        _sealed = isSealed;
    }

    function mint(address toAddr, uint256 value) external {
        require(_msgSender() == _bridgeAddr, "MTTGold: must have minter role");
        _mint(toAddr, value);
    }
}
