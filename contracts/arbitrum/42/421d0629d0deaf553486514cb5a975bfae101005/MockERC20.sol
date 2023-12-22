// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./ERC20.sol";

contract MockERC20 is ERC20 {
    uint256 public constant MAX_HOLD = 10000 ether;

    uint8 private _decimals;

    address public owner;

    mapping(address => uint256) alreadyMinted;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _decimal
    ) ERC20(_name, _symbol) {
        _decimals = uint8(_decimal);

        owner = msg.sender;
    }

    function mint(address _to, uint256 _amount) external {
        if (msg.sender != owner) {
            require(alreadyMinted[_to] + _amount <= MAX_HOLD);
        }

        alreadyMinted[_to] += _amount;
        _mint(_to, _amount);
    }

    function burn(address _to, uint256 _amount) external {
        require(msg.sender == owner);
        alreadyMinted[_to] -= _amount;
        _burn(_to, _amount);
    }
}

