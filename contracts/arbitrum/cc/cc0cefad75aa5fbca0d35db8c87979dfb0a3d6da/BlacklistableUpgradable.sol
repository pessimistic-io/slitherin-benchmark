// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "./Initializable.sol";
import {ContextUpgradeable} from "./ContextUpgradeable.sol";

contract BlacklistableUpgradable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:fortesecurities.BlacklistableUpgradable
    struct BlacklistableUpgradableStorage {
        mapping(address => bool) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("fortesecurities.BlacklistableUpgradable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BlacklistableUpgradableStorageLocation =
        0x8ecc1f59a42058624dce41c94b4f8aa95e42142a4f40b370d396f94cbf8ede00;

    function _getBlacklistableUpgradableStorage() private pure returns (BlacklistableUpgradableStorage storage $) {
        assembly {
            $.slot := BlacklistableUpgradableStorageLocation
        }
    }

    error Blacklisted(address account);

    function __Blacklistable_init() internal onlyInitializing {
        __Blacklistable_init_unchained();
    }

    function __Blacklistable_init_unchained() internal onlyInitializing {}

    /**
     * @dev Emitted when an `account` is blacklisted.
     */
    event Blacklist(address account);

    /**
     * @dev Emitted when an `account` is removed from the blacklist.
     */
    event UnBlacklist(address account);

    /**
     * @dev Throws if argument account is blacklisted
     * @param account The address to check
     */
    modifier notBlacklisted(address account) {
        if (isBlacklisted(account)) {
            revert Blacklisted(account);
        }
        _;
    }

    /**
     * @dev Checks if account is blacklisted
     * @param account The address to check
     */
    function isBlacklisted(address account) public view returns (bool) {
        BlacklistableUpgradableStorage storage $ = _getBlacklistableUpgradableStorage();
        return $.blacklisted[account];
    }

    /**
     * @dev Adds account to blacklist
     * @param account The address to blacklist
     */
    function _blacklist(address account) internal virtual {
        BlacklistableUpgradableStorage storage $ = _getBlacklistableUpgradableStorage();
        $.blacklisted[account] = true;
        emit Blacklist(account);
    }

    /**
     * @dev Removes account from blacklist
     * @param account The address to remove from the blacklist
     */
    function _unBlacklist(address account) internal virtual {
        BlacklistableUpgradableStorage storage $ = _getBlacklistableUpgradableStorage();
        $.blacklisted[account] = false;
        emit UnBlacklist(account);
    }
}

