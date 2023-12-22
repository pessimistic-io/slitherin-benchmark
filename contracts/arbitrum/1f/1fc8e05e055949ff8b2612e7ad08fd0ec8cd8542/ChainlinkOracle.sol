// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./AggregatorV3Interface.sol";
import "./ERC20.sol";
import "./AddressArray.sol";
import "./IOracle.sol";
import "./AccessControl.sol";

/**
 * @notice Oracle that calculates prices using chainlink price feeds
 */
contract ChainlinkOracle is IOracle, AccessControl {
    using AddressArray for address[];
    
    /// @notice Mapping from token addresses to Chainlink price feeds
    mapping (address=>AggregatorV3Interface) public priceFeeds;

    /// @notice Array of all tokens with non-zero address price feeds
    address[] public supportedTokens;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     * @dev For every token whose price feed isn't the zero address, the token will be added to supportedTokens
     * @dev latestRoundData is called on the price feed to prevent incorrect initialization
     */
    function initialize(address[] memory _tokens, address[] memory _priceFeeds, address _addressProvider) external initializer {
        __AccessControl_init(_addressProvider);
        require(_tokens.length==_priceFeeds.length, "Mismatched input length");
        for (uint i = 0; i<_tokens.length; i++) {
            if (_priceFeeds[i]!=address(0)) {
                supportedTokens.push(_tokens[i]);
                AggregatorV3Interface(_priceFeeds[i]).latestRoundData();
            }
            priceFeeds[_tokens[i]] = AggregatorV3Interface(_priceFeeds[i]);
        }
    }

    /**
     * @notice Set price feeds for tokens
     * @dev If token is not present in supportedTokens and priceFeed isn't zero address it will be pushed
     * Otherwise, if priceFeed is zero address, token will be removed from supportedTokens if present
     * @dev latestRoundData is called on the price feed to prevent incorrect addresses
     */
    function setPriceFeeds(address[] memory _tokens, address[] memory _priceFeeds) public restrictAccess(GOVERNOR) {
        require(_tokens.length==_priceFeeds.length, "Mismatched input length");
        for (uint i = 0; i<_tokens.length; i++) {
            if (_priceFeeds[i]==address(0) && address(priceFeeds[_tokens[i]])!=address(0)) {
                uint idx = supportedTokens.findFirst(_tokens[i]);
                supportedTokens[idx] = supportedTokens[supportedTokens.length-1];
                supportedTokens.pop();
            }
            if (_priceFeeds[i]!=address(0)) {
                if (address(priceFeeds[_tokens[i]])!=_priceFeeds[i]) {
                    supportedTokens.push(_tokens[i]);
                }
                AggregatorV3Interface(_priceFeeds[i]).latestRoundData();
            }
            priceFeeds[_tokens[i]] = AggregatorV3Interface(_priceFeeds[i]);
        }
    }

    /**
     @notice Get array of all tokens with initialized price feeds
     */
    function getSupportedTokens() external view returns (address[] memory tokens) {
        tokens = supportedTokens.copy();
    }

    /// @inheritdoc IOracle
    function getPrice(address token) public view returns (uint price) {
        (, int p,,,) = priceFeeds[token].latestRoundData();
        price = uint(p)*10**10;
    }

    /// @inheritdoc IOracle
    function getPriceInTermsOf(address token, address inTermsOf) public view returns (uint price) {
        (, int tokenPrice,,,) = priceFeeds[token].latestRoundData();
        (, int inTermsOfPrice,,,) = priceFeeds[inTermsOf].latestRoundData();
        
        uint decimals = 10**ERC20(inTermsOf).decimals();
        price = decimals*uint(tokenPrice)/uint(inTermsOfPrice);
    }

    /// @inheritdoc IOracle
    function getValue(address token, uint amount) external view returns (uint value) {
        uint256 price = getPrice(token);
        uint decimals = 10**ERC20(token).decimals();
        value = amount*uint(price)/decimals;
    }

    /// @inheritdoc IOracle
    function getValueInTermsOf(address token, uint amount, address inTermsOf) external view returns (uint value) {
        uint256 price = getPriceInTermsOf(token, inTermsOf);
        uint decimals = 10**ERC20(token).decimals();
        value = (price * amount) / decimals;
    }
}
