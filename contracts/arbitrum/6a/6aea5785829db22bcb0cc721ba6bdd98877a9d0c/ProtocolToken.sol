// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./SafeMath.sol";
import "./ERC20Capped.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract ProtocolToken is ERC20Capped, ERC20Burnable, Ownable {
    using SafeMath for uint;

    constructor(uint totalSupply, address assetManager, string memory name, string memory symbol) ERC20(name, symbol) ERC20Capped(totalSupply) {
        _mint(assetManager, totalSupply);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Capped) {
        super._beforeTokenTransfer(from, to, amount);
    }
}

