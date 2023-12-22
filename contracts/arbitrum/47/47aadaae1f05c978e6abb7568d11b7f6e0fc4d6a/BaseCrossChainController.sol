// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {Initializable} from "./Initializable.sol";
import {Rescuable} from "./Rescuable.sol";
import {IRescuable} from "./IRescuable.sol";
import {CrossChainReceiver} from "./CrossChainReceiver.sol";
import {CrossChainForwarder} from "./CrossChainForwarder.sol";
import {Errors} from "./Errors.sol";

import {IBaseCrossChainController} from "./IBaseCrossChainController.sol";

/**
 * @title BaseCrossChainController
 * @author BGD Labs
 * @notice Contract with the logic to manage sending and receiving messages cross chain.
 * @dev This contract is enabled to receive gas tokens as its the one responsible for bridge services payment.
        It should always be topped up, or no messages will be sent to other chains
 */
contract BaseCrossChainController is
  IBaseCrossChainController,
  Rescuable,
  CrossChainForwarder,
  CrossChainReceiver,
  Initializable
{
  constructor()
    CrossChainReceiver(new ConfirmationInput[](0), new ReceiverBridgeAdapterConfigInput[](0))
    CrossChainForwarder(new ForwarderBridgeAdapterConfigInput[](0), new address[](0))
  {}

  /// @dev child class should make a call of this method
  function _baseInitialize(
    address owner,
    address guardian,
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove
  ) internal initializer {
    _transferOwnership(owner);
    _updateGuardian(guardian);

    _configureReceiverBasics(
      receiverBridgeAdaptersToAllow,
      new ReceiverBridgeAdapterConfigInput[](0), // On first init, no bridges to disable
      initialRequiredConfirmations
    );

    _configureForwarderBasics(
      forwarderBridgeAdaptersToEnable,
      new BridgeAdapterToDisable[](0), // On first init, no bridges to disable
      sendersToApprove,
      new address[](0) // On first init, no senders to unauthorize
    );
  }

  /// @inheritdoc IRescuable
  function whoCanRescue() public view override(IRescuable, Rescuable) returns (address) {
    return owner();
  }

  /// @notice Enable contract to receive ETH/Native token
  receive() external payable {}
}

