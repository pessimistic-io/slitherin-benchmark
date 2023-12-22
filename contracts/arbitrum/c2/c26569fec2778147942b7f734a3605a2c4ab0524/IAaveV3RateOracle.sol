// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

import "./IAaveV3LendingPool.sol";
import "./IRateOracle.sol";

interface IAaveV3RateOracle is IRateOracle {

    /// @notice Gets the address of the Aave Lending Pool
    /// @return Address of the Aave Lending Pool
    function aaveLendingPool() external view returns (IAaveV3LendingPool);

}
