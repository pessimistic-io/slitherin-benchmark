// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;


import "./ITroveMarketplace.sol";

import "./BuyOrder.sol";

import "./IShiftSweeperEvents.sol";

interface IShiftSweeper is IShiftSweeperEvents {
  function buyOrdersMultiTokens(
    MultiTokenBuyOrder[] calldata _buyOrders,
    uint16 _inputSettingsBitFlag,
    address[] calldata _paymentTokens,
    uint256[] calldata _maxSpendIncFees
  ) external payable;
}

