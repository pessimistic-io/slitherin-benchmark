// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OfferItem, ConsiderationItem, SpentItem} from "./ConsiderationStructs.sol";

struct CampaignParams {
    uint32 startTime;
    uint32 endTime;
    uint32 maxCampaignRedemptions;
    address manager;
    address signer;
    CampaignRequirements[] requirements;
}

struct CampaignRequirements {
    OfferItem[] offer;
    ConsiderationItem[] consideration;
    TraitRedemption[] traitRedemptions;
}

struct TraitRedemption {
    uint8 substandard;
    address token;
    bytes32 traitKey;
    bytes32 traitValue;
    bytes32 substandardValue;
}

