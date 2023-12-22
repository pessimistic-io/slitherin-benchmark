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
import {OwnableWithoutContextUpgradeable} from "./OwnableWithoutContextUpgradeable.sol";

/**
 * @title  Price Getter
 * @notice This is the contract for getting price feed from chainlink.
 *         The contract will keep a record from tokenName => priceFeed Address.
 *         Got the sponsorship and collaboration with Chainlink.
 * @dev    The price from chainlink priceFeed has different decimals, be careful.
 */
contract PriceGetter is OwnableWithoutContextUpgradeable {
    struct PriceFeedInfo {
        address priceFeedAddress;
        uint256 decimals;
    }
    // Use token address as the mapping key
    mapping(address => PriceFeedInfo) public priceFeedInfo;

    // Find address according to name
    mapping(string => address) public nameToAddress;

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //
    event PriceFeedChanged(
        string tokenName,
        address tokenAddress,
        address feedAddress,
        uint256 decimals
    );

    event LatestPriceGet(
        uint80 roundID,
        int256 price,
        uint256 startedAt,
        uint256 timeStamp,
        uint80 answeredInRound
    );

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize() public initializer {
        __Ownable_init();
    }

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Modifiers ************************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Can not give zero address
     */
    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Zero address");
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Set a price feed oracle address for a token
     * @dev Only callable by the owner
     *      The price result decimal should be less than 18
     *
     * @param _tokenName   Address of the token
     * @param _tokenAddress Address of the token
     * @param _feedAddress Price feed oracle address
     * @param _decimals    Decimals of this price feed service
     */
    function setPriceFeed(
        string memory _tokenName,
        address _tokenAddress,
        address _feedAddress,
        uint256 _decimals
    ) public onlyOwner notZeroAddress(_feedAddress) {
        require(_decimals <= 18, "Too many decimals");

        priceFeedInfo[_tokenAddress] = PriceFeedInfo(_feedAddress, _decimals);
        nameToAddress[_tokenName] = _tokenAddress;

        emit PriceFeedChanged(
            _tokenName,
            _tokenAddress,
            _feedAddress,
            _decimals
        );
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Main Functions *********************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get latest price of a token
     *
     * @param _tokenName Name of the token
     *
     * @return price The latest price
     */
    function getLatestPrice(string memory _tokenName) public returns (uint256) {
        return getLatestPrice(nameToAddress[_tokenName]);
    }

    /**
     * @notice Get latest price of a token
     *
     * @param _tokenAddress Address of the token
     *
     * @return finalPrice The latest price
     */
    function getLatestPrice(address _tokenAddress)
        public
        returns (uint256 finalPrice)
    {
        PriceFeedInfo memory priceFeed = priceFeedInfo[_tokenAddress];

        if (priceFeed.priceFeedAddress == address(0)) {
            finalPrice = 1e18;
        } else {
            (
                uint80 roundID,
                int256 price,
                uint256 startedAt,
                uint256 timeStamp,
                uint80 answeredInRound
            ) = AggregatorV3Interface(priceFeed.priceFeedAddress)
                    .latestRoundData();

            // require(price > 0, "Only accept price that > 0");
            if (price < 0) price = 0;

            emit LatestPriceGet(
                roundID,
                price,
                startedAt,
                timeStamp,
                answeredInRound
            );
            // Transfer the result decimals
            finalPrice = uint256(price) * (10**(18 - priceFeed.decimals));
        }
    }
}

