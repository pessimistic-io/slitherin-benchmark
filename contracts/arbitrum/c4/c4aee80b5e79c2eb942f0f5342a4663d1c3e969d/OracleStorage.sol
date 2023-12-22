// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct SchnorrSign {
    uint256 signature;
    address owner;
    address nonce;
}

struct PublicKey {
    uint256 x;
    uint8 parity;
}

struct PositionPrice {
    uint256 positionId;
    uint256 bidPrice;
    uint256 askPrice;
}

library OracleStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.oracle.storage");

    struct Layout {
        uint256 muonAppId;
        bytes muonAppCID;
        PublicKey muonPublicKey;
        address muonGatewaySigner;
        uint256 signatureExpiryPeriod;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

