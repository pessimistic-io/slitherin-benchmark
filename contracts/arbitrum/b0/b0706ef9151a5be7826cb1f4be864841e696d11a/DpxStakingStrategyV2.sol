//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BasicStakingStrategy} from "./BasicStakingStrategy.sol";

contract DpxStakingStrategyV2 is BasicStakingStrategy {
    constructor(address _ssov, address _rewardToken)
        BasicStakingStrategy(_ssov, _rewardToken)
    {}
}

