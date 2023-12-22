// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./tokens_ERC20.sol";

contract SoulBound is ERC20 {
    mapping(address => bool) whitelistedMinters;
    address owner;

    constructor() ERC20("SBT", "SBT") {
        whitelistedMinters[msg.sender] = true;
        owner = msg.sender;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(false, "Transfer not allowed");
    }

    function mintArbitrary(address _to, uint256 _amount) public {
        require(
            whitelistedMinters[msg.sender],
            "You don't have access to mint!"
        );
        _mint(_to, _amount);
    }

    function transferOwner(address _newOwner) external {
        require(
            msg.sender == owner,
            "You don't have right to call this function"
        );
        owner = _newOwner;
    }

    function addWhitelistMinter(address _newMinter) external {
        require(
            msg.sender == owner,
            "You don't have right to call this function"
        );
        whitelistedMinters[_newMinter] = true;
    }
}

