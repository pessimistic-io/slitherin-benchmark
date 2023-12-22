// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";

interface IOption {
    enum OPTION_TYPE {
        CALLS,
        PUTS
    }

    struct ExecuteParams {
        uint256 currentEpoch;
        // strike price
        uint256[] _strikes;
        // % used in each strike;
        uint256[] _collateralEachStrike;
        uint256 _expiry;
        bytes _externalData;
    }

    // Data needed to settle the ITM options
    struct SettleParams {
        uint256 currentEpoch;
        uint256 optionEpoch;
        // The ITM strikes we will settle
        uint256[] strikesToSettle;
        bytes _externalData;
    }

    // Buys options.
    // Return avg option price in WETH
    function purchase(ExecuteParams calldata params) external;

    function executeSingleOptionPurchase(uint256 _strike, uint256 _collateral) external returns (uint256);

    // Settle ITM options
    function settle(SettleParams calldata params) external returns (uint256);

    // Get option price from given type and strike. On DopEx its returned in collateral token.
    function getOptionPrice(uint256 _strike) external view returns (uint256);

    // system epoch => option epoch
    function epochs(uint256 _epoch) external view returns (uint256);

    function strategy() external view returns (IRouter.OptionStrategy _strategy);

    // avg option price getting ExecuteParams buy the same options
    function optionType() external view returns (OPTION_TYPE);

    function getCurrentStrikes() external view returns (uint256[] memory);

    // Token used to buy options
    function getCollateralToken() external view returns (address);

    function geAllStrikestPrices() external view returns (uint256[] memory);

    function getAvailableOptions(uint256 _strike) external view returns (uint256);
    function position() external view returns (uint256);

    function lpToCollateral(address _lp, uint256 _amount) external view returns (uint256);
    function getExpiry() external view returns (uint256);
}

