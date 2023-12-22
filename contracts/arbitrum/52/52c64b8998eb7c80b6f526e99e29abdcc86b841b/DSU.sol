// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable2Step.sol";

contract DSU is ERC20, Ownable2Step, ERC20Permit {
    constructor()
        ERC20("Digital Standard Unit", "DSU")
        ERC20Permit("Digital Standard Unit")
    { }

    function mint(uint256 amount) public onlyOwner {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount);
    }
}

