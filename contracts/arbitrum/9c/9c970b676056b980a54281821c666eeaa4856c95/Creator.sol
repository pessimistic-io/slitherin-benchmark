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

    address private proxyAdmin;
    address private diamondInit;
    bytes private initData;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initialize Creator contract.
     * @param _diamondInit contract address for diamond proxy.
     */
    function initialize(address _diamondInit) external initializer {
        __Governable_init(msg.sender);

        diamondInit = _diamondInit;
        initData = abi.encodeWithSignature("init()");
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Save proxy implementations.
     * @param _impls address of proxy implementations.
     */
    function setImplementations(address[] memory _impls) external onlyGovernor {
        // clean
        delete implementations;

        uint256 length = _impls.length;
        // 0  -> Vault
        // 1  -> Farm Adapter
        // 2  -> LP Adapter
        // 3  -> Swap Adapter
        // 4  -> Option Call Adapter
        // 5  -> Option Put Adapter
        for (uint256 i; i < length;) {
            implementations.push(_impls[i]);
            unchecked {
                ++i;
            }
        }

        emit SetImplementations(_impls);
    }

    /**
     * @notice Save beacon proxies.
     * @param _beacons address of beacon proxies.
     */
    function setBeacons(address[] memory _beacons) external onlyGovernor {
        // clean
        delete beacons;

        uint256 length = _beacons.length;
        // 0  -> Compound Strategy
        // 1  -> Option Strategy
        for (uint256 i; i < length;) {
            beacons.push(_beacons[i]);
            unchecked {
                ++i;
            }
        }

        emit SetBeacons(_beacons);
    }

    /**
     * @notice Save diamond proxy facets.
     * @param _facets Beacon diamond facets.
     */
    function setFacets(IDiamond.BeaconCut[] memory _facets) external onlyGovernor {
        // clean
        delete facets;

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

        emit SetFacets(_facets);
    }

    /**
     * @notice Update diamond init contract.
     * @param _diamondInit address of diamond init contract.
     */
    function updateDiamondInit(address _diamondInit) external onlyGovernor {
        diamondInit = _diamondInit;
    }

    /**
     * @notice Update diamond init data.
     * @param _initData diamond init data.
     */
    function updateInitData(bytes memory _initData) external onlyGovernor {
        initData = _initData;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Create new diamond proxy.
     * @param _owner Owner of the diamond proxy.
     * @return Diamond proxy address
     */
    function createDiamond(address _owner) external onlyOperator returns (address) {
        address diamond = address(
            new BeaconDiamond(facets, DiamondArgs({
            init: diamondInit,
            initCalldata: initData,
            owner: _owner
            }))
        );

        emit DiamondCreated(msg.sender, _owner, diamond);

        return diamond;
    }

    /**
     * @notice Create new beacon proxy.
     * @param _beacon beacon address.
     * @return Beacon proxy address.
     */
    function createBeacon(address _beacon) external onlyOperator returns (address) {
        address beaconProxy = address(new BeaconProxy(_beacon, ""));
        emit BeaconCreated(msg.sender, _beacon, beaconProxy);
        return beaconProxy;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   VIEW                                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get Facets.
     * @return Array of beacon diamond facets.
     */
    function getFacets() external view returns (IDiamond.BeaconCut[] memory) {
        return facets;
    }

    /**
     * @notice Get Proxy implementations.
     * @return Array of implementations addresses
     */
    function getImplementations() external view returns (address[] memory) {
        return implementations;
    }

    /**
     * @notice Get Beacons.
     * @return Array of beacon addresses
     */
    function getBeacons() external view returns (address[] memory) {
        return beacons;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event SetImplementations(address[] _impls);
    event SetBeacons(address[] _beacons);
    event SetFacets(IDiamond.BeaconCut[] _facets);
    event DiamondCreated(address indexed factory, address indexed owner, address diamond);
    event BeaconCreated(address indexed factory, address indexed beacon, address beaconProxy);
}

