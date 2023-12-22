pragma solidity 0.8.17;

import { GlobalACL, Auth } from "./Auth.sol";
import { IAggregatorV3Interface } from "./IAggregatorV3Interface.sol";
import { ERC20 } from "./ERC20.sol";

contract OracleWrapper is GlobalACL {
    error ZeroAddress();
    error InvalidPrice();

    event UpdateTokenDetails(address indexed _token, TokenDetails _tokenDetails);

    struct TokenDetails {
        uint96 decimals;
        address chainlinkPriceFeed;
    }

    mapping(address => TokenDetails) public tokenDetails;

    constructor(Auth _auth) GlobalACL(_auth) { }

    function updateTokenDetails(address _token, address _chainlinkPriceFeed, uint256 _decimals)
        external
        onlyConfigurator
    {
        TokenDetails storage deets = tokenDetails[_token];
        deets.chainlinkPriceFeed = _chainlinkPriceFeed;
        // read decimals from chain if token contract is not empty and decimals arg passed is 0
        uint96 decimals = _decimals > 0 ? uint96(_decimals) : _token.code.length > 0 ? ERC20(_token).decimals() : 0;
        deets.decimals = decimals;
        emit UpdateTokenDetails(_token, deets);
    }

    function getChainlinkPrice(address _token) public view returns (uint256 _price) {
        TokenDetails storage deets = tokenDetails[_token];
        address priceFeed = deets.chainlinkPriceFeed;
        if (priceFeed == address(0)) revert ZeroAddress();

        (, int256 price,,,) = IAggregatorV3Interface(priceFeed).latestRoundData();
        if (price < 0) revert InvalidPrice();
        _price = uint256(price);
        uint256 priceDecimal = IAggregatorV3Interface(priceFeed).decimals();
        _price = _price * 1e18 / (10 ** priceDecimal);
    }
}

