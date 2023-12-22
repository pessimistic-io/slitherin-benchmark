// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract FlashZToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    uint8 private immutable dec;

    constructor(string memory _tokenName, string memory _tokenSymbol, uint8 _decimals)
        ERC20(_tokenName, _tokenSymbol)
        ERC20Permit(_tokenName)
    {
        dec = _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burnOwner(address _from, uint256 amount) public onlyOwner {
        _burn(_from, amount);
    }

    function decimals() public view override returns (uint8) {
        return dec;
    }
}

