// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IDiamond} from "./IDiamond.sol";
import {DiamondArgs} from "./Diamond.sol";

interface ICreator {
    // GOV
    function setImplementations(address[] memory _impls) external;
    function setFacets(IDiamond.FacetCut[] memory _facets) external;

    // VIEW
    function getDiamondArgs(address _owner) external view returns (DiamondArgs memory);
    function getFacets() external view returns (IDiamond.FacetCut[] memory);
    function getImplementations() external view returns (address[] memory);

    // OPERATOR
    function createDiamond(address _owner) external returns (address);
    function createTransparent(address _implementation) external returns (address);
    function updateAdmin(address _admin) external;
    function updateDiamondInit(address _diamondInit) external;
    function updateInitData(bytes memory _initData) external;
}

