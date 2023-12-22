//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

interface IDeployer {
  event Deployed(address indexed sender, address indexed addr);

  function deploy(bytes memory _initCode, bytes32 _salt)
    external
    returns (address payable createdContract);
}

