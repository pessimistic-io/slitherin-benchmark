// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { PerpStorage } from "./PerpStorage.sol";

interface ITradeHelper {
  /**
   * Errors
   */
  error ITradeHelper_TradingFeeCannotBeCovered();
  error ITradeHelper_BorrowingFeeCannotBeCovered();
  error ITradeHelper_FundingFeeCannotBeCovered();
  error ITradeHelper_UnrealizedPnlCannotBeCovered();
  error ITradeHelper_InvalidAddress();

  /**
   * Functions
   */
  function reloadConfig() external;

  function updateBorrowingRate(uint8 _assetClassIndex) external;

  function updateFundingRate(uint256 _marketIndex) external;

  function settleAllFees(
    bytes32 _positionId,
    PerpStorage.Position memory position,
    uint256 _absSizeDelta,
    uint32 _positionFeeBPS,
    uint8 _assetClassIndex
  ) external;
}

