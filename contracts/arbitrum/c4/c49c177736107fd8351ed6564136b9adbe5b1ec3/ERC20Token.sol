// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract ERC20Token is ERC20 {
    uint8 private immutable _decimals;

    constructor(
        string memory _name,
        string memory _shortName,
        uint8 _dec
    ) ERC20(_name, _shortName) {
        _decimals = _dec;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

