//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./IUtilityToken.sol";
import "./IFeeRouter.sol";

interface IConfig {
    struct StableCoinEnabled {
        bool buyEnabled;
        bool sellEnabled;
        bool exists;
        address gauge;
        bool isMetaGauge;
    }

    function vammBuyFees(uint256 totalPrice) external view returns (uint256);

    function vammSellFees(uint256 totalPrice) external view returns (uint256);

    function getVAMMStableCoin(
        address stableCoin
    ) external view returns (StableCoinEnabled memory);

    function getStableCoins() external view returns (address[] memory);

    function getMaxOnceExchangeAmount() external view returns (uint256);

    function getFeeRouter() external view returns (IFeeRouter);

    function getUtilityToken() external view returns (IUtilityToken);

    function getPRToken() external view returns (IUtilityToken);

    function getGovToken() external view returns (IUtilityToken);

    function getStableCoinToken() external view returns (IUtilityToken);

    function getUtilityStakeAddress() external view returns (address);

    function getLiquidityStakeAddress() external view returns (address);

    function getVAMMAddress() external view returns (address);

    function getMinterAddress() external view returns (address);

    function getCurveStableCoin2CRVPoolAddress()
        external
        view
        returns (address);

    function checkIsOperator(address _operator) external view returns (bool);
}

