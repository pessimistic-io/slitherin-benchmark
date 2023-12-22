// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "./QuotaLib.sol";

struct Fee {
    address to;
    uint160 amount;
}

interface IFeePolicy {
    function getFees(Quota calldata quota, uint160 chargeAmount, address chargeCaller)
        external
        view
        returns (Fee[] memory fees);
}

