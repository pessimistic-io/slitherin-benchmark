// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { Decimal } from "./LibDecimal.sol";

library C {
    using Decimal for Decimal.D256;

    // Collateral
    address private constant COLLATERAL = 0xB62F2fb600D39A44883688DE20A8E058c76Ad558; // TODO

    // System
    uint256 private constant PERCENT_BASE = 1e18;
    uint256 private constant PRECISION = 1e18;

    // Oracle
    address private constant MUON = 0xE4F8d9A30936a6F8b17a73dC6fEb51a3BBABD51A;
    uint16 private constant MUON_APP_ID = 0; // TODO
    uint8 private constant MIN_REQUIRED_SIGNATURES = 0; // TODO

    // Configuration
    uint256 private constant PROTOCOL_FEE = 0.0005e18; // 0.05%
    uint256 private constant LIQUIDATION_FEE = 0.005e18; // 0.5%
    uint256 private constant PROTOCOL_LIQUIDATION_SHARE = 0.1e18; // 10%
    uint256 private constant CVA = 0.02e18; // 2%
    uint256 private constant REQUEST_TIMEOUT = 1 minutes;
    uint256 private constant MAX_OPEN_POSITIONS_CROSS = 10;

    function getCollateral() internal pure returns (address) {
        return COLLATERAL;
    }

    function getPrecision() internal pure returns (uint256) {
        return PRECISION;
    }

    function getMuon() internal pure returns (address) {
        return MUON;
    }

    function getMuonAppId() internal pure returns (uint16) {
        return MUON_APP_ID;
    }

    function getMinimumRequiredSignatures() internal pure returns (uint8) {
        return MIN_REQUIRED_SIGNATURES;
    }

    function getProtocolFee() internal pure returns (Decimal.D256 memory) {
        return Decimal.ratio(PROTOCOL_FEE, PERCENT_BASE);
    }

    function getLiquidationFee() internal pure returns (Decimal.D256 memory) {
        return Decimal.ratio(LIQUIDATION_FEE, PERCENT_BASE);
    }

    function getProtocolLiquidationShare() internal pure returns (Decimal.D256 memory) {
        return Decimal.ratio(PROTOCOL_LIQUIDATION_SHARE, PERCENT_BASE);
    }

    function getCVA() internal pure returns (Decimal.D256 memory) {
        return Decimal.ratio(CVA, PERCENT_BASE);
    }

    function getRequestTimeout() internal pure returns (uint256) {
        return REQUEST_TIMEOUT;
    }

    function getMaxOpenPositionsCross() internal pure returns (uint256) {
        return MAX_OPEN_POSITIONS_CROSS;
    }

    function getChainId() internal view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
}

