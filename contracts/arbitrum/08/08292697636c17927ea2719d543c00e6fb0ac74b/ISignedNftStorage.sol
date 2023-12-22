// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

abstract contract ISignedNftStorage {
    function _signer() internal virtual view returns (address);
    function _signer(address newSigner) internal virtual;

    function _getUsedAndSet(uint64 externalId) internal virtual returns (bool);
    function _getUsed(uint64 externalId) internal view virtual returns (bool);
}

