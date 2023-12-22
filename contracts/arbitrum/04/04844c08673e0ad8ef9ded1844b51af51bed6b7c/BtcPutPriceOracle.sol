// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {FlagsInterface} from "./FlagsInterface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ICrv2Pool} from "./ICrv2Pool.sol";

contract BtcPutPriceOracle is IPriceOracle {
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

    /// @dev BTC/USD priceFeed
    AggregatorV3Interface internal immutable priceFeed;

    /// @dev Chainlink Flags
    FlagsInterface internal immutable chainlinkFlags;

    ICrv2Pool public constant CRV_2POOL =
        ICrv2Pool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    constructor() {
        /**
         * Network: Arbitrum Mainnet
         * Aggregator: BTC/USD
         * Agg Address: 0x6ce185860a4963106506C203335A2910413708e9
         * Flags Address: 0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83
         */
        priceFeed = AggregatorV3Interface(
            0x6ce185860a4963106506C203335A2910413708e9
        );
        chainlinkFlags = FlagsInterface(
            0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83
        );
    }

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return CRV_2POOL.get_virtual_price() / 1e10;
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() public view returns (uint256) {
        bool isRaised = chainlinkFlags.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
        if (isRaised) {
            revert("Price feeds not being updated");
        }
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }
}

