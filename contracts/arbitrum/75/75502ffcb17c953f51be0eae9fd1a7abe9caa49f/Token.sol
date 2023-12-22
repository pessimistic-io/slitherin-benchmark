pragma solidity ^0.8.21;

import "./ERC20.sol";


contract MintableERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address recipient, uint256 amount) public {
        _mint(recipient, amount);
    }
}

contract MintableNonStandardDecimalERC20 is MintableERC20 {
    uint8 internal _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 __decimals
    ) MintableERC20(name, symbol) {
        _decimals = __decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

