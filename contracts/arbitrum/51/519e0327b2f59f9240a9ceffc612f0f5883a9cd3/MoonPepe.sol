// SPDX-License-Identifier: MIT

/*
 * Twitter: https://twitter.com/moonpepe_xyz
 * Telegram: https://t.me/moonpepearb
 */

pragma solidity ^0.8.9;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

contract MoonPepe is ERC20, Ownable {
    uint256 private immutable i_totalSupply = 420690000000 * 10 ** 6;
    uint256 public immutable i_limitPerWalletBeforeTime = 12620700000 * 10 ** 6; // 3 Percent of total supply
    uint256 public immutable i_limitPerWalletAfterTime = 42069000000 * 10 ** 6; // 10 Percent of total supply
    uint256 private immutable i_timeLimit = 2 weeks;
    uint256 public s_endTime;

    constructor() ERC20("Moon Pepe", "MPEPE") {
        _mint(0xB73dD84523EA65cfCAfaE204c9484cC19Ab3906e, i_totalSupply);
        s_endTime = block.timestamp + i_timeLimit;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 afterTokenBalance = balanceOf(to) + amount;

        if (block.timestamp <= s_endTime) {
            require(
                afterTokenBalance <= i_limitPerWalletBeforeTime,
                "ERC20: Owned amount exceeds the maximum limit"
            );
        } else {
            require(
                afterTokenBalance <= i_limitPerWalletAfterTime,
                "ERC20: Owned amount exceeds the maximum limit"
            );
        }

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }
}

