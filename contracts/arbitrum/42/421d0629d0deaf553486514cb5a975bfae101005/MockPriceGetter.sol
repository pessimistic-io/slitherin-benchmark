// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
    *******         **********     ***********     *****     ***********
    *      *        *              *                 *       *
    *        *      *              *                 *       *
    *         *     *              *                 *       *
    *         *     *              *                 *       *
    *         *     **********     *       *****     *       ***********
    *         *     *              *         *       *                 *
    *         *     *              *         *       *                 *
    *        *      *              *         *       *                 *
    *      *        *              *         *       *                 *
    *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {OwnableWithoutContext} from "./OwnableWithoutContext.sol";

/**
 * @title  Price Getter
 * @notice This is the contract for getting price feed from chainlink.
 *         The contract will keep a record from tokenName => priceFeed Address.
 *         Got the sponsorship and collaboration with Chainlink.
 * @dev    The price from chainlink priceFeed has different decimals, be careful.
 */
contract MockPriceGetter is OwnableWithoutContext {
    // Find address according to name
    mapping(string => address) public nameToAddress;

    event LatestPriceGet(address token);

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    constructor() OwnableWithoutContext(msg.sender) {}

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Main Functions *********************************** //
    // ---------------------------------------------------------------------------------------- //

    function getLatestPrice(string memory _tokenName) public returns (uint256) {
        return getLatestPrice(nameToAddress[_tokenName]);
    }

    function getLatestPrice(address _tokenAddress) public returns (uint256) {
        emit LatestPriceGet(_tokenAddress);
        return 1e18;
    }
}

