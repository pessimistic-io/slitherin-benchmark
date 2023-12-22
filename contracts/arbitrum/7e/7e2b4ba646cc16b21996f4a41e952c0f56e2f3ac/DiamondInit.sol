// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import {IDiamondLoupe} from "./IDiamondLoupe.sol";
import {IDiamondCut} from "./IDiamondCut.sol";
import {IERC165} from "./IERC165.sol";

import {LibDiamond} from "./LibDiamond.sol";

import {BaseConnextFacet} from "./BaseConnextFacet.sol";

import {IProposedOwnable} from "./IProposedOwnable.sol";
import {IConnectorManager} from "./IConnectorManager.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init funciton if you need to.

contract DiamondInit is BaseConnextFacet {
  // You can add parameters to this function in order to pass in
  // data to set your own state variables
  function init(
    uint32 _domain,
    address _xAppConnectionManager,
    uint256 _acceptanceDelay
  ) external {
    // adding ERC165 data
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
    ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
    ds.supportedInterfaces[type(IProposedOwnable).interfaceId] = true;
    ds.acceptanceDelay = _acceptanceDelay;

    // add your own state variables
    // EIP-2535 specifies that the `diamondCut` function takes two optional
    // arguments: address _init and bytes calldata _calldata
    // These arguments are used to execute an arbitrary function using delegatecall
    // in order to set state variables in the diamond during deployment or an upgrade
    // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface

    if (!s.initialized) {
      // ensure this is the owner
      LibDiamond.enforceIsContractOwner();

      s.initialized = true;

      // __ReentrancyGuard_init_unchained
      s._status = _NOT_ENTERED;

      // Connext
      s.domain = _domain;
      s.LIQUIDITY_FEE_NUMERATOR = 9995;
      s.maxRoutersPerTransfer = 5;
      s.xAppConnectionManager = IConnectorManager(_xAppConnectionManager);
    }
  }
}

