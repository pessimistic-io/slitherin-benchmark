
// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;
import "./ImpossiblePair.sol";

contract TestPairDeployer {
  constructor() {}

  function testPair() external pure returns (bytes32) {
    bytes memory bytecode = type(ImpossiblePair).creationCode;
    return keccak256(bytecode);
  }
}
