// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyOverview.sol";
import "./ISavvyUserPortfolio.sol";
import "./ISavvyUserBalance.sol";
import "./ISavvyPositions.sol";
import "./ISavvyPool.sol";
import "./ISavvyFrontend.sol";
import "./IVeSvy.sol";
import "./ISavvyBooster.sol";
import "./ISavvyToken.sol";
import "./ISavvyPriceFeed.sol";

/// @title IInfoAggregator
/// @author Savvy DeFi
///
/// @notice Simplifies the calls required to get protcol and user information.
/// @dev Used by the frontend.
interface IInfoAggregator is
    ISavvyOverview,
    ISavvyUserPortfolio,
    ISavvyUserBalance,
    ISavvyPositions,
    ISavvyPool
{
    /// @notice Add new SavvyPositionManagers.
    /// @dev Only owner can call this function. If not, return IllegalArgument().
    /// @param savvyPositionManagers_ List of SavvyPositionManager addresses.
    function addSavvyPositionManager(
        address[] memory savvyPositionManagers_
    ) external;

    /// @notice Add support tokens to infoAggregator.
    /// @param _supportTokens The informations of savvy supports
    function addSupportTokens(
        SupportTokenInfo[] calldata _supportTokens
    ) external;

    /// @notice Get all registered SavvyPositionManager addresses.
    function getSavvyPositionManagers()
        external
        view
        returns (address[] memory);

    /// @dev The contract to get token price.
    function svyPriceFeed()
        external
        view
        returns (ISavvyPriceFeed svyPriceFeed);

    /// @dev Savvy DeFi's own token.
    function svyToken() external view returns (ISavvyToken svyToken);

    /// @dev SavvyBooster contract handle.
    function svyBooster() external view returns (ISavvyBooster svyBooster);

    /// @dev VeSvy contract handle.
    function veSvy() external view returns (IVeSvy veSvy);
}

