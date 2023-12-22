// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./ERC20.sol";

contract MockUSDC is ERC20 {
    uint8 private _decimals;

    address public owner;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _decimal
    ) ERC20(_name, _symbol) {
        require(_decimal == 6);

        owner = msg.sender;

        _decimals = uint8(_decimal);
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == owner);

        _mint(_to, _amount);
    }

    function burn(address _to, uint256 _amount) external {
        require(msg.sender == owner);

        _burn(_to, _amount);
    }
}

