// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import "./TakeAndRunSwap.sol";
import "./TakeRunSwapAndTransfer.sol";
import "./TakeRunSwapsAndTransferMany.sol";
import "./TakeManyRunSwapAndTransferMany.sol";
import "./TakeManyRunSwapsAndTransferMany.sol";
import "./CollectableWithGovernor.sol";
import "./RevokableWithGovernor.sol";
import "./GetBalances.sol";
import "./TokenPermit.sol";
import "./PayableMulticall.sol";

/**
 * @notice This contract implements all swap extensions, so it can be used by EOAs or other contracts that do not have the extensions
 */
contract SwapProxy is
  TakeAndRunSwap,
  TakeRunSwapAndTransfer,
  TakeRunSwapsAndTransferMany,
  TakeManyRunSwapAndTransferMany,
  TakeManyRunSwapsAndTransferMany,
  CollectableWithGovernor,
  RevokableWithGovernor,
  GetBalances,
  TokenPermit,
  PayableMulticall
{
  constructor(address _swapperRegistry, address _governor) SwapAdapter(_swapperRegistry) Governable(_governor) {}
}

