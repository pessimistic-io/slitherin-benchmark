//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import { AxelarExecutable } from "./AxelarExecutable.sol";
import { Ownable } from "./Ownable.sol";
import { IAxelarGasService } from "./IAxelarGasService.sol";

contract MessageRelayer is AxelarExecutable, Ownable {
  IAxelarGasService public immutable gasReceiver;

  constructor(address _gateway, address _gasReceiver, address _owner) AxelarExecutable(_gateway) {
    gasReceiver = IAxelarGasService(_gasReceiver);
    _transferOwnership(_owner);
  }

  function sendMessage(
    string memory _destinationChain,
    string memory _destinationAddress,
    bytes memory _payload
  ) public payable onlyOwner {
    if (msg.value > 0) {
      gasReceiver.payNativeGasForContractCall{ value: msg.value }(
        address(this), _destinationChain, _destinationAddress, _payload, msg.sender
      );
    }
    gateway.callContract(_destinationChain, _destinationAddress, _payload);
  }
}

