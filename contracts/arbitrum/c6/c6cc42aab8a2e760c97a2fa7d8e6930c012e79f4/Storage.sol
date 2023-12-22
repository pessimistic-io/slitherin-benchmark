// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { AccrualData } from "./DataTypes.sol";
import { EnumerableSet } from "./EnumerableSet.sol";

/// @title TokenStorage
/// @dev defines storage layout for the Token facet
library TokenStorage {
    struct Layout {
        /// @dev ratio of distributionSupply to totalSupply
        uint256 globalRatio;
        /// @dev number of tokens held for distribution to token holders
        uint256 distributionSupply;
        /// @dev number of tokens held for airdrop dispersion
        uint256 airdropSupply;
        /// @dev fraction of tokens to be reserved for distribution to token holders in basis points
        uint32 distributionFractionBP;
        /// @dev information related to Token accruals for an account
        mapping(address account => AccrualData data) accrualData;
        /// @dev set of contracts which are allowed to call the mint function
        EnumerableSet.AddressSet mintingContracts;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("insrt.contracts.storage.MintToken");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

