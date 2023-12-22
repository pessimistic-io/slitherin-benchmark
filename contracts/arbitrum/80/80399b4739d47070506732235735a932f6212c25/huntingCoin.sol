// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./AccessControl.sol";

contract HuntingCoin is ERC20, Ownable, AccessControl  {
     bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20(unicode"₿itcoach Hanster DAO",unicode"ŠKRČK") {
        _mint(msg.sender, 1_000_000 * 10**18);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address acc, uint256 amount) public {
        
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(acc, amount);
    }

    function addMinter(address minter) public onlyOwner {
       _grantRole(MINTER_ROLE, minter);
    }
}

