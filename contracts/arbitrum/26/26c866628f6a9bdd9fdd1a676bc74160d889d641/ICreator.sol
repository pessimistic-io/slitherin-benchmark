// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IDiamond} from "./IDiamond.sol";
import {DiamondArgs} from "./BeaconDiamond.sol";

interface ICreator {
    // GOV
    function setImplementations(address[] memory _impls) external;
    function setFacets(IDiamond.BeaconCut[] memory _facets) external;
    function updateDiamondInit(address _diamondInit) external;
    function updateInitData(bytes memory _initData) external;

    // VIEW
    function getFacets() external view returns (IDiamond.BeaconCut[] memory);
    function getImplementations() external view returns (address[] memory);
    function getBeacons() external view returns (address[] memory);

    // OPERATOR
    function createDiamond(address _owner) external returns (address);
    function createBeacon(address _beacon) external returns (address);
}

