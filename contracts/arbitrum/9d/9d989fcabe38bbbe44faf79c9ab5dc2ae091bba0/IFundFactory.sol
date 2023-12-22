// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IFees.sol";

interface IFundFactory {

    struct FundInfo {
        uint256 id;

        bool hwm;
        // Lock Up Period for user since enter the Stake
        uint256 lockUpPeriod;
        uint256 indentPeriod;

        uint256 subscriptionFee;

        uint256 managementFeePeriod;
        uint256 managementFee;

        uint256 performanceFeePeriod;
        uint256 performanceFee;

        uint256 minStakingAmount;
        uint256 minWithdrawAmount;

        // Reporting period. Users can enter or leave ETF only at the start of every invest period
        uint256 investPeriod;
    }

    /// On fund created
    event FundCreated(address indexed manager,
        uint256 id,
        bool hwm,
        uint256 sf,
        uint256 pf,
        uint256 mf,
        uint256 period);

    event FeesChanged(address newFees);
    event TriggerChanged(address newTrigger);

    function newFund(FundInfo calldata fundInfo) external returns(uint256);

    function fees() external view returns (IFees);
    function feeder() external view returns (address);

}

