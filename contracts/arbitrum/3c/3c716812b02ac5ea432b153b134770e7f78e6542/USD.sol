// SPDX-License-Identifier: MIT

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|
//

pragma solidity 0.8.19;

import { ERC20Burnable, ERC20 } from "./ERC20Burnable.sol";
import { Ownable } from "./Ownable.sol";

/*
 * Title: USD
 * Author: Torque Inc.
 * Collateral: Exogenous
 * Minting: Algorithmic
 * Stability: USD Peg
 * Collateral: Crypto
 *
 * This contract is owned by the USDEngine.
 */
contract USD is ERC20Burnable, Ownable {
    error USD__AmountMustBeMoreThanZero();
    error USD__BurnAmountExceedsBalance();
    error USD__NotZeroAddress();

    constructor() ERC20("USD Stablecoin", "USD") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert USD__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert USD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert USD__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert USD__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

