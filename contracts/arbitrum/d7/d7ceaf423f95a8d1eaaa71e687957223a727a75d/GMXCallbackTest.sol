// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWNT } from "./IWNT.sol";
import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IOrderCallbackReceiver } from "./IOrderCallbackReceiver.sol";

interface IGMXTest {
  function postDeposit() payable external;
  function viewAlp() external view returns (AddLiquidityParams memory);

}
  struct AddLiquidityParams {
    address payable user;
    // Amount of tokenA to add liquidity
    uint256 tokenAAmt;
    // Amount of tokenB to add liquidity
    uint256 tokenBAmt;
    // Slippage tolerance for adding liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // Execution fee sent to GMX for adding liquidity
    uint256 executionFee;
    uint256 callbackGaslimit;
    bool unwrap;
  }

contract GMXCallbackTest is IDepositCallbackReceiver {

  address public WNT = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;



  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXTest public vault;
  bytes32 _depositKey;
  address handler;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize callback contract with associated vault address
    * @param _vault Address of vault contract
  */
  constructor (address _vault) {
    vault = IGMXTest(_vault);
  }


  /**
    * @dev Process vault after successful deposit execution from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IDeposit.Props
    * @param eventData IEvent.Props
  */
  function afterDepositExecution(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external {

    _depositKey = depositKey;
    handler = msg.sender;

    vault.postDeposit();

    // AddLiquidityParams memory _alp = vault.viewAlp();

    // IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    // (bool success, ) = payable(_alp.user).call{value: address(this).balance}("");
    // require(success, "Transfer failed.");
  }

  function afterDepositCancellation(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external {

    _depositKey = depositKey;
    handler = msg.sender;
  }

  receive() external payable {
    // require(msg.sender == WNT, "msg.sender != WNT");
  }

}

