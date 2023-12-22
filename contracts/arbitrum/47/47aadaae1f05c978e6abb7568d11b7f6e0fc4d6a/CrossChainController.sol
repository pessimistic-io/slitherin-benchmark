// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {ICrossChainController} from "./ICrossChainController.sol";
import {BaseCrossChainController} from "./BaseCrossChainController.sol";

/**
 * @title CrossChainController
 * @author BGD Labs
 * @notice CrossChainController contract adopted for usage on the chain where Governance deployed (mainnet in our case)
 */
contract CrossChainController is ICrossChainController, BaseCrossChainController {
  /// @inheritdoc ICrossChainController
  function initialize(
    address owner,
    address guardian,
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove
  ) external initializer {
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
}

