// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IMarketsEvents {
    event CreateMarket(uint256 indexed marketId, uint256 timestamp);
    event UpdateMarketIdentifier(uint256 indexed marketId, string oldIdentifier, string newIdentifier);
    event UpdateMarketActive(uint256 indexed marketId, bool oldStatus, bool newStatus);
    event UpdateMarketMuonPriceFeedId(uint256 indexed marketId, bytes32 oldMuonPriceFeedId, bytes32 newMuonPriceFeedId);
    event UpdateMarketFundingRateId(uint256 indexed marketId, bytes32 oldFundingRateId, bytes32 newFundingRateId);
    event UpdateProtocolFee(uint256 indexed marketId, uint256 oldProtocolFee, uint256 newProtocolFee);
}

