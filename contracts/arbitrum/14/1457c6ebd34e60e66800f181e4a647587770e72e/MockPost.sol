// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Capped.sol";
import "./ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./PostToken.sol";

contract MockPost is PostToken {
    constructor(address _multisigTreasury) PostToken(msg.sender) {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

