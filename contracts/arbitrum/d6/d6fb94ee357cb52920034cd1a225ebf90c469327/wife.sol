// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "./ERC20.sol";

contract Wife is ERC20 {
    uint256 constant initialSupply = 100000000000 * (10 ** 18);

    // Contract deployer (owner)
    address private _owner;

    // Constructor will be called on contract creation
    constructor() ERC20("Wife", "Wife") {
        _owner = msg.sender;
        _mint(_owner, initialSupply);
    }

    // Airdrop the same amount of tokens to multiple addresses
    function airdropTokens(address[] memory recipients, uint256 amount) public {
        require(
            msg.sender == _owner,
            "Only the contract owner can airdrop tokens"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(_owner, recipients[i], amount);
        }
    }
}

