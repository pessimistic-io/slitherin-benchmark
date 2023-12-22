// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

interface ITreasuryCaller {
  event TreasuryChange(address treasury);

  function setTreasury(address treasury) external;

  function getTreasury() external view returns (address);
}

