// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IHook} from "./IHook.sol";
import {IERC20} from "./IERC20.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from "./draft-IERC20PermitUpgradeable.sol";

interface ICollateral is IERC20Upgradeable, IERC20PermitUpgradeable {
  event Deposit(
    address indexed funder,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );
  event DepositFeePercentChange(uint256 percent);
  event DepositHookChange(address hook);
  event Withdraw(
    address indexed funder,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );
  event WithdrawFeePercentChange(uint256 percent);
  event WithdrawHookChange(address hook);

  function deposit(
    address recipient,
    uint256 baseTokenAmount,
    bytes calldata data
  ) external returns (uint256 collateralMintAmount);

  function withdraw(
    address recipient,
    uint256 collateralAmount,
    bytes calldata data
  ) external returns (uint256 baseTokenAmountAfterFee);

  function setDepositFeePercent(uint256 depositFeePercent) external;

  function setWithdrawFeePercent(uint256 withdrawFeePercent) external;

  function setDepositHook(IHook hook) external;

  function setWithdrawHook(IHook hook) external;

  function getBaseToken() external view returns (IERC20);

  function getDepositFeePercent() external view returns (uint256);

  function getWithdrawFeePercent() external view returns (uint256);

  function getDepositHook() external view returns (IHook);

  function getWithdrawHook() external view returns (IHook);

  function getBaseTokenBalance() external view returns (uint256);

  function PERCENT_UNIT() external view returns (uint256);

  function FEE_LIMIT() external view returns (uint256);

  function SET_DEPOSIT_FEE_PERCENT_ROLE() external view returns (bytes32);

  function SET_WITHDRAW_FEE_PERCENT_ROLE() external view returns (bytes32);

  function SET_DEPOSIT_HOOK_ROLE() external view returns (bytes32);

  function SET_WITHDRAW_HOOK_ROLE() external view returns (bytes32);
}

