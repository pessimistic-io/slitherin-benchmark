// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20Burnable.sol";
import "./ERC20.sol";
import "./Ownable.sol";

contract bDEI is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public minter;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function setMinters(
        address[] calldata _minters,
        bool _isMinter
    ) external onlyOwner {
        for (uint256 i = 0; i < _minters.length; i++) {
            minter[_minters[i]] = _isMinter;
        }
    }

    function mint(address _to, uint256 _amount) public {
        require(minter[msg.sender], "not minter");
        _mint(_to, _amount);
    }
}

