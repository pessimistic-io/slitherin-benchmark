// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StdUtils} from "./StdUtils.sol";

abstract contract Create2Utils is StdUtils {
  address private constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

  function _create2Deploy(bytes32 salt, bytes memory bytecode) internal returns (address) {
    if (isContractDeployed(CREATE2_FACTORY) == false) {
      revert('MISSING CREATE2_FACTORY');
    }
    address computed = computeCreate2Address(salt, hashInitCode(bytecode));

    if (isContractDeployed(computed)) {
      return computed;
    } else {
      bytes memory creationBytecode = abi.encodePacked(salt, bytecode);
      bytes memory returnData;
      (, returnData) = CREATE2_FACTORY.call(creationBytecode);
      address deployedAt = address(uint160(bytes20(returnData)));
      require(deployedAt == computed, 'failure at create2 address derivation');
      return deployedAt;
    }
  }

  function isContractDeployed(address _addr) internal view returns (bool isContract) {
    return (_addr.code.length > 0);
  }
}

