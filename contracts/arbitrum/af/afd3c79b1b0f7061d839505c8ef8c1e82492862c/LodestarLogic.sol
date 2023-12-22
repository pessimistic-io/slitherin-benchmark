// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./ILodestar.sol";
import "./AggregatorV3Interface.sol";
import "./LendingLogic.sol";

contract LodestarLogic is LendingLogic {
    function _checkMarkets(address xToken)
        internal
        view
        override
        returns (bool isUsedXToken)
    {
        (isUsedXToken, , ) = IComptrollerLodestar(comptroller).markets(xToken);
    }

    function _claim(address[] memory xTokens) internal override {
        IDistributionLodestar(rainMaker).claimComp(address(this), xTokens);
    }

    function _rewardToken() internal view override returns (address) {
        return IDistributionLodestar(comptroller).getCompAddress();
    }

    function _getUnderlyingPrice(address xToken)
        internal
        view
        override
        returns (uint256)
    {
        address oracle = IComptrollerLodestar(comptroller).oracle();
        address ethUsdAggregator = IOracleLodestar(oracle).ethUsdAggregator();

        return
            (IOracleLodestar(oracle).getUnderlyingPrice(xToken) *
                uint256(
                    AggregatorV3Interface(ethUsdAggregator).latestAnswer()
                )) / (10**AggregatorV3Interface(ethUsdAggregator).decimals());
    }

    function _getUnderlying(address xToken)
        internal
        view
        override
        returns (address)
    {
        address underlying;
        if (xToken == 0x2193c45244AF12C280941281c8aa67dD08be0a64) {
            underlying = ZERO_ADDRESS;
        } else {
            underlying = IXToken(xToken).underlying();
        }

        return underlying;
    }

    function _getCollateralFactor(address xToken)
        internal
        view
        override
        returns (uint256 collateralFactor)
    {
        // get collateralFactor from market
        (, collateralFactor, ) = IComptrollerLodestar(comptroller).markets(
            xToken
        );
    }

    function _accrueInterest(address xToken) internal override {
        IXToken(xToken).accrueInterest();
    }
}

