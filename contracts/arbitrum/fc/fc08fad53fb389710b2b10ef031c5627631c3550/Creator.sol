// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {UpgradeableOperable} from "./UpgradeableOperable.sol";
import {BeaconProxy} from "./BeaconProxy.sol";
import {BeaconDiamond, DiamondArgs} from "./BeaconDiamond.sol";
import {IDiamond} from "./IDiamond.sol";

contract Creator is UpgradeableOperable {
    // For beacon and clone proxy contracts
    address[] private implementations;
    // beacon contracts
    address[] private beacons;
    // For diamond facets
    IDiamond.BeaconCut[] private facets;

    address private diamondInit;
    bytes private initData;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initialize(address _diamondInit) external initializer {
        __Governable_init(msg.sender);

        diamondInit = _diamondInit;
        initData = abi.encodeWithSignature("init()");
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function setImplementations(address[] memory _impls) external onlyGovernor {
        uint256 length = _impls.length;
        // 0  -> Vault
        // 1  -> Farm Adapter
        // 2  -> LP Adapter
        // 3  -> Swap Adapter
        for (uint256 i; i < length;) {
            implementations.push(_impls[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setBeacons(address[] memory _beacons) external onlyGovernor {
        uint256 length = _beacons.length;
        // 0  -> Compound Strategy
        // 1  -> Option Strategy
        // 2  -> Option Adapter
        for (uint256 i; i < length;) {
            beacons.push(_beacons[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setFacets(IDiamond.BeaconCut[] memory _facets) external onlyGovernor {
        uint256 length = _facets.length;
        // 0  -> OwnershipFacet
        // 1  -> DiamondCutFacet
        // 2  -> DiamondLoupeFacet
        // 3  -> RouterFacet
        // 4  -> DepositFacet
        // 5  -> WithdrawFacet
        // 6  -> FlipFacet
        for (uint256 i; i < length;) {
            facets.push(_facets[i]);
            unchecked {
                ++i;
            }
        }
    }

    function updateDiamondInit(address _diamondInit) external onlyGovernor {
        diamondInit = _diamondInit;
    }

    function updateInitData(bytes memory _initData) external onlyGovernor {
        initData = _initData;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    function createDiamond(address _owner) external onlyOperator returns (address) {
        return address(
            new BeaconDiamond(facets, DiamondArgs({
            init: diamondInit,
            initCalldata: initData,
            owner: _owner
            }))
        );
    }

    function createBeacon(address _beacon) external onlyOperator returns (address) {
        return address(new BeaconProxy(_beacon, ""));
    }

    /* -------------------------------------------------------------------------- */
    /*                                   VIEW                                     */
    /* -------------------------------------------------------------------------- */

    function getDiamondArgs(address _owner) external view returns (DiamondArgs memory) {
        return DiamondArgs({init: diamondInit, initCalldata: initData, owner: _owner});
    }

    function getFacets() external view returns (IDiamond.BeaconCut[] memory) {
        return facets;
    }

    function getImplementations() external view returns (address[] memory) {
        return implementations;
    }

    function getBeacons() external view returns (address[] memory) {
        return beacons;
    }
}

