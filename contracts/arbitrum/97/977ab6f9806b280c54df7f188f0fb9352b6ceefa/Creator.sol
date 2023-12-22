// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {UpgradeableOperable} from "./UpgradeableOperable.sol";
import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";
import {Diamond} from "./Diamond.sol";
import {IDiamond} from "./IDiamond.sol";
import {DiamondArgs} from "./Diamond.sol";

contract Creator is UpgradeableOperable {
    // For transparent and clone proxy contracts
    address[] private implementations;
    // For diamond facets
    IDiamond.FacetCut[] private facets;

    address private proxyAdmin;
    address private diamondInit;
    bytes private initData;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initialize(address _proxyAdmin, address _diamondInit) external initializer {
        __Governable_init(msg.sender);

        proxyAdmin = _proxyAdmin;
        diamondInit = _diamondInit;
        initData = abi.encodeWithSignature("init()");
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function setImplementations(address[] memory _impls) external onlyGovernor {
        uint256 length = _impls.length;
        // 0  -> Vault
        // 1  -> Compound Strategy
        // 2  -> Option Strategy
        // 3  -> Option Adapter
        // 4  -> Farm Adapter
        // 5  -> LP Adapter
        // 6  -> Swap Adapter
        for (uint256 i; i < length;) {
            implementations.push(_impls[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setFacets(IDiamond.FacetCut[] memory _facets) external onlyGovernor {
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

    function updateAdmin(address _admin) external onlyGovernor {
        proxyAdmin = _admin;
    }

    function updateDiamondInit(address _diamondInit) external onlyGovernor {
        diamondInit = _diamondInit;
    }

    function updateInitData(bytes memory _initData) external onlyGovernor {
        initData = _initData;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function createDiamond(address _owner) external onlyOperator returns (address) {
        return address(
            new Diamond(facets, DiamondArgs({
            init: diamondInit,
            initCalldata: initData,
            owner: _owner
            }))
        );
    }

    function createTransparent(address _implementation) external onlyOperator returns (address) {
        return address(new TransparentUpgradeableProxy(_implementation, proxyAdmin, ""));
    }

    /* -------------------------------------------------------------------------- */
    /*                                   VIEW                                     */
    /* -------------------------------------------------------------------------- */

    function getDiamondArgs(address _owner) external view returns (DiamondArgs memory) {
        return DiamondArgs({init: diamondInit, initCalldata: initData, owner: _owner});
    }

    function getFacets() external view returns (IDiamond.FacetCut[] memory) {
        return facets;
    }

    function getImplementations() external view returns (address[] memory) {
        return implementations;
    }
}

