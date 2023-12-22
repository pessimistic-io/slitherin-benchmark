// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface IOpenTermLoan {
    function borrowerCommitment() external;
    function withdraw() external;
    function repayPrincipal(uint256) external;
    function repayInterests() external;
    function getDebt() external view returns 
    (
        uint256 interestDebtAmount, 
        uint256 grossDebtAmount, 
        uint256 principalDebtAmount, 
        uint256 interestOwed, 
        uint256 applicableLateFee, 
        uint256 netDebtAmount, 
        uint256 daysSinceFunding, 
        uint256 currentBillingCycle,
        uint256 minPaymentAmount,
        uint256 maxPaymentAmount
    );
    function principalToken() external view returns(address);
    
}
