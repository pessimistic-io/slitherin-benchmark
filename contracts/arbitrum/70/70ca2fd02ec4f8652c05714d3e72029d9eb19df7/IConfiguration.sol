// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IConfiguration {
  event DepositFeeUpdated(uint256 fee);
  event WithdrawFeeUpdated(uint256 fee);
  event ProtocolTreasuryUpdated(address indexed treasury);

  function depositFee() external view returns (uint256);

  function setDepositFee(uint256 fee) external;

  function withdrawFee() external view returns (uint256);

  function setWithdrawFee(uint256 fee) external;

  function protocolTreasury() external view returns (address);

  function setProtocolTreasury(address treasury) external;
}

