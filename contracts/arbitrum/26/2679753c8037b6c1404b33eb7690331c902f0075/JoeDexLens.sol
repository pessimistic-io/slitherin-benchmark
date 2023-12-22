// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Constants} from "./Constants.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {JoeLibrary} from "./JoeLibrary.sol";
import {IJoeFactory} from "./IJoeFactory.sol";
import {IJoePair} from "./IJoePair.sol";
import {ILBFactory} from "./ILBFactory.sol";
import {ILBLegacyFactory} from "./ILBLegacyFactory.sol";
import {ILBLegacyPair} from "./ILBLegacyPair.sol";
import {ILBPair} from "./ILBPair.sol";
import {Uint256x256Math} from "./Uint256x256Math.sol";
import {IERC20Metadata, IERC20} from "./IERC20Metadata.sol";
import {     ISafeAccessControlEnumerable, SafeAccessControlEnumerable } from "./SafeAccessControlEnumerable.sol";

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IJoeDexLens} from "./IJoeDexLens.sol";

/**
 * @title Joe Dex Lens
 * @author Trader Joe
 * @notice This contract allows to price tokens in either Native or USD.
 * It uses a set of data feeds to get the price of a token. The data feeds can be added or removed by the owner and
 * the data feed manager. They can also set the weight of each data feed.
 * When no data feed is provided, the contract will iterate over TOKEN/WNative
 * pools on v2.1, v2 and v1 to find a weighted average price.
 */
