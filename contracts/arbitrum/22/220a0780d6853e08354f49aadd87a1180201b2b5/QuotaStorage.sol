// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "./QuotaLib.sol";

/**
 * Two-way mapping between quota and quota id
 */
abstract contract QuotaStorage {
    /// @notice Get quota id by its hash
    mapping(bytes32 quotaHash => uint64 quotaId) public quotaIdsByHash;

    /// @dev Quota details by id
    mapping(uint64 quotaId => Quota quota) internal _quotasById;

    uint64 internal _quotaCounter;

    /// @notice Get quota by its hash
    function getQuotaByHash(bytes32 quotaHash) public view returns (Quota memory quota) {
        return _quotasById[quotaIdsByHash[quotaHash]];
    }

    /// @notice Get quota by its id
    function getQuotaById(uint64 quotaId) public view returns (Quota memory quota) {
        return _quotasById[quotaId];
    }

    /// @dev Store quota and assign an ID, if it's not already stored
    function _storeQuota(Quota memory quota) internal {
        bytes32 quotaHash = QuotaLib.hash(quota);
        if (quotaIdsByHash[quotaHash] == 0) {
            _quotasById[quotaIdsByHash[quotaHash] = (++_quotaCounter)] = quota;
        }
    }

    /// @dev Reserved space for future storage layout upgrades
    uint256[47] private __gap;
}

