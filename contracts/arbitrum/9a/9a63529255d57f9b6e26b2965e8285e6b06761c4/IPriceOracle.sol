// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPriceOracle {
    function latestAnswer() external view returns (uint256);

    function getUnderlyingPrice() external view returns (uint256);

    function getCollateralPrice() external view returns (uint256);

    function getPrice(
        address token,
        bool maximise,
        bool includeAmmPrice,
        bool useSwapPricing
    ) external view returns (uint256);
}

