// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;
pragma abicoder v2;

interface ICurveAddressProvider {
  function get_registry() external view returns (address);

  function get_address(uint256 id) external view returns (address);
}

