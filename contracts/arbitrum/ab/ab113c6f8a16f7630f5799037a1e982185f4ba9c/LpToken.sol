// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract LpToken is ERC20 {
    address public immutable owner;

    constructor(string memory _name, string memory _symbol, address _owner) ERC20(_name, _symbol) {
        owner = _owner;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Forbidden");
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        require(msg.sender == owner, "Forbidden");
        _burn(to, amount);
    }
}

