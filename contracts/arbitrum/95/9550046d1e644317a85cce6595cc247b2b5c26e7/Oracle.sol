// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { OracleInternal } from "./OracleInternal.sol";
import { PublicKey, SchnorrSign } from "./OracleStorage.sol";

contract Oracle {
    function getMuonAppId() external view returns (uint256) {
        return OracleInternal.getMuonAppId();
    }

    function getMuonAppCID() external view returns (bytes memory) {
        return OracleInternal.getMuonAppCID();
    }

    function getMuonPublicKey() external view returns (PublicKey memory) {
        return OracleInternal.getMuonPublicKey();
    }

    function getMuonGatewaySigner() external view returns (address) {
        return OracleInternal.getMuonGatewaySigner();
    }

    function verifyTSSOrThrow(string calldata data, bytes calldata reqId, SchnorrSign calldata sign) external view {
        OracleInternal.verifyTSSOrThrow(data, reqId, sign);
    }

    function verifyTSSAndGatewayOrThrow(
        bytes32 hash,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external view {
        OracleInternal.verifyTSSAndGatewayOrThrow(hash, sign, gatewaySignature);
    }

    function verifyPositionPriceOrThrow(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external view {
        OracleInternal.verifyPositionPriceOrThrow(positionId, bidPrice, askPrice, reqId, sign, gatewaySignature);
    }

    function verifyPositionPricesOrThrow(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external view {
        OracleInternal.verifyPositionPricesOrThrow(positionIds, bidPrices, askPrices, reqId, sign, gatewaySignature);
    }
}

