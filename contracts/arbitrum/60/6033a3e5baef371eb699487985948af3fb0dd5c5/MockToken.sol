// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {}

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }
}
