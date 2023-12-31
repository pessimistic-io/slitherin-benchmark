// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "./UD60x18.sol";
import {IERC1155Base} from "./IERC1155Base.sol";
import {IERC1155Enumerable} from "./IERC1155Enumerable.sol";

interface IOptionPS is IERC1155Base, IERC1155Enumerable {
    enum TokenType {
        Long,
        Short
    }

    error OptionPS__ExercisePeriodEnded(uint256 maturity, uint256 exercisePeriodEnd);
    error OptionPS__ExercisePeriodNotEnded(uint256 maturity, uint256 exercisePeriodEnd);
    error OptionPS__OptionMaturityNot8UTC(uint256 maturity);
    error OptionPS__OptionExpired(uint256 maturity);
    error OptionPS__OptionNotExpired(uint256 maturity);
    error OptionPS__StrikeNotMultipleOfStrikeInterval(UD60x18 strike, UD60x18 strikeInterval);

    event Exercise(
        address indexed user,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 exerciseCost,
        UD60x18 exerciseFee
    );

    event Settle(
        address indexed user,
        UD60x18 contractSize,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 collateralAmount,
        UD60x18 exerciseTokenAmount
    );

    event Underwrite(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize
    );

    event Annihilate(address indexed annihilator, UD60x18 strike, uint256 maturity, UD60x18 contractSize);

    /// @notice Returns the pair infos for this option
    function getSettings() external view returns (address base, address quote, bool isCall);

    /// @notice Returns the length of time in seconds during which long holders can exercise their options after maturity
    function getExerciseDuration() external pure returns (uint256);

    /// @notice Underwrite an option by depositing collateral
    /// @param strike the option strike price (18 decimals)
    /// @param longReceiver the address that will receive the long tokens
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of long tokens to mint (18 decimals)
    function underwrite(UD60x18 strike, uint64 maturity, address longReceiver, UD60x18 contractSize) external;

    /// @notice Burn longs and shorts, to recover collateral of the option
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of contracts to annihilate (18 decimals)
    function annihilate(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    /// @notice Exercises the long options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of long tokens to exercise (18 decimals)
    /// @return exerciseValue the amount of tokens transferred to the caller
    function exercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external returns (uint256 exerciseValue);

    /// @notice Settles the short options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of short tokens to settle (18 decimals)
    /// @return collateralAmount the amount of collateral transferred to the caller (base for calls, quote for puts)
    /// @return exerciseTokenAmount the amount of exerciseToken transferred to the caller (quote for calls, base for puts)
    function settle(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external returns (uint256 collateralAmount, uint256 exerciseTokenAmount);

    /// @notice Returns the list of existing tokenIds with non zero balance
    /// @return tokenIds The list of existing tokenIds
    function getTokenIds() external view returns (uint256[] memory);
}

