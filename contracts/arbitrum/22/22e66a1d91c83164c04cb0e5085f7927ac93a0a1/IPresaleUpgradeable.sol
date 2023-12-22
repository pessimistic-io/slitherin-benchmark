// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPresaleUpgradeable {
    event SetMinPurchase(uint256 min);
    event SetPrice(uint256 tokenPrice);
    event SetBonus(uint256 bonusPercentage);
    event SetBeneficiary(address beneficiary);
    event Released(address recipient, uint256 amount);
    event TokenSaleAdded(uint256 amount);
    event TokenBonusAdded(uint256 amount);

    event TokensPurchased(
        address indexed purchaser,
        address indexed beneficiary,
        address paymentToken,
        uint256 usdAmount,
        uint256 tokensAmount
    );

    error InsufficientBalance();
    error LengthMisMatch();
}

