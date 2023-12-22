// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IHook.sol";

interface IDepositHook is IHook {
  event DepositsAllowedChange(bool allowed);

  function setDepositsAllowed(bool allowed) external;

  function depositsAllowed() external view returns (bool);

  function SET_COLLATERAL_ROLE() external view returns (bytes32);

  function SET_DEPOSIT_RECORD_ROLE() external view returns (bytes32);

  function SET_DEPOSITS_ALLOWED_ROLE() external view returns (bytes32);

  function SET_TREASURY_ROLE() external view returns (bytes32);

  function SET_TOKEN_SENDER_ROLE() external view returns (bytes32);
}

