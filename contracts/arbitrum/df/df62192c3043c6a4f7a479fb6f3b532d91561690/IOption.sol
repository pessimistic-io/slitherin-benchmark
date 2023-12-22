// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IRouter} from "./IRouter.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";

interface IOption {
    // Data needed to purchase and settle options
    struct OptionParams {
        uint16 _epoch;
        IOptionStrategy.Option _option;
        bytes _optionData;
    }

    // Buys options.
    // Return avg option price in WETH
    function purchase(OptionParams calldata params) external;

    // Settle ITM options
    function settle(OptionParams calldata params) external returns (uint256);

    function position(address _optionStrategy, address _compoundStrategy, IRouter.OptionStrategy _type)
        external
        view
        returns (uint256);

    function pnl(address _optionStrategy, address _compoundStrategy, IRouter.OptionStrategy _type)
        external
        view
        returns (uint256);

    function lpToCollateral(address _lp, uint256 _amount, address _optionStrategy) external view returns (uint256);
}

