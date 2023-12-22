// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./ERC20.sol";

contract ERC20MockWithDecimalsAndSymbol is ERC20 {
    uint8 immutable _decimals;

    constructor(
        uint8 decimals_,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

