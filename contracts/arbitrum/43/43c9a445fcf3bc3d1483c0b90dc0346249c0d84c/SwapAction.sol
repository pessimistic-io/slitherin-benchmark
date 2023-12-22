// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import { Executable } from "./Executable.sol";
import { ServiceRegistry } from "./ServiceRegistry.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { IWETH } from "./IWETH.sol";
import { SwapData } from "./types_Common.sol";
import { UseStore, Write } from "./UseStore.sol";
import { Swap } from "./Swap.sol";
import { WETH, SWAP } from "./types_Common.sol";
import { OperationStorage } from "./OperationStorage.sol";

/**
 * @title SwapAction Action contract
 * @notice Call the deployed Swap contract which handles swap execution
 */
contract SwapAction is Executable, UseStore {
  using SafeERC20 for IERC20;
  using Write for OperationStorage;

  constructor(address _registry) UseStore(_registry) {}

  /**
   * @dev The swap contract is pre-configured to use a specific exchange (EG 1inch)
   * @param data Encoded calldata that conforms to the SwapData struct
   */
  function execute(bytes calldata data, uint8[] memory) external payable override {
    address swapAddress = registry.getRegisteredService(SWAP);

    SwapData memory swap = parseInputs(data);

    IERC20(swap.fromAsset).safeApprove(swapAddress, swap.amount);

    uint256 received = Swap(swapAddress).swapTokens(swap);

    store().write(bytes32(received));
  }

  function parseInputs(bytes memory _callData) public pure returns (SwapData memory params) {
    return abi.decode(_callData, (SwapData));
  }
}

