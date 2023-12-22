// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC20} from "./ERC20.sol";

/// @notice Base implementation for ERC20s.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/ERC20Base.sol)
abstract contract ERC20Base is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function transfer(address to, uint256 amount) public virtual override returns (bool success) {
        _beforeTokenTransfer(msg.sender, to, amount);
        success = super.transfer(to, amount);
        _afterTokenTransfer(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool success) {
        _beforeTokenTransfer(from, to, amount);
        success = super.transferFrom(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual override {
        _beforeTokenTransfer(address(0), to, amount);
        super._mint(to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual override {
        _beforeTokenTransfer(from, address(0), amount);
        super._burn(from, amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        return approve(spender, allowance[msg.sender][spender] + addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        return approve(spender, allowance[msg.sender][spender] - subtractedValue);
    }
}

