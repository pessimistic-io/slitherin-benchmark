// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface ID4ARoyaltySplitterFactory {
  function createD4ARoyaltySplitter(address setting, address addr1, uint256 w1, address addr2, uint256 w2) external returns(address);
}

