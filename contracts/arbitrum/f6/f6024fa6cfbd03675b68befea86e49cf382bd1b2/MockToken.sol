// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MOCK Token B", "B") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

