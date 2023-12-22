// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IPriceOracle} from "./IPriceOracle.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";
import {ICustomPriceOracle} from "./ICustomPriceOracle.sol";

contract DpxPutPriceOracle is IPriceOracle {
    /// @dev DPX Price Oracle
    ICustomPriceOracle public constant DPX_PRICE_ORACLE =
        ICustomPriceOracle(0x252C07E0356d3B1a8cE273E39885b094053137b9);

    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price() / 1e10;
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() external view returns (uint256) {
        return DPX_PRICE_ORACLE.getPriceInUSD();
    }
}

