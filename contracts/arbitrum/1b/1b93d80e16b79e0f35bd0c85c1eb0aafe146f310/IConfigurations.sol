// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @author DeFragDAO
interface IConfigurations {
    function maxBorrow() external view returns (uint256);

    function impliedVolatility() external view returns (uint256);

    function expirationCycle() external view returns (uint256);

    function riskFreeRate() external view returns (int256);

    function pricingOracle() external view returns (address);

    function minBorrow() external view returns (uint256);

    function liquidationThreshold() external view returns (uint256);

    function premiumFeeProration() external view returns (uint256);

    function minimumPremiumFee() external view returns (uint256);

    function setMaxBorrow(uint256 _maxBorrow) external;

    function setImpliedVolitility(uint256 _impliedVolatility) external;

    function setExpirationCycle(uint256 _expirationCycle) external;

    function setRiskFreeRate(int256 _riskFreeRate) external;

    function setPricingOracle(address _pricingOracle) external;

    function setMinBorrow(uint256 _minBorrow) external;

    function setLiquidationThreshold(uint256 _liquidationThreshold) external;

    function setPremiumFeeProration(uint256 _premiumFeeProration) external;

    function setMinimumPremiumFee(uint256 _minimumPremiumFee) external;

    function getConstants()
        external
        view
        returns (
            uint256 maxBorrow,
            uint256 impliedVolatility,
            uint256 expirationCycle,
            int256 riskFreeRate,
            address pricingOracle,
            uint256 minBorrow,
            uint256 liquidationThreshold,
            uint256 premiumFeeProration,
            uint256 minimumPremiumFee
        );
}

