// SPDX-License-Identifier: MIT
/**
 * Customized version of DiamondInit.sol
 *
 * Vendored on November 16, 2021 from:
 * https://github.com/mudgen/diamond-3-hardhat/blob/7feb995/contracts/upgradeInitializers/DiamondInit.sol
 */
pragma solidity ^0.8.17;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

// It is expected that this contract is customized in order to deploy a diamond with data
// from a deployment script. The init function is used to initialize state variables
// of the diamond. Add parameters to the init function if you need to.

// Interface imports
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IDiamondCut } from "./IDiamondCut.sol";
import { IERC173 } from "./IERC173.sol";
import { IERC165 } from "./IERC165.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC721Metadata } from "./IERC721Metadata.sol";
import { IERC721Enumerable } from "./IERC721Enumerable.sol";

// Inherited storage
import { ERC721MetadataStorage } from "./ERC721MetadataStorage.sol";
import { ERC165Storage } from "./ERC165Storage.sol";

// Library imports
import { LibDiamond } from "./LibDiamond.sol";
import { WithModifiers } from "./LibStorage.sol";

// Errors
import { Errors } from "./Errors.sol";

// Type imports
struct InitArgs {
    string landMetadataExtension;
    string landContractURI;
    string landName;
    string landSymbol;
    string landMetadataBaseURI;
    address guardian;
    address magic;
}

contract WLInit is WithModifiers {
    using ERC721MetadataStorage for ERC721MetadataStorage.Layout;
    using ERC165Storage for ERC165Storage.Layout;

    address private immutable _facetAddress = address(this);

    event Initialized();

    // You can add parameters to this function in order to pass in
    // data to set initialize state variables
    function init(InitArgs memory initArgs) external onlyOwner {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ERC165Storage.layout().supportedInterfaces[type(IERC165).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IERC173).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IERC721).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IERC721Metadata).interfaceId] = true;
        ERC165Storage.layout().supportedInterfaces[type(IERC721Enumerable).interfaceId] = true;

        // Setup the ERC721 metadata
        ERC721MetadataStorage.layout().name = initArgs.landName;
        ERC721MetadataStorage.layout().symbol = initArgs.landSymbol;
        ERC721MetadataStorage.layout().baseURI = initArgs.landMetadataBaseURI;

        ws().diamondAddress = address(this);

        ws().landContractURI = initArgs.landContractURI;
        ws().landMetadataExtension = initArgs.landMetadataExtension;
        ws().guardian[initArgs.guardian] = true;
        ws().magic = initArgs.magic;
        ws().paused = true;

        // Self remove init facet
        LibDiamond.removeFunction(ds, _facetAddress, WLInit.init.selector);
    }
}

