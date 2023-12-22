// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISupa} from "./ISupa.sol";
import {FsUtils} from "./FsUtils.sol";

import {Errors} from "./Errors.sol";

/// @title the state part of the WalletLogic. A parent to all contracts that form wallet
/// @dev the contract is abstract because it is not expected to be used separately from wallet
abstract contract WalletState {
    modifier onlyOwner() {
        require(msg.sender == supa.getWalletOwner(address(this)), "WalletState: only this");
        _;
    }

    /// @dev Supa instance to be used by all other wallet contracts
    ISupa public supa;

    /// @param _supa - address of a deployed Supa contract
    constructor(address _supa) {
        // slither-disable-next-line missing-zero-check
        supa = ISupa(FsUtils.nonNull(_supa));
    }

    /// @notice Point the wallet to a new Supa contract
    /// @dev This function is only callable by the wallet itself
    /// @param _supa - address of a deployed Supa contract
    function updateSupa(address _supa) external onlyOwner {
        // 1. Get the current wallet details
        // 1a. Get the wallet owner
        address currentOwner = supa.getWalletOwner(address(this));
        // 1b. Get the current implementation
        address implementation = supa.getImplementation(address(this));

        // 2. Update the supa implementation
        if (_supa == address(0) || _supa == address(supa)) {
            revert Errors.AddressZero();
        }
        supa = ISupa(_supa);

        // 3. Call the new supa to update the wallet owner
        supa.migrateWallet(address(this), currentOwner, implementation);
    }
}

