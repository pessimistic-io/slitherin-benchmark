// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { LibOracle, SchnorrSign } from "./LibOracle.sol";

contract OracleFacet {
    /*------------------------*
     * PUBLIC VIEW FUNCTIONS *
     *------------------------*/

    function verifyTSSOrThrow(string calldata data, bytes calldata reqId, SchnorrSign calldata sign) external view {
        LibOracle.verifyTSSOrThrow(data, reqId, sign);
    }

    function verifyPositionPriceOrThrow(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external view {
        LibOracle.verifyPositionPriceOrThrow(positionId, bidPrice, askPrice, reqId, sign, gatewaySignature);
    }

    function verifyPositionPricesOrThrow(
        uint256[] memory positionIds,
        uint256[] memory bidPrices,
        uint256[] memory askPrices,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external view {
        LibOracle.verifyPositionPricesOrThrow(positionIds, bidPrices, askPrices, reqId, sign, gatewaySignature);
    }
}

