// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import { Executable } from "./Executable.sol";
import { ServiceRegistry } from "./ServiceRegistry.sol";
import { IVault } from "./IVault.sol";
import { IERC3156FlashBorrower } from "./IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "./IERC3156FlashLender.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";
import { FlashloanData, FlashloanProvider } from "./types_Common.sol";
import { OPERATION_EXECUTOR, DAI, CHAINLOG_VIEWER } from "./types_Common.sol";
import { MCD_FLASH } from "./Maker.sol";
import { BALANCER_VAULT } from "./Balancer.sol";
import { ChainLogView } from "./ChainLogView.sol";
import { ProxyPermission } from "./ProxyPermission.sol";
import { IERC20 } from "./SafeERC20.sol";

/**
 * @title TakeFlashloan Action contract
 * @notice Executes a sequence of Actions after flashloaning funds
 */
contract TakeFlashloan is Executable, ProxyPermission {
  address internal immutable dai;
  ServiceRegistry private immutable registry;

  constructor(
    ServiceRegistry _registry,
    address _dai,
    address _dsGuardFactory
  ) ProxyPermission(_dsGuardFactory) {
    registry = _registry;
    dai = _dai;
  }

  /**
   * @dev When the Flashloan lender calls back the Operation Executor we may need to re-establish the calling context.
   * @dev The isProxyFlashloan flag is used to give the Operation Executor temporary authority to call the execute method on a user"s proxy. Refers to any proxy wallet (DSProxy or DPMProxy at time of writing)
   * @dev isDPMProxy flag switches between regular DSPRoxy and DPMProxy
   * @param data Encoded calldata that conforms to the FlashloanData struct
   */
  function execute(bytes calldata data, uint8[] memory) external payable override {
    FlashloanData memory flData = parseInputs(data);
    address operationExecutorAddress = registry.getRegisteredService(OPERATION_EXECUTOR);

    if (flData.isProxyFlashloan) {
      givePermission(flData.isDPMProxy, operationExecutorAddress);
    }

    if (flData.provider == FlashloanProvider.DssFlash) {
      ChainLogView chainlogView = ChainLogView(registry.getRegisteredService(CHAINLOG_VIEWER));

      IERC3156FlashLender(chainlogView.getServiceAddress(MCD_FLASH)).flashLoan(
        IERC3156FlashBorrower(operationExecutorAddress),
        dai,
        flData.amount,
        abi.encode(flData, address(this))
      );
    }

    if (flData.provider == FlashloanProvider.Balancer) {
      IERC20[] memory tokens = new IERC20[](1);
      uint256[] memory amounts = new uint256[](1);

      tokens[0] = IERC20(flData.asset);
      amounts[0] = flData.amount;

      IVault(registry.getRegisteredService(BALANCER_VAULT)).flashLoan(
        IFlashLoanRecipient(operationExecutorAddress),
        tokens,
        amounts,
        abi.encode(flData, address(this))
      );
    }

    if (flData.isProxyFlashloan) {
      removePermission(flData.isDPMProxy, operationExecutorAddress);
    }
  }

  function parseInputs(bytes memory _callData) public pure returns (FlashloanData memory params) {
    return abi.decode(_callData, (FlashloanData));
  }
}

