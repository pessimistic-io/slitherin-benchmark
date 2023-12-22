// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {FlagsInterface} from "./FlagsInterface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

contract EthCallPriceOracle is IPriceOracle {
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

    /// @dev ETH/USD priceFeed
    AggregatorV3Interface internal immutable priceFeed;

    /// @dev Chainlink Flags
    FlagsInterface internal immutable chainlinkFlags;

    constructor() {
        /**
         * Network: Arbitrum Mainnet
         * Aggregator: ETH/USD
         * Agg Address: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
         * Flags Address: 0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83
         */
        priceFeed = AggregatorV3Interface(
            0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
        );
        chainlinkFlags = FlagsInterface(
            0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83
        );
    }

    /// @notice Returns the collateral price
    function getCollateralPrice() external view returns (uint256) {
        return getUnderlyingPrice();
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

