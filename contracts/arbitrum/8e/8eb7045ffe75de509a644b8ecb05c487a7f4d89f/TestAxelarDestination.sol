//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AxelarExecutable } from "./AxelarExecutable.sol";

contract TestAxelarDestination is AxelarExecutable {
  
  event CrossChainInvoke(
                         string sourceChain,
                         string sourceAddress,
                         address rewardAddress,
                         uint rewardValue
                         );
  
  constructor(address gateway_) AxelarExecutable(gateway_) {
  }
  
  function _execute(
                    string calldata sourceChain_,
                    string calldata sourceAddress_,
                    bytes calldata payload_) internal override {
    (address rewardAddress, uint rewardValue) = abi.decode(payload_, (address, uint));
    emit CrossChainInvoke(sourceChain_, sourceAddress_, rewardAddress, rewardValue);
  }
}
