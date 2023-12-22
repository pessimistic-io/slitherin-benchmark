// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library HedgerStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.hedger.storage");

    struct Layout {
        mapping(address => bool) masterAgreementMap;
        mapping(address => address) collateralMap; // masterAgreement => collateral
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

