// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FsUtils} from "./FsUtils.sol";
import {GitCommitHash} from "./GitCommitHash.sol";

/// @title ImmutableVersion
/// @dev This contract is meant to be inherited by other contracts, to version them.
/// @notice Inherits from GitCommitHash to tie the version to the commit hash in the git repo.
contract ImmutableVersion is GitCommitHash {
    address private supa; // TODO: this is here to not overwrite the supa address in WalletState, but it's not used
    bytes32 public immutable immutableVersion;

    constructor(string memory _version) {
        require(bytes(_version).length > 0, "Version is empty");
        immutableVersion = FsUtils.encodeToBytes32(bytes(_version));
    }
}

