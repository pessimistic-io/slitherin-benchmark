// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ITokenPriceCalculator {

    event SetPricePerMint(uint256 _price);

    function pricePerMint() external view returns(uint256);

    function getTokensEligible(uint256 _amountPaid) external view returns (uint256);

    function setPricePerMint(uint256 _price) external;
}
