// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {FlagsInterface} from "./FlagsInterface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";
import {ICustomPriceOracle} from "./ICustomPriceOracle.sol";

contract GmxPutPriceOracle is IPriceOracle {
    /// @dev GMX Price Oracle
    ICustomPriceOracle public constant GMX_PRICE_ORACLE =
        ICustomPriceOracle(0x60E07B25Ba79bf8D40831cdbDA60CF49571c7Ee0);

    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    /// @dev Identifier of the Sequencer offline flag on the Flags contract
    address private constant FLAG_ARBITRUM_SEQ_OFFLINE =
        address(
            bytes20(
                bytes32(
                    uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) -
                        1
                )
            )
        );

    /// @dev Chainlink Flags
    FlagsInterface internal constant CHAINLINK_FLAGS =
        FlagsInterface(0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83);

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price() / 1e10;
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() external view returns (uint256) {
        bool isRaised = CHAINLINK_FLAGS.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
        if (isRaised) {
            revert("Price feeds not being updated");
        }
        return GMX_PRICE_ORACLE.getPriceInUSD();
    }
}

