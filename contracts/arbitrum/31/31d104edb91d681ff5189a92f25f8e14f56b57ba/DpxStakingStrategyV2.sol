//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BasicStakingStrategy} from "./BasicStakingStrategy.sol";

/// @title Stakes DPX into the DPX single sided farm on Arbitrum
contract DpxStakingStrategyV2 is BasicStakingStrategy {
    constructor(address _ssov, address _rewardToken)
        BasicStakingStrategy(_ssov, _rewardToken)
    {}
}

