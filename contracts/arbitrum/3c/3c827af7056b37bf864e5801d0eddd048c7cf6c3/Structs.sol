// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/******* STRUCTS *******/

struct USDCMilestone {
    uint256 pegAllocation;
    uint256 priceOfPeg;
    uint256 pegDistributed;
    uint256 USDCTarget; ///@dev total usdc to raise through usdc donations
    uint256 milestoneUSDCTarget; ///@dev total USDC to raise for milestone
    uint256 USDCRaised;
    bool isCleared;
}
struct PLSMilestone {
    uint256 pegAllocation;
    uint256 priceOfPeg;
    uint256 pegDistributed;
    uint256 plsRaised;
    uint256 USDCOfPlsTarget; ///@dev total usdc to raise through pls donations
    uint256 milestoneUSDCTarget; ///@dev total USDC to raise for milestone
    uint256 USDCOfPlsRaised;
    bool isCleared;
}
struct User {
    address user;
    uint256 PLSDonations;
    uint256 USDCDonations;
    uint256 pegAllocation;
}

