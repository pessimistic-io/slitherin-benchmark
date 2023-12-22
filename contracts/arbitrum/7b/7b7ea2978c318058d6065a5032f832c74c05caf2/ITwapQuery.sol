// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ITwapQuery {
  function getOrderMetrics () external view returns (uint256 pStartedOn, uint256 pDeadline, uint256 pSpent, uint256 pFilled, uint256 pTradeSize, uint256 pChunkSize, uint256 pPriceLimit, address srcToken, address dstToken, uint8 pState, bool pAlive);
}
