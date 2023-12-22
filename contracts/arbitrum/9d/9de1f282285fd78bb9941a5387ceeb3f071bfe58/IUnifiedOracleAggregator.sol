// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./Ownable2Step.sol";
import "./extensions_IERC20Metadata.sol";
import "./AggregatorV3Interface.sol";

/// @title Oracle aggergator for uni and link oracles
/// @author flora.loans
/// @notice Owner can set Chainlink oracles for specific tokens
/// @notice returns the token price from chainlink oracle (if available) otherwise the uni oracle will be used
interface IUnifiedOracleAggregator {
    function linkOracles(address) external view returns (address);

    function setOracle(address, AggregatorV3Interface) external;

    function preparePool(address, address, uint16) external;

    function tokenSupported(address) external view returns (bool);

    function tokenPrice(address) external view returns (uint256);

    function tokenPrices(
        address,
        address
    ) external view returns (uint256, uint256);

    /// @dev Not used in any code to save gas. But useful for external usage.
    function convertTokenValues(
        address,
        address,
        uint256
    ) external view returns (uint256);
}

