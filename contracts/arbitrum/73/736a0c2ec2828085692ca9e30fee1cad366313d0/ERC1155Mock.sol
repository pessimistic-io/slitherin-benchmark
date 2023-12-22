// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;
import "./ERC1155MintBurnMock.sol";


contract ERC1155Mock is ERC1155MintBurnMock {
  constructor() ERC1155MintBurnMock("TestERC1155", "") {}
}
