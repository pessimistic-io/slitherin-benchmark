// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPriceOracle} from "./IPriceOracle.sol";
import {IDIAOracleV2} from "./IDIAOracleV2.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";

contract RdpxPutPriceOracleV2 is IPriceOracle {
    /// @dev 2CRV USDC/USDT Pool
    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    /// @dev DIA Oracle V2
    IDIAOracleV2 public constant DIA_ORACLE_V2 =
        IDIAOracleV2(0xe871E9BD0ccc595A626f5e1657c216cE457CEa43);

    /// @dev RDPX value key
    string public constant RDPX_VALUE_KEY = "RDPX/USD";

    error HeartbeatNotFulfilled();

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price() / 1e10;
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() public view returns (uint256) {
        (uint128 price, uint128 updatedAt) = DIA_ORACLE_V2.getValue(
            RDPX_VALUE_KEY
        );

        if ((block.timestamp - uint256(updatedAt)) > 86400) {
            revert HeartbeatNotFulfilled();
        }

        return uint256(price);
    }
}

