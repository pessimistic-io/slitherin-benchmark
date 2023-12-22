// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { UFixed18 } from "./Token18.sol";
interface ISeasonalMerkleClaim {
    /// @notice Thrown if proposed root in claim was not added by onwer
    /// @dev sig: 0x276e15bb
    error InvalidRoot(bytes32 root);

    /// @notice Thrown if address has already claimed
    /// @dev sig: 0x646cf558
    error AlreadyClaimed();

    /// @notice Thrown if address/amount are not part of Merkle tree
    /// @dev sig: 0x9f4e07dc
    error InvalidClaim(address account, bytes32 root);

    event Claimed(address indexed to, bytes32 indexed root, UFixed18 amount);
    event RootAdded(bytes32 root);
    event RootRemoved(bytes32 root);
}