contract JoeDexLens is SafeAccessControlEnumerable, IJoeDexLens {
    using Uint256x256Math for uint256;
    using PriceHelper for uint24;

    bytes32 public constant DATA_FEED_MANAGER_ROLE = keccak256("DATA_FEED_MANAGER_ROLE");

    uint256 private constant _BIN_WIDTH = 5;
    uint256 private constant _TWO_BASIS_POINT = 20_000;

    ILBFactory private immutable _FACTORY_V2_1;
    ILBLegacyFactory private immutable _LEGACY_FACTORY_V2;
    IJoeFactory private immutable _FACTORY_V1;

    address private immutable _WNATIVE;
    uint256 private immutable _WNATIVE_DECIMALS;
    uint256 private immutable _WNATIVE_PRECISION;

    /**
     * @dev Mapping from a token to an enumerable set of data feeds used to get the price of the token
     */
    mapping(address => DataFeedSet) private _whitelistedDataFeeds;

    /**
     * Modifiers *
     */

    /**
     * @notice Verify that the two lengths match
     * @dev Revert if length are not equal
     * @param lengthA The length of the first list
     * @param lengthB The length of the second list
     */
    modifier verifyLengths(uint256 lengthA, uint256 lengthB) {
        if (lengthA != lengthB) revert JoeDexLens__LengthsMismatch();
        _;
    }

    /**
     * @notice Verify a data feed
     * @dev Revert if :
     * - The dataFeed's collateral and the token are the same address
     * - The dataFeed's collateral is not one of the two tokens of the pair (if the dfType is V1 or V2)
     * - The token is not one of the two tokens of the pair (if the dfType is V1 or V2)
     * @param token The address of the token
     * @param dataFeed The data feeds information
     */
    modifier verifyDataFeed(address token, DataFeed calldata dataFeed) {
        address collateralAddress = dataFeed.collateralAddress;
        if (collateralAddress == token) revert JoeDexLens__SameTokens();

        DataFeedType dfType = dataFeed.dfType;

        if (dfType != DataFeedType.CHAINLINK) {
            if (dfType == DataFeedType.V2_1 && address(_FACTORY_V2_1) == address(0)) {
                revert JoeDexLens__V2_1ContractNotSet();
            } else if (dfType == DataFeedType.V2 && address(_LEGACY_FACTORY_V2) == address(0)) {
                revert JoeDexLens__V2ContractNotSet();
            } else if (dfType == DataFeedType.V1 && address(_FACTORY_V1) == address(0)) {
                revert JoeDexLens__V1ContractNotSet();
            }

            (address tokenA, address tokenB) = _getPairedTokens(dataFeed.dfAddress, dfType);

            if (tokenA != collateralAddress && tokenB != collateralAddress) {
                revert JoeDexLens__CollateralNotInPair(dataFeed.dfAddress, collateralAddress);
            }

            if (tokenA != token && tokenB != token) revert JoeDexLens__TokenNotInPair(dataFeed.dfAddress, token);
        }
        _;
    }

    /**
     * @notice Verify the weight for a data feed
     * @dev Revert if the weight is equal to 0
     * @param weight The weight of a data feed
     */
    modifier verifyWeight(uint88 weight) {
        if (weight == 0) revert JoeDexLens__NullWeight();
        _;
    }

    /**
     * @notice Constructor of the contract
     * @dev Revert if :
     * - All addresses are zero
     * - wnative is zero
     * @param lbFactory The address of the v2.1 factory
     * @param lbLegacyFactory The address of the v2 factory
     * @param joeFactory The address of the v1 factory
     * @param wnative The address of the wnative token
     */
    constructor(ILBFactory lbFactory, ILBLegacyFactory lbLegacyFactory, IJoeFactory joeFactory, address wnative) {
        // revert if all addresses are zero or if wnative is zero
        if (
            address(lbFactory) == address(0) && address(lbLegacyFactory) == address(0)
                && address(joeFactory) == address(0) || wnative == address(0)
        ) {
            revert JoeDexLens__ZeroAddress();
        }

        _FACTORY_V1 = joeFactory;
        _LEGACY_FACTORY_V2 = lbLegacyFactory;
        _FACTORY_V2_1 = lbFactory;

        _WNATIVE = wnative;

        _WNATIVE_DECIMALS = IERC20Metadata(wnative).decimals();
        _WNATIVE_PRECISION = 10 ** _WNATIVE_DECIMALS;
    }

    /**
     * @notice Initialize the contract
     * @dev Transfer the ownership to the sender and set the native data feed
     * @param aggregator The address of the aggregator
     */
    function initialize(address aggregator) external {
        if (_getDataFeedsLength(_WNATIVE) != 0) revert JoeDexLens__AlreadyInitialized();
        _whitelistedDataFeeds[_WNATIVE].dataFeeds.push();

        _transferOwnership(msg.sender);
        _setNativeDataFeed(aggregator);
    }

    /**
     * @notice Returns the address of the wrapped native token
     * @return wNative The address of the wrapped native token
     */
    function getWNative() external view override returns (address wNative) {
        return _WNATIVE;
    }

    /**
     * @notice Returns the address of the factory v1
     * @return factoryV1 The address of the factory v1
     */
    function getFactoryV1() external view override returns (IJoeFactory factoryV1) {
        return _FACTORY_V1;
    }

    /**
     * @notice Returns the address of the factory v2
     * @return legacyFactoryV2 The address of the factory v2
     */
    function getLegacyFactoryV2() external view override returns (ILBLegacyFactory legacyFactoryV2) {
        return _LEGACY_FACTORY_V2;
    }

    /**
     * @notice Returns the address of the factory v2.1
     * @return factoryV2 The address of the factory v2.1
     */
    function getFactoryV2_1() external view override returns (ILBFactory factoryV2) {
        return _FACTORY_V2_1;
    }

    /**
     * @notice Returns the list of data feeds used to calculate the price of the token
     * @param token The address of the token
     * @return dataFeeds The array of data feeds used to price `token`
     */
    function getDataFeeds(address token) external view override returns (DataFeed[] memory dataFeeds) {
        return _whitelistedDataFeeds[token].dataFeeds;
    }

    /**
     * @notice Returns the price of token in USD, scaled with wnative's decimals
     * @param token The address of the token
     * @return price The price of the token in USD, with wnative's decimals
     */
    function getTokenPriceUSD(address token) external view override returns (uint256 price) {
        return _getTokenWeightedAverageNativePrice(token) * _getNativePrice() / _WNATIVE_PRECISION;
    }

    /**
     * @notice Returns the price of token in Native, scaled with wnative's decimals
     * @param token The address of the token
     * @return price The price of the token in Native, with wnative's decimals
     */
    function getTokenPriceNative(address token) external view override returns (uint256 price) {
        return _getTokenWeightedAverageNativePrice(token);
    }

    /**
     * @notice Returns the prices of each token in USD, scaled with wnative's decimals
     * @param tokens The list of address of the tokens
     * @return prices The prices of each token in USD, with wnative's decimals
     */
    function getTokensPricesUSD(address[] calldata tokens) external view override returns (uint256[] memory prices) {
        return _getTokenWeightedAverageNativePrices(tokens);
    }

    /**
     * @notice Returns the prices of each token in Native, scaled with wnative's decimals
     * @param tokens The list of address of the tokens
     * @return prices The prices of each token in Native, with wnative's decimals
     */
    function getTokensPricesNative(address[] calldata tokens)
        external
        view
        override
        returns (uint256[] memory prices)
    {
        return _getTokenWeightedAverageNativePrices(tokens);
    }

    /**
     * Owner Functions *
     */

    /**
     * @notice Set the chainlink datafeed for the native token
     * @dev Can only be called by the owner
     * @param aggregator The address of the chainlink aggregator
     */
    function setNativeDataFeed(address aggregator) external override onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE) {
        _setNativeDataFeed(aggregator);
    }

    /**
     * @notice Add a data feed for a specific token
     * @dev Can only be called by the owner
     * @param token The address of the token
     * @param dataFeed The data feeds information
     */
    function addDataFeed(address token, DataFeed calldata dataFeed)
        external
        override
        onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE)
    {
        if (token == _WNATIVE) revert JoeDexLens__NativeToken();

        _addDataFeed(token, dataFeed);
    }

    /**
     * @notice Set the Native weight for a specific data feed of a token
     * @dev Can only be called by the owner
     * @param token The address of the token
     * @param dfAddress The data feed address
     * @param newWeight The new weight of the data feed
     */
    function setDataFeedWeight(address token, address dfAddress, uint88 newWeight)
        external
        override
        onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE)
    {
        _setDataFeedWeight(token, dfAddress, newWeight);
    }

    /**
     * @notice Remove a data feed of a token
     * @dev Can only be called by the owner
     * @param token The address of the token
     * @param dfAddress The data feed address
     */
    function removeDataFeed(address token, address dfAddress)
        external
        override
        onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE)
    {
        if (token == _WNATIVE) revert JoeDexLens__NativeToken();

        _removeDataFeed(token, dfAddress);
    }

    /**
     * @notice Batch add data feed for each (token, data feed)
     * @dev Can only be called by the owner
     * @param tokens The addresses of the tokens
     * @param dataFeeds The list of Native data feeds informations
     */
    function addDataFeeds(address[] calldata tokens, DataFeed[] calldata dataFeeds)
        external
        override
        onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE)
    {
        _addDataFeeds(tokens, dataFeeds);
    }

    /**
     * @notice Batch set the Native weight for each (token, data feed)
     * @dev Can only be called by the owner
     * @param tokens The list of addresses of the tokens
     * @param dfAddresses The list of Native data feed addresses
     * @param newWeights The list of new weights of the data feeds
     */
    function setDataFeedsWeights(
        address[] calldata tokens,
        address[] calldata dfAddresses,
        uint88[] calldata newWeights
    ) external override onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE) {
        _setDataFeedsWeights(tokens, dfAddresses, newWeights);
    }

    /**
     * @notice Batch remove a list of data feeds for each (token, data feed)
     * @dev Can only be called by the owner
     * @param tokens The list of addresses of the tokens
     * @param dfAddresses The list of data feed addresses
     */
    function removeDataFeeds(address[] calldata tokens, address[] calldata dfAddresses)
        external
        override
        onlyOwnerOrRole(DATA_FEED_MANAGER_ROLE)
    {
        _removeDataFeeds(tokens, dfAddresses);
    }

    /**
     * Private Functions *
     */

    /**
     * @notice Returns the data feed length for a specific token
     * @param token The address of the token
     * @return length The number of data feeds
     */
    function _getDataFeedsLength(address token) private view returns (uint256 length) {
        return _whitelistedDataFeeds[token].dataFeeds.length;
    }

    /**
     * @notice Returns the data feed at index `index` for a specific token
     * @param token The address of the token
     * @param index The index
     * @return dataFeed the data feed at index `index`
     */
    function _getDataFeedAt(address token, uint256 index) private view returns (DataFeed memory dataFeed) {
        return _whitelistedDataFeeds[token].dataFeeds[index];
    }

    /**
     * @notice Returns if a token's set contains the data feed address
     * @param token The address of the token
     * @param dfAddress The data feed address
     * @return Whether the set contains the data feed address (true) or not (false)
     */
    function _dataFeedContains(address token, address dfAddress) private view returns (bool) {
        return _whitelistedDataFeeds[token].indexes[dfAddress] != 0;
    }

    /**
     * @notice Add a data feed to a set, return true if it was added, false if not
     * @param token The address of the token
     * @param dataFeed The data feeds information
     * @return Whether the data feed was added (true) to the set or not (false)
     */
    function _addToSet(address token, DataFeed calldata dataFeed) private returns (bool) {
        if (!_dataFeedContains(token, dataFeed.dfAddress)) {
            DataFeedSet storage set = _whitelistedDataFeeds[token];

            set.dataFeeds.push(dataFeed);
            set.indexes[dataFeed.dfAddress] = set.dataFeeds.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Remove a data feed from a set, returns true if it was removed, false if not
     * @param token The address of the token
     * @param dfAddress The data feed address
     * @return Whether the data feed was removed (true) from the set or not (false)
     */
    function _removeFromSet(address token, address dfAddress) private returns (bool) {
        DataFeedSet storage set = _whitelistedDataFeeds[token];
        uint256 dataFeedIndex = set.indexes[dfAddress];

        if (dataFeedIndex != 0) {
            uint256 toDeleteIndex = dataFeedIndex - 1;
            uint256 lastIndex = set.dataFeeds.length - 1;

            if (toDeleteIndex != lastIndex) {
                DataFeed memory lastDataFeed = set.dataFeeds[lastIndex];

                set.dataFeeds[toDeleteIndex] = lastDataFeed;
                set.indexes[lastDataFeed.dfAddress] = dataFeedIndex;
            }

            set.dataFeeds.pop();
            delete set.indexes[dfAddress];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Add a data feed to a set, revert if it couldn't add it
     * @param token The address of the token
     * @param dataFeed The data feeds information
     */
    function _addDataFeed(address token, DataFeed calldata dataFeed)
        private
        verifyDataFeed(token, dataFeed)
        verifyWeight(dataFeed.dfWeight)
    {
        if (!_addToSet(token, dataFeed)) {
            revert JoeDexLens__DataFeedAlreadyAdded(token, dataFeed.dfAddress);
        }

        (uint256 price,) = _getDataFeedPrice(dataFeed, token);
        if (price == 0) revert JoeDexLens__InvalidDataFeed();

        emit DataFeedAdded(token, dataFeed);
    }

    /**
     * @notice Batch add data feed for each (token, data feed)
     * @param tokens The addresses of the tokens
     * @param dataFeeds The list of USD data feeds informations
     */
    function _addDataFeeds(address[] calldata tokens, DataFeed[] calldata dataFeeds)
        private
        verifyLengths(tokens.length, dataFeeds.length)
    {
        for (uint256 i; i < tokens.length;) {
            _addDataFeed(tokens[i], dataFeeds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set the weight for a specific data feed of a token
     * @param token The address of the token
     * @param dfAddress The data feed address
     * @param newWeight The new weight of the data feed
     */
    function _setDataFeedWeight(address token, address dfAddress, uint88 newWeight) private verifyWeight(newWeight) {
        DataFeedSet storage set = _whitelistedDataFeeds[token];

        uint256 index = set.indexes[dfAddress];
        if (index == 0) revert JoeDexLens__DataFeedNotInSet(token, dfAddress);

        set.dataFeeds[index - 1].dfWeight = newWeight;

        emit DataFeedsWeightSet(token, dfAddress, newWeight);
    }

    /**
     * @notice Batch set the weight for each (token, data feed)
     * @param tokens The list of addresses of the tokens
     * @param dfAddresses The list of data feed addresses
     * @param newWeights The list of new weights of the data feeds
     */
    function _setDataFeedsWeights(
        address[] calldata tokens,
        address[] calldata dfAddresses,
        uint88[] calldata newWeights
    ) private verifyLengths(tokens.length, dfAddresses.length) verifyLengths(tokens.length, newWeights.length) {
        for (uint256 i; i < tokens.length;) {
            _setDataFeedWeight(tokens[i], dfAddresses[i], newWeights[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove a data feed from a set, revert if it couldn't remove it
     * @dev Revert if the token's price is 0 after removing the data feed to prevent the other tokens
     * that use this token as a data feed to have a price of 0
     * @param token The address of the token
     * @param dfAddress The data feed address
     */
    function _removeDataFeed(address token, address dfAddress) private {
        if (!_removeFromSet(token, dfAddress)) {
            revert JoeDexLens__DataFeedNotInSet(token, dfAddress);
        }

        if (_getTokenWeightedAverageNativePrice(token) == 0) revert JoeDexLens__InvalidDataFeed();

        emit DataFeedRemoved(token, dfAddress);
    }

    /**
     * @notice Batch remove a list of data feeds for each (token, data feed)
     * @param tokens The list of addresses of the tokens
     * @param dfAddresses The list of USD data feed addresses
     */
    function _removeDataFeeds(address[] calldata tokens, address[] calldata dfAddresses)
        private
        verifyLengths(tokens.length, dfAddresses.length)
    {
        for (uint256 i; i < tokens.length;) {
            _removeDataFeed(tokens[i], dfAddresses[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set the native token's data feed
     * @param aggregator The address of the chainlink aggregator
     */
    function _setNativeDataFeed(address aggregator) private {
        if (_getDataFeedAt(_WNATIVE, 0).dfAddress == aggregator) revert JoeDexLens__SameDataFeed();

        DataFeed memory dataFeed = DataFeed(_WNATIVE, aggregator, 1, DataFeedType.CHAINLINK);
        _whitelistedDataFeeds[_WNATIVE].dataFeeds[0] = dataFeed;

        if (_getPriceFromChainlink(aggregator) == 0) revert JoeDexLens__InvalidChainLinkPrice();

        emit NativeDataFeedSet(aggregator);
    }

    /**
     * @notice Return the price of the native token
     * @dev The native token had to have a chainlink data feed set
     * @return price The price of the native token, with the native token's decimals
     */
    function _getNativePrice() private view returns (uint256 price) {
        return _getPriceFromChainlink(_getDataFeedAt(_WNATIVE, 0).dfAddress);
    }

    /**
     * @notice Return the weighted average native price of a token using its data feeds
     * @dev If no data feed was provided, will use `_getNativePriceAnyToken` to try to find a valid price
     * @param token The address of the token
     * @return price The weighted average price of the token, with the wnative's decimals
     */
    function _getTokenWeightedAverageNativePrice(address token) private view returns (uint256 price) {
        if (token == _WNATIVE) return _WNATIVE_PRECISION;

        uint256 length = _getDataFeedsLength(token);
        if (length == 0) return _getNativePriceAnyToken(token);

        uint256 totalWeights;

        for (uint256 i; i < length;) {
            DataFeed memory dataFeed = _getDataFeedAt(token, i);

            (uint256 dfPrice, uint256 dfWeight) = _getDataFeedPrice(dataFeed, token);

            if (dfPrice != 0) {
                price += dfPrice * dfWeight;
                unchecked {
                    totalWeights += dfWeight;
                }
            }

            unchecked {
                ++i;
            }
        }

        price = totalWeights == 0 ? 0 : price / totalWeights;
    }

    /**
     * @notice Return the price of a token using a specific datafeed, with wnative's decimals
     */
    function _getDataFeedPrice(DataFeed memory dataFeed, address token)
        private
        view
        returns (uint256 dfPrice, uint256 dfWeight)
    {
        DataFeedType dfType = dataFeed.dfType;

        if (dfType == DataFeedType.V1) {
            (,, dfPrice,) = _getPriceFromV1(dataFeed.dfAddress, token);
        } else if (dfType == DataFeedType.V2 || dfType == DataFeedType.V2_1) {
            (,, dfPrice,) = _getPriceFromLb(dataFeed.dfAddress, dfType, token);
        } else if (dfType == DataFeedType.CHAINLINK) {
            dfPrice = _getPriceFromChainlink(dataFeed.dfAddress);
        } else {
            revert JoeDexLens__UnknownDataFeedType();
        }

        if (dfPrice != 0) {
            if (dataFeed.collateralAddress != _WNATIVE) {
                uint256 collateralPrice = _getTokenWeightedAverageNativePrice(dataFeed.collateralAddress);
                dfPrice = dfPrice * collateralPrice / _WNATIVE_PRECISION;
            }

            dfWeight = dataFeed.dfWeight;
        }
    }

    /**
     * @notice Batch function to return the weighted average price of each tokens using its data feeds
     * @dev If no data feed was provided, will use `_getNativePriceAnyToken` to try to find a valid price
     * @param tokens The list of addresses of the tokens
     * @return prices The list of weighted average price of each token, with the wnative's decimals
     */
    function _getTokenWeightedAverageNativePrices(address[] calldata tokens)
        private
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length;) {
            prices[i] = _getTokenWeightedAverageNativePrice(tokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Return the price tracked by the aggreagator using chainlink's data feed, with wnative's decimals
     * @param dfAddress The address of the data feed
     * @return price The price tracked by the aggregator, with wnative's decimals
     */
    function _getPriceFromChainlink(address dfAddress) private view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(dfAddress);

        (, int256 sPrice,,,) = aggregator.latestRoundData();
        if (sPrice <= 0) revert JoeDexLens__InvalidChainLinkPrice();

        price = uint256(sPrice);

        uint256 aggregatorDecimals = aggregator.decimals();

        // Return the price with wnative's decimals
        if (aggregatorDecimals < _WNATIVE_DECIMALS) price *= 10 ** (_WNATIVE_DECIMALS - aggregatorDecimals);
        else if (aggregatorDecimals > _WNATIVE_DECIMALS) price /= 10 ** (aggregatorDecimals - _WNATIVE_DECIMALS);
    }

    /**
     * @notice Return the price of the token denominated in the second token of the V1 pair, with wnative's decimals
     * @dev The `token` token needs to be on of the two paired token of the given pair
     * @param pairAddress The address of the pair
     * @param token The address of the token
     * @return reserve0 The reserve of the first token of the pair
     * @return reserve1 The reserve of the second token of the pair
     * @return price The price of the token denominated in the second token of the pair, with wnative's decimals
     * @return isTokenX True if the token is the first token of the pair, false otherwise
     */
    function _getPriceFromV1(address pairAddress, address token)
        private
        view
        returns (uint256 reserve0, uint256 reserve1, uint256 price, bool isTokenX)
    {
        IJoePair pair = IJoePair(pairAddress);

        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 decimals0 = IERC20Metadata(token0).decimals();
        uint256 decimals1 = IERC20Metadata(token1).decimals();

        (reserve0, reserve1,) = pair.getReserves();
        isTokenX = token == token0;

        // Return the price with wnative's decimals
        if (isTokenX) {
            price =
                reserve0 == 0 ? 0 : (reserve1 * 10 ** (decimals0 + _WNATIVE_DECIMALS)) / (reserve0 * 10 ** decimals1);
        } else {
            price =
                reserve1 == 0 ? 0 : (reserve0 * 10 ** (decimals1 + _WNATIVE_DECIMALS)) / (reserve1 * 10 ** decimals0);
        }
    }

    /**
     * @notice Return the price of the token denominated in the second token of the LB pair, with wnative's decimals
     * @dev The `token` token needs to be on of the two paired token of the given pair
     * @param pair The address of the pair
     * @param dfType The type of the data feed
     * @param token The address of the token
     * @return activeId The active id of the pair
     * @return binStep The bin step of the pair
     * @return price The price of the token, with wnative's decimals
     * @return isTokenX True if the token is the first token of the pair, false otherwise
     */
    function _getPriceFromLb(address pair, DataFeedType dfType, address token)
        private
        view
        returns (uint24 activeId, uint16 binStep, uint256 price, bool isTokenX)
    {
        (address tokenX, address tokenY) = _getPairedTokens(pair, dfType);
        (activeId, binStep) = _getActiveIdAndBinStep(pair, dfType);

        uint256 priceScaled = activeId.getPriceFromId(binStep);

        uint256 decimalsX = IERC20Metadata(tokenX).decimals();
        uint256 decimalsY = IERC20Metadata(tokenY).decimals();

        uint256 precision;

        isTokenX = token == tokenX;

        (priceScaled, precision) = isTokenX
            ? (priceScaled, 10 ** (_WNATIVE_DECIMALS + decimalsX - decimalsY))
            : (type(uint256).max / priceScaled, 10 ** (_WNATIVE_DECIMALS + decimalsY - decimalsX));

        price = priceScaled.mulShiftRoundDown(precision, Constants.SCALE_OFFSET);
    }

    /**
     * @notice Return the addresses of the two tokens of a pair
     * @dev Work with both V1 or V2 pairs
     * @param pair The address of the pair
     * @param dfType The type of the pair, V1, V2 or V2.1
     * @return tokenA The address of the first token of the pair
     * @return tokenB The address of the second token of the pair
     */
    function _getPairedTokens(address pair, DataFeedType dfType)
        private
        view
        returns (address tokenA, address tokenB)
    {
        if (dfType == DataFeedType.V2_1) {
            tokenA = address(ILBPair(pair).getTokenX());
            tokenB = address(ILBPair(pair).getTokenY());
        } else if (dfType == DataFeedType.V2) {
            tokenA = address(ILBLegacyPair(pair).tokenX());
            tokenB = address(ILBLegacyPair(pair).tokenY());
        } else if (dfType == DataFeedType.V1) {
            tokenA = IJoePair(pair).token0();
            tokenB = IJoePair(pair).token1();
        } else {
            revert JoeDexLens__UnknownDataFeedType();
        }
    }

    /**
     * @notice Return the active id and the bin step of a pair
     * @dev Work with both V1 or V2 pairs
     * @param pair The address of the pair
     * @param dfType The type of the pair, V1, V2 or V2.1
     * @return activeId The active id of the pair
     * @return binStep The bin step of the pair
     */
    function _getActiveIdAndBinStep(address pair, DataFeedType dfType)
        private
        view
        returns (uint24 activeId, uint16 binStep)
    {
        if (dfType == DataFeedType.V2) {
            (,, uint256 aId) = ILBLegacyPair(pair).getReservesAndId();
            activeId = uint24(aId);

            binStep = uint16(ILBLegacyPair(pair).feeParameters().binStep);
        } else if (dfType == DataFeedType.V2_1) {
            activeId = ILBPair(pair).getActiveId();
            binStep = ILBPair(pair).getBinStep();
        } else {
            revert JoeDexLens__UnknownDataFeedType();
        }
    }

    /**
     * @notice Tries to find the price of the token on v2.1, v2 and v1 pairs.
     * V2.1 and v2 pairs are checked to have enough liquidity in them, to avoid pricing using stale pools
     * @dev Will return 0 if the token is not paired with wnative on any of the different versions
     * @param token The address of the token
     * @return price The weighted average, based on pair's liquidity, of the token with the collateral's decimals
     */
    function _getNativePriceAnyToken(address token) private view returns (uint256 price) {
        // First check the token price on v2.1
        (uint256 weightedPriceV2_1, uint256 totalWeightV2_1) = _v2_1FallbackNativePrice(token);

        // Then on v2
        (uint256 weightedPriceV2, uint256 totalWeightV2) = _v2FallbackNativePrice(token);

        // Then on v1
        (uint256 weightedPriceV1, uint256 totalWeightV1) = _v1FallbackNativePrice(token);

        uint256 totalWeight = totalWeightV2_1 + totalWeightV2 + totalWeightV1;
        return totalWeight == 0 ? 0 : (weightedPriceV2_1 + weightedPriceV2 + weightedPriceV1) / totalWeight;
    }

    /**
     * @notice Loops through all the wnative/token v2.1 pairs and returns the price of the token if a valid one was found
     * @param token The address of the token
     * @return weightedPrice The weighted price, based on the paired wnative's liquidity,
     * of the token with the collateral's decimals
     * @return totalWeight The total weight of the pairs
     */
    function _v2_1FallbackNativePrice(address token)
        private
        view
        returns (uint256 weightedPrice, uint256 totalWeight)
    {
        if (address(_FACTORY_V2_1) == address(0)) return (0, 0);

        ILBFactory.LBPairInformation[] memory lbPairsAvailable =
            _FACTORY_V2_1.getAllLBPairs(IERC20(_WNATIVE), IERC20(token));

        if (lbPairsAvailable.length != 0) {
            for (uint256 i = 0; i < lbPairsAvailable.length; i++) {
                address lbPair = address(lbPairsAvailable[i].LBPair);

                (uint24 activeId, uint16 binStep, uint256 price, bool isTokenX) =
                    _getPriceFromLb(lbPair, DataFeedType.V2_1, token);

                uint256 scaledReserves = _getLbBinReserves(lbPair, activeId, binStep, isTokenX);

                weightedPrice += price * scaledReserves;
                totalWeight += scaledReserves;
            }
        }
    }

    /**
     * @notice Loops through all the wnative/token v2 pairs and returns the price of the token if a valid one was found
     * @param token The address of the token
     * @return weightedPrice The weighted price, based on the paired wnative's liquidity,
     * of the token with the collateral's decimals
     * @return totalWeight The total weight of the pairs
     */
    function _v2FallbackNativePrice(address token) private view returns (uint256 weightedPrice, uint256 totalWeight) {
        if (address(_LEGACY_FACTORY_V2) == address(0)) return (0, 0);

        ILBLegacyFactory.LBPairInformation[] memory lbPairsAvailable =
            _LEGACY_FACTORY_V2.getAllLBPairs(IERC20(_WNATIVE), IERC20(token));

        if (lbPairsAvailable.length != 0) {
            for (uint256 i = 0; i < lbPairsAvailable.length; i++) {
                address lbPair = address(lbPairsAvailable[i].LBPair);

                (uint24 activeId, uint16 binStep, uint256 price, bool isTokenX) =
                    _getPriceFromLb(lbPair, DataFeedType.V2, token);

                uint256 scaledReserves = _getLbBinReserves(lbPair, activeId, binStep, isTokenX);

                weightedPrice += price * scaledReserves;
                totalWeight += scaledReserves;
            }
        }
    }

    /**
     * @notice Fetchs the wnative/token v1 pair and returns the price of the token if a valid one was found
     * @param token The address of the token
     * @return weightedPrice The weighted price, based on the paired wnative's liquidity,
     * of the token with the collateral's decimals
     * @return totalWeight The total weight of the pairs
     */
    function _v1FallbackNativePrice(address token) private view returns (uint256 weightedPrice, uint256 totalWeight) {
        if (address(_FACTORY_V1) == address(0)) return (0, 0);

        address pair = _FACTORY_V1.getPair(token, _WNATIVE);

        if (pair != address(0)) {
            (uint256 reserve0, uint256 reserve1, uint256 price, bool isTokenX) = _getPriceFromV1(pair, token);

            totalWeight = (isTokenX ? reserve1 : reserve0) * _BIN_WIDTH;
            weightedPrice = price * totalWeight;
        }
    }

    /**
     * @notice Get the scaled reserves of the bins that are close to the active bin, based on the bin step
     * and the wnative's reserves.
     * @dev Multiply the reserves by `20_000 / binStep` to get the scaled reserves and compare them to the
     * reserves of the V1 pair. This is an approximation of the price impact of the different versions.
     * @param lbPair The address of the liquidity book pair
     * @param activeId The active bin id
     * @param binStep The bin step
     * @param isTokenX Whether the token is token X or not
     * @return scaledReserves The scaled reserves of the pair, based on the bin step and the other token's reserves
     */
    function _getLbBinReserves(address lbPair, uint24 activeId, uint16 binStep, bool isTokenX)
        private
        view
        returns (uint256 scaledReserves)
    {
        if (isTokenX) {
            (uint256 start, uint256 end) = (activeId - _BIN_WIDTH + 1, activeId + 1);

            for (uint256 i = start; i < end;) {
                (, uint256 y) = ILBPair(lbPair).getBin(uint24(i));
                scaledReserves += y * _TWO_BASIS_POINT / binStep;

                unchecked {
                    ++i;
                }
            }
        } else {
            (uint256 start, uint256 end) = (activeId, activeId + _BIN_WIDTH);

            for (uint256 i = start; i < end;) {
                (uint256 x,) = ILBPair(lbPair).getBin(uint24(i));
                scaledReserves += x * _TWO_BASIS_POINT / binStep;

                unchecked {
                    ++i;
                }
            }
        }
    }
}

