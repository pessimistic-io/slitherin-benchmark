// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import "./console.sol";
import {IGuild} from "./IGuild.sol";
import {UpgradeableERC20} from "./UpgradeableERC20.sol";
import {SafeMath} from "./SafeMath.sol";
import {Errors} from "./Errors.sol";

/**
 * @title MintableUpgradeableERC20
 * @author Tazz Labs, inspired by AAVE MintableIncentivizedERC20
 * @notice Implements mint and burn functions for UpgradeableERC20
 **/
abstract contract MintableUpgradeableERC20 is UpgradeableERC20 {
    using SafeMath for uint256;

    /**
     * @dev Constructor.
     * @param guild The reference to the main Guild contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals The number of decimals of the token
     */
    constructor(
        IGuild guild,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) UpgradeableERC20(guild, name, symbol, decimals) {
        // Intentionally left blank
    }

    /**
     * @notice Mints tokens to an account
     * @param account The address receiving tokens
     * @param amount The amount of tokens to mint
     */
    function _mint(address account, uint256 amount) internal virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burns tokens from an account
     * @param account The account whose tokens are burnt
     * @param amount The amount of tokens to burn
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(_balances[account] >= amount, Errors.INSUFFICIENT_BALANCE_TO_BURN);
        _balances[account] = _balances[account].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }
}

