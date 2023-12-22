// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IPriceOracle} from "./IPriceOracle.sol";
import {FlagsInterface} from "./FlagsInterface.sol";

interface ICustomPriceOracle {
    function getPriceInUSD() external view returns (uint256);
}

contract GohmCallPriceOracle is IPriceOracle {
    /// @dev RDPX Price Oracle
    ICustomPriceOracle public constant RDPX_PRICE_ORACLE =
        ICustomPriceOracle(0x6cB7D5BD21664E0201347bD93D66ce18Bc48A807);

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
        return getUnderlyingPrice();
    }

    /// @notice Returns the underlying price
    function getUnderlyingPrice() public view returns (uint256) {
        bool isRaised = CHAINLINK_FLAGS.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
        if (isRaised) {
            revert("Price feeds not being updated");
        }
        return RDPX_PRICE_ORACLE.getPriceInUSD();
    }
}

