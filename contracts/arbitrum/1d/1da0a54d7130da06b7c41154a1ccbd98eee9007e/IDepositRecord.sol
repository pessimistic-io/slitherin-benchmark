// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.7;

interface IDepositRecord {
  event GlobalNetDepositCapChange(uint256 cap);

  event UserDepositCapChange(uint256 cap);

  function recordDeposit(address sender, uint256 amount) external;

  function recordWithdrawal(uint256 amount) external;

  function setGlobalNetDepositCap(uint256 globalNetDepositCap) external;

  function setUserDepositCap(uint256 userDepositCap) external;

  function getGlobalNetDepositCap() external view returns (uint256);

  function getGlobalNetDepositAmount() external view returns (uint256);

  function getUserDepositCap() external view returns (uint256);

  function getUserDepositAmount(address account)
    external
    view
    returns (uint256);

  function SET_GLOBAL_NET_DEPOSIT_CAP_ROLE() external view returns (bytes32);

  function SET_USER_DEPOSIT_CAP_ROLE() external view returns (bytes32);

  function SET_ALLOWED_MSG_SENDERS_ROLE() external view returns (bytes32);

  function SET_ACCOUNT_LIST_ROLE() external view returns (bytes32);
}

