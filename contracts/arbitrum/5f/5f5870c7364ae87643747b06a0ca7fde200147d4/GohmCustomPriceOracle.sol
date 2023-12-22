// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

contract GohmCustomPriceOracle is Ownable {
    /*==== PUBLIC VARS ====*/

    uint256 public lastPrice;

    /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

    /**
     * @notice Updates the last price of the token
     * @param price price
     * @return price of the token
     */
    function updatePrice(uint256 price) external onlyOwner returns (uint256) {
        require(price != 0, 'CustomPriceOracle: Token price cannot be 0');

        lastPrice = price;

        return price;
    }

    /*==== VIEWS ====*/

    /**
     * @notice Gets the price of the token
     * @return price
     */
    function getPriceInUSD() external view returns (uint256) {
        require(lastPrice != 0, 'CustomPriceOracle: Last price == 0');

        return lastPrice;
    }
}

