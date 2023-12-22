// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IOutletManagement.sol";

interface IOutletDescriptor {
  function outletURI(IOutletManagement outletManagement, uint256 outletId) external view returns (string memory);
}

