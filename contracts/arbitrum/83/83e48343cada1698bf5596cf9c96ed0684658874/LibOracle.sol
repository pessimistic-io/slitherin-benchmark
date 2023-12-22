// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import "./ECDSA.sol";
import "./SchnorrSECP256K1Verifier.sol";
import { C } from "./C.sol";

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

library LibOracle {
    using ECDSA for bytes32;

    /*------------------------*
     * PRIVATE VIEW FUNCTIONS *
     *------------------------*/

    function _getMuonConstants()
        private
        view
        returns (uint256 muonAppId, PublicKey memory muonPublicKey, address muonGatewaySigner)
    {
        return (C.getMuonAppId(), C.getMuonPublicKey(), C.getMuonGatewaySigner());
    }

    function _verifySignature(
        uint256 hash,
        SchnorrSign memory signature,
        PublicKey memory pubKey
    ) private pure returns (bool) {
        return
            SchnorrSECP256K1Verifier.verifySignature(
                pubKey.x,
                pubKey.parity,
                signature.signature,
                hash,
                signature.nonce
            );
    }

    /*-------------------------*
     * INTERNAL VIEW FUNCTIONS *
     *-------------------------*/

    function verifyTSSOrThrow(string calldata data, bytes calldata reqId, SchnorrSign calldata sign) internal view {
        (uint256 muonAppId, PublicKey memory muonPublicKey, ) = _getMuonConstants();

        bytes32 hash = keccak256(abi.encodePacked(muonAppId, reqId, data));
        bool verified = _verifySignature(uint256(hash), sign, muonPublicKey);
        require(verified, "TSS not verified");
    }

    // To get the gatewaySignature, gwSign=true should be passed to the MuonApp.
    function verifyTSSAndGatewayOrThrow(
        bytes32 hash,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (, PublicKey memory muonPublicKey, address muonGatewaySigner) = _getMuonConstants();

        bool verified = _verifySignature(uint256(hash), sign, muonPublicKey);
        require(verified, "TSS not verified");

        hash = hash.toEthSignedMessageHash();
        address gatewaySigner = hash.recover(gatewaySignature);
        require(gatewaySigner == muonGatewaySigner, "Invalid gateway signer");
    }

    function verifyPositionPriceOrThrow(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (uint256 muonAppId, , ) = _getMuonConstants();

        bytes32 hash = keccak256(abi.encodePacked(muonAppId, reqId, positionId, bidPrice, askPrice));
        verifyTSSAndGatewayOrThrow(hash, sign, gatewaySignature);
    }

    function verifyPositionPricesOrThrow(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (uint256 muonAppId, , ) = _getMuonConstants();

        bytes32 hash = keccak256(abi.encodePacked(muonAppId, reqId, positionIds, bidPrices, askPrices));
        verifyTSSAndGatewayOrThrow(hash, sign, gatewaySignature);
    }

    function createPositionPrice(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) internal pure returns (PositionPrice memory positionPrice) {
        return PositionPrice(positionId, bidPrice, askPrice);
    }

    function createPositionPrices(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices
    ) internal pure returns (PositionPrice[] memory positionPrices) {
        require(
            positionPrices.length == bidPrices.length && positionPrices.length == askPrices.length,
            "Invalid position prices"
        );

        positionPrices = new PositionPrice[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            positionPrices[i] = PositionPrice(positionIds[i], bidPrices[i], askPrices[i]);
        }
    }
}

