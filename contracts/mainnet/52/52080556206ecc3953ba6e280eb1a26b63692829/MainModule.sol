// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./SignatureValidator.sol";

import "./Implementation.sol";
import "./ModuleAuthFixed.sol";
import "./ModuleHooks.sol";
import "./ModuleCalls.sol";
import "./ModuleUpdate.sol";
import "./ModuleCreator.sol";

import "./IERC1155Receiver.sol";
import "./IERC721Receiver.sol";

import "./IERC1271Wallet.sol";


/**
 * @notice Contains the core functionality arcadeum wallets will inherit.
 * @dev If using a new main module, developpers must ensure that all inherited
 *      contracts by the mainmodule don't conflict and are accounted for to be
 *      supported by the supportsInterface method.
 */
contract MainModule is
  ModuleAuthFixed,
  ModuleCalls,
  ModuleUpdate,
  ModuleHooks,
  ModuleCreator
{
  constructor(
    address _factory
  ) public ModuleAuthFixed(
    _factory
  ) { }

  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceID The interface identifier, as specified in ERC-165
   * @return `true` if the contract implements `_interfaceID`
   */
  function supportsInterface(
    bytes4 _interfaceID
  ) public override(
    ModuleAuth,
    ModuleCalls,
    ModuleUpdate,
    ModuleHooks,
    ModuleCreator
  ) pure returns (bool) {
    return super.supportsInterface(_interfaceID);
  }
}

