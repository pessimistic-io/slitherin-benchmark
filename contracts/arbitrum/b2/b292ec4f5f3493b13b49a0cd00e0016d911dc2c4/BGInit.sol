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

// Inherited storage
import { ERC165Storage } from "./ERC165Storage.sol";

// Library imports
import { LibDiamond } from "./LibDiamond.sol";
import { WithModifiers } from "./LibStorage.sol";

// Errors
import { Errors } from "./Errors.sol";

// Type imports
struct InitArgs {
    uint256 gFlyPerCredit;
    uint256 treasuresPerCredit;
    address gFlyReceiver;
    address treasureReceiver;
    address gFLY;
    address treasures;
    address guardian;
    uint256[] creditTypes;
}

contract BGInit is WithModifiers {
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

        gs().diamondAddress = address(this);

        gs().gFlyPerCredit = initArgs.gFlyPerCredit;
        gs().treasuresPerCredit = initArgs.treasuresPerCredit;
        gs().gFlyReceiver = initArgs.gFlyReceiver;
        gs().treasureReceiver = initArgs.treasureReceiver;
        gs().gFLY = initArgs.gFLY;
        gs().treasures = initArgs.treasures;
        gs().guardian[initArgs.guardian] = true;
        gs().paused = true;

        for (uint256 i = 0; i < initArgs.creditTypes.length; i++) {
            gs().creditTypes[initArgs.creditTypes[i]] = true;
        }

        // Self remove init facet
        LibDiamond.removeFunction(ds, _facetAddress, BGInit.init.selector);
    }
}

