// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "./ECDSA.sol";
import { OracleStorage, PublicKey, SchnorrSign, PositionPrice } from "./OracleStorage.sol";
import { SchnorrSECP256K1Verifier } from "./SchnorrSECP256K1Verifier.sol";

library OracleInternal {
    using OracleStorage for OracleStorage.Layout;
    using ECDSA for bytes32;

    /* ========== VIEWS ========== */

    function getMuonAppId() internal view returns (uint256) {
        return OracleStorage.layout().muonAppId;
    }

    function getMuonAppCID() internal view returns (bytes memory) {
        return OracleStorage.layout().muonAppCID;
    }

    function getMuonPublicKey() internal view returns (PublicKey memory) {
        return OracleStorage.layout().muonPublicKey;
    }

    function getMuonGatewaySigner() internal view returns (address) {
        return OracleStorage.layout().muonGatewaySigner;
    }

    function getSignatureExpiryPeriod() internal view returns (uint256) {
        return OracleStorage.layout().signatureExpiryPeriod;
    }

    function verifyTSSOrThrow(string calldata data, bytes calldata reqId, SchnorrSign calldata sign) internal view {
        (uint256 muonAppId, bytes memory muonAppCID, PublicKey memory muonPublicKey, ) = _getMuonConstants();

        bytes32 hash = keccak256(abi.encodePacked(muonAppId, reqId, muonAppCID, data));
        bool verified = _verifySignature(uint256(hash), sign, muonPublicKey);
        require(verified, "TSS not verified");
    }

    // To get the gatewaySignature, gwSign=true should be passed to the MuonApp.
    function verifyTSSAndGatewayOrThrow(
        bytes32 hash,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (, , PublicKey memory muonPublicKey, address muonGatewaySigner) = _getMuonConstants();

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
        uint256 timestamp,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (uint256 muonAppId, bytes memory muonAppCID, , ) = _getMuonConstants();
        require(timestamp + getSignatureExpiryPeriod() >= block.timestamp, "Signature expired");

        bytes32 hash = keccak256(
            abi.encodePacked(muonAppId, reqId, muonAppCID, positionId, bidPrice, askPrice, timestamp)
        );
        verifyTSSAndGatewayOrThrow(hash, sign, gatewaySignature);
    }

    function verifyPositionPricesOrThrow(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices,
        uint256 timestamp,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal view {
        (uint256 muonAppId, bytes memory muonAppCID, , ) = _getMuonConstants();
        require(timestamp + getSignatureExpiryPeriod() >= block.timestamp, "Signature expired");

        bytes32 hash = keccak256(
            abi.encodePacked(muonAppId, reqId, muonAppCID, positionIds, bidPrices, askPrices, timestamp)
        );
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
            positionIds.length == bidPrices.length && positionIds.length == askPrices.length,
            "Invalid position prices"
        );

        positionPrices = new PositionPrice[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            positionPrices[i] = PositionPrice(positionIds[i], bidPrices[i], askPrices[i]);
        }
    }

    /* ========== SETTERS ========== */

    function setMuonAppId(uint256 muonAppId) internal {
        OracleStorage.layout().muonAppId = muonAppId;
    }

    function setMuonAppCID(bytes calldata muonAppCID) internal {
        OracleStorage.layout().muonAppCID = muonAppCID;
    }

    function setMuonPublicKey(PublicKey memory muonPublicKey) internal {
        OracleStorage.layout().muonPublicKey = muonPublicKey;
    }

    function setMuonGatewaySigner(address muonGatewaySigner) internal {
        OracleStorage.layout().muonGatewaySigner = muonGatewaySigner;
    }

    function setSignatureExpiryPeriod(uint256 signatureExpiryPeriod) internal {
        OracleStorage.layout().signatureExpiryPeriod = signatureExpiryPeriod;
    }

    /* ========== PRIVATE ========== */

    function _getMuonConstants()
        private
        view
        returns (uint256 muonAppId, bytes memory muonAppCID, PublicKey memory muonPublicKey, address muonGatewaySigner)
    {
        return (getMuonAppId(), getMuonAppCID(), getMuonPublicKey(), getMuonGatewaySigner());
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
}

