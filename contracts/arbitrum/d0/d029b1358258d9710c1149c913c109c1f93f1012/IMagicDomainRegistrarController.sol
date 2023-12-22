// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

interface IMagicDomainRegistrarController {

    event NameRegistered(
        string name,
        string discriminant,
        address indexed owner
    );

    error InvalidSignature();

    struct RegisterArgs {
        string name;
        string discriminant;
        address owner;
        address resolver;
        uint96 nonce;
    }

    /**
     * @dev Used to track Pricing configurations on a per-token basis 
     * @param enabled Whether or not this pricing configuration is enabled
     * @param priceFeed The price feed to get derived costs from. If its 0x0 then calculatePriceFromFeed will be false
     * @param calculatePriceFromFeed Helper to ensure priceFeed is set correctly and determines if `price` is a different token value (and/or decimal)
     * @param paymentTokenDecimals The number of decimals of the base payment token.
     *  Needed to ensure proper funds transferring when decimals in the pair differ
     * @param price The value set to be validated against. Can be non-payment token amounts when using a price feed
     */
    struct PriceInfo {
        bool enabled;
        AggregatorV3Interface priceFeed;
        bool calculatePriceFromFeed;
        uint8 paymentTokenDecimals;
        uint256 price;
    }

    function available(string memory name, string memory discriminant) external returns (bool);

    function register(RegisterArgs calldata _registerArgs, bytes calldata _authoritySignature) external;
    function changeTag(RegisterArgs calldata _registerArgs, bytes calldata _authoritySignature) external;

}
