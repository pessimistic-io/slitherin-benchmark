// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

/// @notice Writes notes to event log during deployment.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/AnnotatingConstructor.sol)
abstract contract AnnotatingConstructor {
    event Deployed(address indexed contractAddress, string[] note);

    constructor(string[] memory notes) {
        emit Deployed(address(this), notes);
    }
}

