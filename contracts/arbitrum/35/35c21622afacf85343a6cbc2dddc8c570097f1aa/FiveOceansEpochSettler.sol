// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./FiveOceans.sol";

contract FiveOceansEpochSettler {
    FiveOceans public immutable fiveOceans;

    constructor(address fiveOceans_) {
        fiveOceans = FiveOceans(fiveOceans_);
    }

    function settle() public {
        fiveOceans.settleEpoch(fiveOceans.getCurrentEpochId());
    }
}
