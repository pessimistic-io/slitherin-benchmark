// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Milestone {
    uint256 priceOfPeg; ///@dev in terms of usdc
    uint256 usdcRaised; ///@dev usdc raised through usdc donations
    uint256 usdcOfPlsRaised; ///@dev amount of usdc raised through pls donations
    uint256 plsRaised; ///@dev number of pls tokens donated
    uint256 targetAmount; ///@dev total amount of usdc to raise
    uint256 totalUSDCRaised; ///@dev amount of usdc raised through both usdc and pls donations
    uint8 milestoneId;
    bool isCleared;
}

struct User {
    address user;
    uint256 plsDonations;
    uint256 usdcOfPlsDonations;
    uint256 usdcDonations;
}

