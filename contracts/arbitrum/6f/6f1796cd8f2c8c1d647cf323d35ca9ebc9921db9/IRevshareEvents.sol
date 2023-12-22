//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

interface IRevshareEvents {

    event ProposedDiscountChange(uint32 oldRate, uint32 newRate, uint allowedAfterTime);
    event DiscountChanged(uint32 newRate);

    event ProposedBpsChange(uint32 oldStdRate, uint32 newStdRate, uint32 oldMinRate, uint32 newMinRate, uint allowedAfterTime);
    event BpsChanged(uint32 stdRate, uint32 minRate);

    event ProposedVolumeGoal(uint oldVolume, uint newVolume, uint allowedAfterTime);
    event AppliedVolumeGoal(uint newVolume);

    event ProposedMintRateChange(uint16 minThreshold, uint16 maxThreshold, uint percentage, uint allowedAfterTime);
    event MintRateChange(uint16 minThreshold, uint16 maxThreshold, uint percentage);
    
    event ProposedFeeToken(address indexed token, address indexed priceFeed, bool removal, uint allowedAfterTime);
    event FeeTokenAdded(address indexed token, address indexed priceFeed);
    event FeeTokenRemoved(address indexed token);
    event  DXBLRedeemed(address holder, uint dxblAmount, address rewardToken, uint rewardAmount);
}
