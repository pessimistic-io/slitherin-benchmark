// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { RescuableUpgradeable } from "./RescuableUpgradeable.sol";
import { PausableExtUpgradeable } from "./PausableExtUpgradeable.sol";
import { BlacklistableUpgradeable } from "./BlacklistableUpgradeable.sol";

/**
 * @title BRLCTokenBase contract
 * @dev This contract is base implementation of the BRLC token with inherited Rescuable,
 * Pausable, and Blacklistable functionality.
 */
abstract contract BRLCTokenBase is
    OwnableUpgradeable,
    RescuableUpgradeable,
    PausableExtUpgradeable,
    BlacklistableUpgradeable,
    ERC20Upgradeable
{
    function __BRLCTokenBase_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Rescuable_init_unchained();
        __Pausable_init_unchained();
        __PausableExt_init_unchained();
        __Blacklistable_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        __BRLCTokenBase_init_unchained();
    }

    function __BRLCTokenBase_init_unchained() internal onlyInitializing {}

    /**
     * @dev See {ERC20Upgradeable-decimals}.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev See {ERC20Upgradeable-transfer}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - The `_msgSender()` address must not be blacklisted.
     * - The `recipient` address must not be blacklisted.
     */
    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(recipient)
        returns (bool)
    {
        return super.transfer(recipient, amount);
    }

    /**
     * @dev See {ERC20Upgradeable-approve}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - The `_msgSender()` address must not be blacklisted.
     * - The `spender` address must not be blacklisted.
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    /**
     * @dev See {ERC20Upgradeable-transferFrom}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - The `sender` address must not be blacklisted.
     * - The `recipient` address must not be blacklisted.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @dev See {ERC20Upgradeable-increaseAllowance}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - The `_msgSender()` address must not be blacklisted.
     * - The `spender` address must not be blacklisted.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        return super.increaseAllowance(spender, addedValue);
    }

    /**
     * @dev See {ERC20Upgradeable-decreaseAllowance}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - The `_msgSender()` address must not be blacklisted.
     * - The `spender` address must not be blacklisted.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        return super.decreaseAllowance(spender, subtractedValue);
    }

    /**
     * @dev See {ERC20Upgradeable-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused(), "ERC20Pausable: token transfer while paused");
    }
}

