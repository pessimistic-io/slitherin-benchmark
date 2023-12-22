// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IPriceOracle} from "./IPriceOracle.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";
import {ICustomPriceOracle} from "./ICustomPriceOracle.sol";

contract RdpxPutPriceOracle is IPriceOracle {
    /// @dev RDPX Price Oracle
    ICustomPriceOracle public constant RDPX_PRICE_ORACLE =
        ICustomPriceOracle(0xa70bF62578AaDb37032c73f01873bCC7Dcef1B9c);

    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price() / 1e10;
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() external view returns (uint256) {
        return RDPX_PRICE_ORACLE.getPriceInUSD();
    }
}

