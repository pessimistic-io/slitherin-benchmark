// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./AntfarmOracle.sol";
import "./IAntfarmBase.sol";

interface IAntfarmAtfPair is IAntfarmBase {
    /// @notice Initialize the pair
    /// @dev Can only be called by the factory
    function initialize(
        address,
        address,
        uint16
    ) external;

    /// @notice The Oracle instance associated to the AntfarmPair
    /// @return AntfarmOracle Oracle instance
    function antfarmOracle() external view returns (address);

    /// @notice Average token0 price depending on the AntfarmOracle's period
    /// @return uint token0 Average price
    function price1CumulativeLast() external view returns (uint256);
}

