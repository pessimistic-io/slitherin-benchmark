// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

interface IRenderer {
  function render(uint tokenId, uint hp, uint shootTimes) external view returns(string memory);
}
