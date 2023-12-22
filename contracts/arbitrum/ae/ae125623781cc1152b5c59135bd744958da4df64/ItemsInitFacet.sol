// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IDiamondLoupe} from "./IDiamondLoupe.sol";
import {IERC173} from "./IERC173.sol";
import {UsingDiamondOwner} from "./UsingDiamondOwner.sol";
import "./LibDiamond.sol";
import {WithStorage} from "./ItemsLibAppStorage.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {UintUtils} from "./UintUtils.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

contract ItemsInitFacet is UsingDiamondOwner, WithStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    function init(address minter) external onlyOwner {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // maybe move to params
        _constants().contractUri = 'https://assets.kaijucards.io/metadata/items/itemsMetadata.json';
        _constants().baseUri = 'https://assets.kaijucards.io/metadata/items/';
        _constants().NUM_TRADES_ALLOWED_AFTER_TRANSMOG = 9999;
        _constants().nftActionPrice = 500000000000000;

        _token().equipmentTradingIsEnabled = false;
        _token().chestTradingIsEnabled = false;

        _access().rolesByAddress[minter].add(uint256(LibAccessControl.Roles.MINTER));


        //TODO add remaining interfaces
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
    }
}

