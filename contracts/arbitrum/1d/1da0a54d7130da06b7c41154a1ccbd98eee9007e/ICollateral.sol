// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IHook.sol";
import "./IERC20.sol";
import "./IERC20Upgradeable.sol";
import "./draft-IERC20PermitUpgradeable.sol";

interface ICollateral is IERC20Upgradeable, IERC20PermitUpgradeable {
  event Deposit(
    address indexed depositor,
    uint256 amountAfterFee,
    uint256 fee
  );

  event Withdraw(
    address indexed withdrawer,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );

  event DepositFeeChange(uint256 fee);

  event WithdrawFeeChange(uint256 fee);

  event DepositHookChange(address hook);

  event WithdrawHookChange(address hook);

  function deposit(address recipient, uint256 baseTokenAmount)
    external
    returns (uint256 collateralMintAmount);

  function withdraw(address recipient, uint256 collateralAmount)
    external
    returns (uint256 baseTokenAmountAfterFee);

  function setDepositFee(uint256 depositFee) external;

  function setWithdrawFee(uint256 withdrawFee) external;

  function setDepositHook(IHook hook) external;

  function setWithdrawHook(IHook hook) external;

  function getBaseToken() external view returns (IERC20);

  function getDepositFee() external view returns (uint256);

  function getWithdrawFee() external view returns (uint256);

  function getDepositHook() external view returns (IHook);

  function getWithdrawHook() external view returns (IHook);

  function getBaseTokenBalance() external view returns (uint256);

  function PERCENT_DENOMINATOR() external view returns (uint256);

  function FEE_LIMIT() external view returns (uint256);

  function SET_DEPOSIT_FEE_ROLE() external view returns (bytes32);

  function SET_WITHDRAW_FEE_ROLE() external view returns (bytes32);

  function SET_DEPOSIT_HOOK_ROLE() external view returns (bytes32);

  function SET_WITHDRAW_HOOK_ROLE() external view returns (bytes32);
}

