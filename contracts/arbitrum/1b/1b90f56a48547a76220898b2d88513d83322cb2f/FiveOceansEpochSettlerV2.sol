// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./FiveOceans.sol";

contract FiveOceansEpochSettlerV2 {
    FiveOceans public immutable fiveOceans;

    constructor(address fiveOceans_) {
        fiveOceans = FiveOceans(fiveOceans_);
    }

    function settlePreviousEpoch() public {
        fiveOceans.settleEpoch(fiveOceans.getCurrentEpochId() - 1);
    }

}
