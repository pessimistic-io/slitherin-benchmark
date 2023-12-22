// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import { LibDiamond } from "./LibDiamond.sol";
import { AppStorage, LibAppStorage } from "./LibAppStorage.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IDiamondCut } from "./IDiamondCut.sol";
import { IERC165 } from "./IERC165.sol";

contract DiamondInit {
    function init(address _collateral, address _muon) external {
        // Initialize DiamondStorage
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;

        // Initialize AppStorage
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.constants.collateral = _collateral;
        s.constants.muon = _muon;
        s.constants.muonAppId = 0;
        s.constants.minimumRequiredSignatures = 0;
        s.constants.protocolFee = 0.0005e18; // 0.05%
        s.constants.liquidationFee = 0.005e18; // 0.5%
        s.constants.protocolLiquidationShare = 0.1e18; // 10%
        s.constants.cva = 0.02e18; // 2%
        s.constants.requestTimeout = 2 minutes;
        s.constants.maxOpenPositionsCross = 10;
    }
}

