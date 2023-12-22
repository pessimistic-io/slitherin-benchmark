// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct CurveSettings {
    address mainRegistry;
    address cryptoRegistry;
    address cryptoFactory;
}

struct Amm {
    uint8 protocolId;
    bytes4 selector;
    address addr;
}

struct AppStorage {
    address weth;
    address magpieAggregatorAddress;
    mapping(uint16 => Amm) amms;
    CurveSettings curveSettings;
}

library LibMagpieRouter {
    function getStorage() internal pure returns (AppStorage storage s) {
        assembly {
            s.slot := 0
        }
    }
}

