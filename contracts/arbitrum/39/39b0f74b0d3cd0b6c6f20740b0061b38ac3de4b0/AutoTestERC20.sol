// SPDX-License-Identifier: BUSL-1.1
/*
 * Test ETC20 class for poption
 * Copyright ©2022 by Poption.org.
 * Author: Poption <hydrogenbear@poption.org>
 */

pragma solidity ^0.8.4;

import "./ERC20.sol";

contract AutoTestERC20 is ERC20 {
    uint8 private _dec;
    mapping(address => bool) public touched;
    uint256 private _default;

    constructor(
        string memory name,
        string memory symbol,
        uint8 dec_,
        uint256 default_
    ) ERC20(name, symbol) {
        _dec = dec_;
        _default = default_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _dec;
    }

    function mint(uint256 amount) public {
        touched[msg.sender] = true;
        _mint(msg.sender, amount);
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        if (touched[account]) {
            return super.balanceOf(account);
        } else {
            return _default;
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        if (!touched[from]) {
            if (from != address(0)) {
                _mint(from, _default);
            }
            touched[from] = true;
        }
        if (!touched[to]) {
            touched[to] = true;
        }
    }
}

