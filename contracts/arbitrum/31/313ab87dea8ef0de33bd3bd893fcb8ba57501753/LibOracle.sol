// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import "./ECDSA.sol";
import { SchnorrSign, IMuonV03 } from "./IMuonV03.sol";
import { C } from "./C.sol";

struct PositionPrice {
    uint256 positionId;
    uint256 bidPrice;
    uint256 askPrice;
}

library LibOracle {
    using ECDSA for bytes32;

    /**
     * @notice Verify the binding of prices with the positionId
     */
    function verifyPositionPriceOrThrow(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        uint256 timestamp_,
        SchnorrSign[] calldata sigs
    ) internal {
        require(sigs.length >= C.getMinimumRequiredSignatures(), "Insufficient signatures");

        bytes32 hash = keccak256(abi.encodePacked(C.getMuonAppId(), reqId, positionId, bidPrice, askPrice, timestamp_));
        IMuonV03 _muon = IMuonV03(C.getMuon());

        bool verified = _muon.verify(reqId, uint256(hash), sigs);
        require(verified, "Invalid signatures");
    }

    /**
     * @notice Verify the binding of prices with the positionIds
     * @dev The caller defines the positionIds and its order, Muon doesn't perform a check.
     * @dev Prices are valid by expiration, but the positionIds are valid per-block.
     */
    function verifyPositionPricesOrThrow(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices,
        bytes calldata reqId,
        uint256 timestamp_,
        SchnorrSign[] calldata sigs
    ) internal {
        require(sigs.length >= C.getMinimumRequiredSignatures(), "Insufficient signatures");

        bytes32 hash = keccak256(
            abi.encodePacked(C.getMuonAppId(), reqId, positionIds, bidPrices, askPrices, timestamp_)
        );
        IMuonV03 _muon = IMuonV03(C.getMuon());

        bool verified = _muon.verify(reqId, uint256(hash), sigs);
        require(verified, "Invalid signatures");
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

