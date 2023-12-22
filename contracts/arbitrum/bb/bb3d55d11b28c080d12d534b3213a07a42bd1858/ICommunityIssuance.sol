// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ICommunityIssuance {
    // --- Events ---

    event TotalPREONIssuedUpdated(uint256 _totalPREONIssued);

    // --- Functions ---

    function issuePREON() external returns (uint256);

    function sendPREON(address _account, uint256 _PREONamount) external;

    function addFundToStabilityPool(uint256 _assignedSupply) external;

    function addFundToStabilityPoolFrom(
        uint256 _assignedSupply,
        address _spender
    ) external;

    function setWeeklyPreonDistribution(uint256 _weeklyReward) external;
}

