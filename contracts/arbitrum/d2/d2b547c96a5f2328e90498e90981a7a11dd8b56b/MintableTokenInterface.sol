// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { IERC20 } from "./IERC20.sol";

interface MintableTokenInterface is IERC20 {
  function isMinter(address _minter) external view returns (bool);

  function setMinter(address minter, bool allow) external;

  function mint(address to, uint256 amount) external;

  function burn(address to, uint256 amount) external;
}

