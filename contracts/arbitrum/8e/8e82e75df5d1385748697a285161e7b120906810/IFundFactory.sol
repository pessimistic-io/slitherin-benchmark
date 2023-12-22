// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IFees.sol";

interface IFundFactory {

    struct FundInfo {
        uint256 id;
        bool hwm;
        uint256 subscriptionFee;
        uint256 managementFee;
        uint256 performanceFee;
        uint256 investPeriod;
        uint256 indent;
        bytes whitelistMask;
        uint256 serviceMask;
    }

    /// On fund created
    event FundCreated(address indexed manager,
        uint256 id,
        bool hwm,
        uint256 sf,
        uint256 pf,
        uint256 mf,
        uint256 period,
        bytes whitelistMask,
        uint256 serviceMask
    );

    event FeesChanged(address newFees);
    event TriggerChanged(address newTrigger);

    function newFund(FundInfo calldata fundInfo) external returns (uint256);
}

