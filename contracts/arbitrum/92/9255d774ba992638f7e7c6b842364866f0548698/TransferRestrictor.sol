// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2Step} from "./Ownable2Step.sol";
import {ITransferRestrictor} from "./ITransferRestrictor.sol";

/// @notice Enforces transfer restrictions
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/TransferRestrictor.sol)
/// Maintains a single `owner` who can add or remove accounts from `isBlacklisted`
contract TransferRestrictor is Ownable2Step, ITransferRestrictor {
    /// ------------------ Types ------------------ ///

    /// @dev Account is restricted
    error AccountRestricted();

    /// @dev Emitted when `account` is added to `isBlacklisted`
    event Restricted(address indexed account);
    /// @dev Emitted when `account` is removed from `isBlacklisted`
    event Unrestricted(address indexed account);

    /// ------------------ State ------------------ ///

    /// @notice Accounts in `isBlacklisted` cannot send or receive tokens
    mapping(address => bool) public isBlacklisted;

    /// ------------------ Initialization ------------------ ///

    constructor(address owner) {
        _transferOwnership(owner);
    }

    /// ------------------ Setters ------------------ ///

    /// @notice Restrict `account` from sending or receiving tokens
    /// @dev Does not check if `account` is restricted
    /// Can only be called by `owner`
    function restrict(address account) external onlyOwner {
        isBlacklisted[account] = true;
        emit Restricted(account);
    }

    /// @notice Unrestrict `account` from sending or receiving tokens
    /// @dev Does not check if `account` is restricted
    /// Can only be called by `owner`
    function unrestrict(address account) external onlyOwner {
        isBlacklisted[account] = false;
        emit Unrestricted(account);
    }

    /// ------------------ Transfer Restriction ------------------ ///

    /// @inheritdoc ITransferRestrictor
    function requireNotRestricted(address from, address to) external view virtual {
        // Check if either account is restricted
        if (isBlacklisted[from] || isBlacklisted[to]) {
            revert AccountRestricted();
        }
        // Otherwise, do nothing
    }
}

