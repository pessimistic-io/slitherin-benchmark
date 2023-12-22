// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;
import "./ERC1155MintBurnPackedBalanceMock.sol";


contract ERC1155PackedBalanceMock is ERC1155MintBurnPackedBalanceMock {
  constructor() ERC1155MintBurnPackedBalanceMock("TestERC1155", "") {}
}
