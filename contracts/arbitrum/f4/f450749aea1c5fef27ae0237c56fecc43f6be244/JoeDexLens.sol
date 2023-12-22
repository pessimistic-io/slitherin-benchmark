// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Math512Bits.sol";
import "./Constants.sol";
import "./PendingOwnable.sol";
import "./ILBPair.sol";
import "./IJoePair.sol";
import "./IERC20Metadata.sol";

import "./IJoeDexLens.sol";

/// @title Joe Dex Lens
/// @author Trader Joe
/// @notice This contract allows to price tokens in either Native or USDC. It could be easily extended to any collateral.
/// Owners can add or remove data feeds to price a token and can set the weight of the different data feeds.
/// When no data feed is provided, the contract will use the TOKEN/WNative and TOKEN/USDC V1 pool to try to price the asset
contract JoeDexLens is PendingOwnable, IJoeDexLens {
    using Math512Bits for uint256;

    uint256 constant DECIMALS = 18;
    uint256 constant PRECISION = 10**DECIMALS;

    ILBRouter private immutable _ROUTER_V2;
    IJoeFactory private immutable _FACTORY_V1;

    address private immutable _WNATIVE;
    address private immutable _USDC;

    /// @dev Mapping from a collateral token to a token to an enumerable set of data feeds used to get the price of the token in collateral
    /// e.g. USDC => Native will return datafeeds to get the price of Native in USD
    /// And Native => JOE will return datafeeds to get the price of JOE in Native
    mapping(address => mapping(address => DataFeedSet)) private _whitelistedDataFeeds;

    /** Modifiers **/

    /// @notice Verify that the two lengths match
    /// @dev Revert if length are not equal
    /// @param _lengthA The length of the first list
    /// @param _lengthB The length of the second list
    modifier verifyLengths(uint256 _lengthA, uint256 _lengthB) {
        if (_lengthA != _lengthB) revert JoeDexLens__LengthsMismatch();
        _;
    }

    /// @notice Verify a data feed
    /// @dev Revert if :
    /// - The _collateral and the _token are the same address
    /// - The _collateral is not one of the two tokens of the pair (if the dfType is V1 or V2)
    /// - The _token is not one of the two tokens of the pair (if the dfType is V1 or V2)
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dataFeed The data feeds information
    modifier verifyDataFeed(
        address _collateral,
        address _token,
        DataFeed calldata _dataFeed
    ) {
        if (_collateral == _token) revert JoeDexLens__SameTokens();

        if (_dataFeed.dfType != dfType.CHAINLINK) {
            (address tokenA, address tokenB) = _getTokens(_dataFeed);

            if (tokenA != _collateral && tokenB != _collateral)
                revert JoeDexLens__CollateralNotInPair(_dataFeed.dfAddress, _collateral);
            if (tokenA != _token && tokenB != _token) revert JoeDexLens__TokenNotInPair(_dataFeed.dfAddress, _token);
        }
        _;
    }

    /// @notice Verify the weight for a data feed
    /// @dev Revert if the weight is equal to 0
    /// @param weight The weight of a data feed
    modifier verifyWeight(uint88 weight) {
        if (weight == 0) revert JoeDexLens__NullWeight();
        _;
    }

    /** Constructor **/

    constructor(
        ILBRouter _routerV2,
        IJoeFactory _factoryV1,
        address _wNative,
        address _usdc
    ) {
        _ROUTER_V2 = _routerV2;
        _FACTORY_V1 = _factoryV1;
        _WNATIVE = _wNative;
        _USDC = _usdc;
    }

    /** External View Functions **/

    /// @notice Returns the address of the router V2
    /// @return routerV2 The address of the router V2
    function getRouterV2() external view override returns (ILBRouter routerV2) {
        return _ROUTER_V2;
    }

    /// @notice Returns the address of the factory V1
    /// @return factoryV1 The address of the factory V1
    function getFactoryV1() external view override returns (IJoeFactory factoryV1) {
        return _FACTORY_V1;
    }

    /// @notice Returns the list of data feeds used to calculate the price of the token in USD
    /// @param _token The address of the token
    /// @return dataFeeds The array of data feeds used to price `token` in USD
    function getUSDDataFeeds(address _token) external view override returns (DataFeed[] memory dataFeeds) {
        return _whitelistedDataFeeds[_USDC][_token].dataFeeds;
    }

    /// @notice Returns the list of data feeds used to calculate the price of the token in Native
    /// @param _token The address of the token
    /// @return dataFeeds The array of data feeds used to price `token` in Native
    function getNativeDataFeeds(address _token) external view override returns (DataFeed[] memory dataFeeds) {
        return _whitelistedDataFeeds[_WNATIVE][_token].dataFeeds;
    }

    /// @notice Returns the price of token in USD, scaled with 6 decimals
    /// @param _token The address of the token
    /// @return price The price of the token in USD, with 6 decimals
    function getTokenPriceUSD(address _token) external view override returns (uint256 price) {
        return _getTokenWeightedAveragePrice(_USDC, _token);
    }

    /// @notice Returns the price of token in Native, scaled with `DECIMALS` decimals
    /// @param _token The address of the token
    /// @return price The price of the token in Native, with `DECIMALS` decimals
    function getTokenPriceNative(address _token) external view override returns (uint256 price) {
        return _getTokenWeightedAveragePrice(_WNATIVE, _token);
    }

    /// @notice Returns the prices of each token in USD, scaled with 6 decimals
    /// @param _tokens The list of address of the tokens
    /// @return prices The prices of each token in USD, with 6 decimals
    function getTokensPricesUSD(address[] calldata _tokens) external view override returns (uint256[] memory prices) {
        return _getTokenWeightedAveragePrices(_USDC, _tokens);
    }

    /// @notice Returns the prices of each token in Native, scaled with `DECIMALS` decimals
    /// @param _tokens The list of address of the tokens
    /// @return prices The prices of each token in Native, with `DECIMALS` decimals
    function getTokensPricesNative(address[] calldata _tokens)
        external
        view
        override
        returns (uint256[] memory prices)
    {
        return _getTokenWeightedAveragePrices(_WNATIVE, _tokens);
    }

    /** Owner Functions **/

    /// @notice Add a USD data feed for a specific token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dataFeed The USD data feeds information
    function addUSDDataFeed(address _token, DataFeed calldata _dataFeed) external override onlyOwner {
        _addDataFeed(_USDC, _token, _dataFeed);
    }

    /// @notice Add a Native data feed for a specific token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dataFeed The Native data feeds information
    function addNativeDataFeed(address _token, DataFeed calldata _dataFeed) external override onlyOwner {
        _addDataFeed(_WNATIVE, _token, _dataFeed);
    }

    /// @notice Set the USD weight for a specific data feed of a token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dfAddress The USD data feed address
    /// @param _newWeight The new weight of the data feed
    function setUSDDataFeedWeight(
        address _token,
        address _dfAddress,
        uint88 _newWeight
    ) external override onlyOwner {
        _setDataFeedWeight(_USDC, _token, _dfAddress, _newWeight);
    }

    /// @notice Set the Native weight for a specific data feed of a token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    /// @param _newWeight The new weight of the data feed
    function setNativeDataFeedWeight(
        address _token,
        address _dfAddress,
        uint88 _newWeight
    ) external override onlyOwner {
        _setDataFeedWeight(_WNATIVE, _token, _dfAddress, _newWeight);
    }

    /// @notice Remove a USD data feed of a token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dfAddress The USD data feed address
    function removeUSDDataFeed(address _token, address _dfAddress) external override onlyOwner {
        _removeDataFeed(_USDC, _token, _dfAddress);
    }

    /// @notice Remove a Native data feed of a token
    /// @dev Can only be called by the owner
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    function removeNativeDataFeed(address _token, address _dfAddress) external override onlyOwner {
        _removeDataFeed(_WNATIVE, _token, _dfAddress);
    }

    /// @notice Batch add USD data feed for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The addresses of the tokens
    /// @param _dataFeeds The list of USD data feeds informations
    function addUSDDataFeeds(address[] calldata _tokens, DataFeed[] calldata _dataFeeds) external override onlyOwner {
        _addDataFeeds(_USDC, _tokens, _dataFeeds);
    }

    /// @notice Batch add Native data feed for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The addresses of the tokens
    /// @param _dataFeeds The list of Native data feeds informations
    function addNativeDataFeeds(address[] calldata _tokens, DataFeed[] calldata _dataFeeds)
        external
        override
        onlyOwner
    {
        _addDataFeeds(_WNATIVE, _tokens, _dataFeeds);
    }

    /// @notice Batch set the USD weight for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of USD data feed addresses
    /// @param _newWeights The list of new weights of the data feeds
    function setUSDDataFeedsWeights(
        address[] calldata _tokens,
        address[] calldata _dfAddresses,
        uint88[] calldata _newWeights
    ) external override onlyOwner {
        _setDataFeedsWeights(_USDC, _tokens, _dfAddresses, _newWeights);
    }

    /// @notice Batch set the Native weight for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of Native data feed addresses
    /// @param _newWeights The list of new weights of the data feeds
    function setNativeDataFeedsWeights(
        address[] calldata _tokens,
        address[] calldata _dfAddresses,
        uint88[] calldata _newWeights
    ) external override onlyOwner {
        _setDataFeedsWeights(_WNATIVE, _tokens, _dfAddresses, _newWeights);
    }

    /// @notice Batch remove a list of USD data feeds for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of USD data feed addresses
    function removeUSDDataFeeds(address[] calldata _tokens, address[] calldata _dfAddresses)
        external
        override
        onlyOwner
    {
        _removeDataFeeds(_USDC, _tokens, _dfAddresses);
    }

    /// @notice Batch remove a list of Native data feeds for each (token, data feed)
    /// @dev Can only be called by the owner
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of Native data feed addresses
    function removeNativeDataFeeds(address[] calldata _tokens, address[] calldata _dfAddresses)
        external
        override
        onlyOwner
    {
        _removeDataFeeds(_WNATIVE, _tokens, _dfAddresses);
    }

    /** Private Functions **/

    /// @notice Returns the data feed length for a specific collateral and a token
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @return length The number of data feeds
    function _getDataFeedsLength(address _collateral, address _token) private view returns (uint256 length) {
        return _whitelistedDataFeeds[_collateral][_token].dataFeeds.length;
    }

    /// @notice Returns the data feed at index `_index` for a specific collateral and a token
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _index The index
    /// @return dataFeed the data feed at index `_index`
    function _getDataFeedAt(
        address _collateral,
        address _token,
        uint256 _index
    ) private view returns (DataFeed memory dataFeed) {
        return _whitelistedDataFeeds[_collateral][_token].dataFeeds[_index];
    }

    /// @notice Returns if a (tokens)'s set contains the data feed address
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    /// @return Whether the set contains the data feed address (true) or not (false)
    function _dataFeedContains(
        address _collateral,
        address _token,
        address _dfAddress
    ) private view returns (bool) {
        return _whitelistedDataFeeds[_collateral][_token].indexes[_dfAddress] != 0;
    }

    /// @notice Add a data feed to a set, return true if it was added, false if not
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dataFeed The data feeds information
    /// @return Whether the data feed was added (true) to the set or not (false)
    function _addToSet(
        address _collateral,
        address _token,
        DataFeed calldata _dataFeed
    ) private returns (bool) {
        if (!_dataFeedContains(_collateral, _token, _dataFeed.dfAddress)) {
            DataFeedSet storage set = _whitelistedDataFeeds[_collateral][_token];

            set.dataFeeds.push(_dataFeed);
            set.indexes[_dataFeed.dfAddress] = set.dataFeeds.length;
            return true;
        } else {
            return false;
        }
    }

    /// @notice Remove a data feed from a set, returns true if it was removed, false if not
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    /// @return Whether the data feed was removed (true) from the set or not (false)
    function _removeFromSet(
        address _collateral,
        address _token,
        address _dfAddress
    ) private returns (bool) {
        DataFeedSet storage set = _whitelistedDataFeeds[_collateral][_token];
        uint256 dataFeedIndex = set.indexes[_dfAddress];

        if (dataFeedIndex != 0) {
            uint256 toDeleteIndex = dataFeedIndex - 1;
            uint256 lastIndex = set.dataFeeds.length - 1;

            if (toDeleteIndex != lastIndex) {
                DataFeed memory lastDataFeed = set.dataFeeds[lastIndex];

                set.dataFeeds[toDeleteIndex] = lastDataFeed;
                set.indexes[lastDataFeed.dfAddress] = dataFeedIndex;
            }

            set.dataFeeds.pop();
            delete set.indexes[_dfAddress];

            return true;
        } else {
            return false;
        }
    }

    /// @notice Add a data feed to a set, revert if it couldn't add it
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dataFeed The data feeds information
    function _addDataFeed(
        address _collateral,
        address _token,
        DataFeed calldata _dataFeed
    ) private verifyDataFeed(_collateral, _token, _dataFeed) verifyWeight(_dataFeed.dfWeight) {
        if (!_addToSet(_collateral, _token, _dataFeed))
            revert JoeDexLens__DataFeedAlreadyAdded(_collateral, _token, _dataFeed.dfAddress);

        emit DataFeedAdded(_collateral, _token, _dataFeed);
    }

    /// @notice Batch add data feed for each (_collateral, token, data feed)
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _tokens The addresses of the tokens
    /// @param _dataFeeds The list of USD data feeds informations
    function _addDataFeeds(
        address _collateral,
        address[] calldata _tokens,
        DataFeed[] calldata _dataFeeds
    ) private verifyLengths(_tokens.length, _dataFeeds.length) {
        for (uint256 i; i < _tokens.length; ) {
            _addDataFeed(_collateral, _tokens[i], _dataFeeds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Set the weight for a specific data feed of a (collateral, token)
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    /// @param _newWeight The new weight of the data feed
    function _setDataFeedWeight(
        address _collateral,
        address _token,
        address _dfAddress,
        uint88 _newWeight
    ) private verifyWeight(_newWeight) {
        DataFeedSet storage set = _whitelistedDataFeeds[_collateral][_token];

        uint256 index = set.indexes[_dfAddress];

        if (index == 0) revert JoeDexLens__DataFeedNotInSet(_collateral, _token, _dfAddress);

        set.dataFeeds[index - 1].dfWeight = _newWeight;

        emit DataFeedsWeightSet(_collateral, _token, _dfAddress, _newWeight);
    }

    /// @notice Batch set the weight for each (_collateral, token, data feed)
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of USD data feed addresses
    /// @param _newWeights The list of new weights of the data feeds
    function _setDataFeedsWeights(
        address _collateral,
        address[] calldata _tokens,
        address[] calldata _dfAddresses,
        uint88[] calldata _newWeights
    ) private verifyLengths(_tokens.length, _dfAddresses.length) verifyLengths(_tokens.length, _newWeights.length) {
        for (uint256 i; i < _tokens.length; ) {
            _setDataFeedWeight(_collateral, _tokens[i], _dfAddresses[i], _newWeights[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Remove a data feed from a set, revert if it couldn't remove it
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @param _dfAddress The data feed address
    function _removeDataFeed(
        address _collateral,
        address _token,
        address _dfAddress
    ) private {
        if (!_removeFromSet(_collateral, _token, _dfAddress))
            revert JoeDexLens__DataFeedNotInSet(_collateral, _token, _dfAddress);

        emit DataFeedRemoved(_collateral, _token, _dfAddress);
    }

    /// @notice Batch remove a list of collateral data feeds for each (token, data feed)
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _tokens The list of addresses of the tokens
    /// @param _dfAddresses The list of USD data feed addresses
    function _removeDataFeeds(
        address _collateral,
        address[] calldata _tokens,
        address[] calldata _dfAddresses
    ) private verifyLengths(_tokens.length, _dfAddresses.length) {
        for (uint256 i; i < _tokens.length; ) {
            _removeDataFeed(_collateral, _tokens[i], _dfAddresses[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Return the weighted average price of a token using its collateral data feeds
    /// @dev If no data feed was provided, will use V1 TOKEN/Native and USDC/TOKEN pools to calculate the price of the token
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @return price The weighted average price of the token, with the collateral's decimals
    function _getTokenWeightedAveragePrice(address _collateral, address _token) private view returns (uint256 price) {
        uint256 decimals = IERC20Metadata(_collateral).decimals();
        if (_collateral == _token) return 10**decimals;

        uint256 length = _getDataFeedsLength(_collateral, _token);
        if (length == 0) return _getPriceAnyToken(_collateral, _token);

        uint256 dfPrice;
        uint256 totalWeights;
        for (uint256 i; i < length; ) {
            DataFeed memory dataFeed = _getDataFeedAt(_collateral, _token, i);

            if (dataFeed.dfType == dfType.V1) {
                dfPrice = _getPriceFromV1(dataFeed.dfAddress, _token);
            } else if (dataFeed.dfType == dfType.V2) {
                dfPrice = _getPriceFromV2(dataFeed.dfAddress, _token);
            } else if (dataFeed.dfType == dfType.CHAINLINK) {
                dfPrice = _getPriceFromChainlink(dataFeed.dfAddress);
            } else revert JoeDexLens__UnknownDataFeedType();

            price += dfPrice * dataFeed.dfWeight;
            totalWeights += dataFeed.dfWeight;

            unchecked {
                ++i;
            }
        }

        price /= totalWeights;

        // Return the price with the collateral's decimals
        if (decimals < DECIMALS) price /= 10**(DECIMALS - decimals);
        else if (decimals > DECIMALS) price *= 10**(decimals - DECIMALS);
    }

    /// @notice Batch function to return the weighted average price of each tokens using its collateral data feeds
    /// @dev If no data feed was provided, will use V1 TOKEN/Native and USDC/TOKEN pools to calculate the price of the token
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _tokens The list of addresses of the tokens
    /// @return prices The list of weighted average price of each token, with the collateral's decimals
    function _getTokenWeightedAveragePrices(address _collateral, address[] calldata _tokens)
        private
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            prices[i] = _getTokenWeightedAveragePrice(_collateral, _tokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Return the price tracked by the aggreagator using chainlink's data feed, with `DECIMALS` decimals
    /// @param _dfAddress The address of the data feed
    /// @return price The price tracked by the aggreagator, with `DECIMALS` decimals
    function _getPriceFromChainlink(address _dfAddress) private view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(_dfAddress);

        (, int256 sPrice, , , ) = aggregator.latestRoundData();
        if (sPrice <= 0) revert JoeDexLens__InvalidChainLinkPrice();

        price = uint256(sPrice);

        uint256 aggregatorDecimals = aggregator.decimals();

        // Return the price with `DECIMALS` decimals
        if (aggregatorDecimals < DECIMALS) price *= 10**(DECIMALS - aggregatorDecimals);
        else if (aggregatorDecimals > DECIMALS) price /= 10**(aggregatorDecimals - DECIMALS);
    }

    /// @notice Return the price of the token denominated in the second token of the V1 pair, with `DECIMALS` decimals
    /// @dev The `token` token needs to be on of the two paired token of the given pair
    /// @param _pairAddress The address of the pair
    /// @param _token The address of the token
    /// @return price The price of the token, with `DECIMALS` decimals
    function _getPriceFromV1(address _pairAddress, address _token) private view returns (uint256 price) {
        IJoePair pair = IJoePair(_pairAddress);

        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 decimals0 = IERC20Metadata(token0).decimals();
        uint256 decimals1 = IERC20Metadata(token1).decimals();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        // Return the price with `DECIMALS` decimals
        if (_token == token0) {
            return (reserve1 * 10**(decimals0 + DECIMALS)) / (reserve0 * 10**decimals1);
        } else if (_token == token1) {
            return (reserve0 * 10**(decimals1 + DECIMALS)) / (reserve1 * 10**decimals0);
        } else revert JoeDexLens__WrongPair();
    }

    /// @notice Return the price of the token denominated in the second token of the V2 pair, with `DECIMALS` decimals
    /// @dev The `token` token needs to be on of the two paired token of the given pair
    /// @param _pairAddress The address of the pair
    /// @param _token The address of the token
    /// @return price The price of the token, with `DECIMALS` decimals
    function _getPriceFromV2(address _pairAddress, address _token) private view returns (uint256 price) {
        ILBPair pair = ILBPair(_pairAddress);

        (, , uint256 activeID) = pair.getReservesAndId();
        uint256 priceScaled = _ROUTER_V2.getPriceFromId(pair, uint24(activeID));

        address tokenX = address(pair.tokenX());
        address tokenY = address(pair.tokenY());

        uint256 decimalsX = IERC20Metadata(tokenX).decimals();
        uint256 decimalsY = IERC20Metadata(tokenY).decimals();

        // Return the price with `DECIMALS` decimals
        if (_token == tokenX) {
            return priceScaled.mulShiftRoundDown(10**(18 + decimalsX - decimalsY), Constants.SCALE_OFFSET);
        } else if (_token == tokenY) {
            return
                (type(uint256).max / priceScaled).mulShiftRoundDown(
                    10**(18 + decimalsY - decimalsX),
                    Constants.SCALE_OFFSET
                );
        } else revert JoeDexLens__WrongPair();
    }

    /// @notice Return the addresses of the two tokens of a pair
    /// @dev Work with both V1 or V2 pairs
    /// @param _dataFeed The data feeds information
    /// @return tokenA The address of the first token of the pair
    /// @return tokenB The address of the second token of the pair
    function _getTokens(DataFeed calldata _dataFeed) private view returns (address tokenA, address tokenB) {
        if (_dataFeed.dfType == dfType.V1) {
            IJoePair pair = IJoePair(_dataFeed.dfAddress);

            tokenA = pair.token0();
            tokenB = pair.token1();
        } else if (_dataFeed.dfType == dfType.V2) {
            ILBPair pair = ILBPair(_dataFeed.dfAddress);

            tokenA = address(pair.tokenX());
            tokenB = address(pair.tokenY());
        } else revert JoeDexLens__UnknownDataFeedType();
    }

    /// @notice Return the price of a token using TOKEN/Native and TOKEN/USDC V1 pairs, with `DECIMALS` decimals
    /// @dev If only one pair is available, will return the price on this pair, and will revert if no pools were created
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _token The address of the token
    /// @return price The weighted average, based on pair's liquidity, of the token with the collateral's decimals
    function _getPriceAnyToken(address _collateral, address _token) private view returns (uint256 price) {
        address pairTokenWNative = _FACTORY_V1.getPair(_token, _WNATIVE);
        address pairTokenUsdc = _FACTORY_V1.getPair(_token, _USDC);

        if (pairTokenWNative != address(0) && pairTokenUsdc != address(0)) {
            uint256 priceOfNative = _getTokenWeightedAveragePrice(_collateral, _WNATIVE);
            uint256 priceOfUSDC = _getTokenWeightedAveragePrice(_collateral, _USDC);

            uint256 priceInUSDC = _getPriceFromV1(pairTokenUsdc, _token);
            uint256 priceInNative = _getPriceFromV1(pairTokenWNative, _token);

            uint256 totalReserveInUSDC = _getReserveInTokenAFromV1(pairTokenUsdc, _USDC, _token);
            uint256 totalReserveinWNative = _getReserveInTokenAFromV1(pairTokenWNative, _WNATIVE, _token);

            uint256 weightUSDC = (totalReserveInUSDC * priceOfUSDC) / PRECISION;
            uint256 weightWNative = (totalReserveinWNative * priceOfNative) / PRECISION;

            uint256 totalWeights;
            uint256 weightedPriceUSDC = (priceInUSDC * priceOfUSDC * weightUSDC) / PRECISION;
            if (weightedPriceUSDC != 0) totalWeights += weightUSDC;

            uint256 weightedPriceNative = (priceInNative * priceOfNative * weightWNative) / PRECISION;
            if (weightedPriceNative != 0) totalWeights += weightWNative;

            if (totalWeights == 0) revert JoeDexLens__NotEnoughLiquidity();

            return (weightedPriceUSDC + weightedPriceNative) / totalWeights;
        } else if (pairTokenWNative != address(0)) {
            return _getPriceInCollateralFromV1(_collateral, pairTokenWNative, _WNATIVE, _token);
        } else if (pairTokenUsdc != address(0)) {
            return _getPriceInCollateralFromV1(_collateral, pairTokenUsdc, _USDC, _token);
        } else revert JoeDexLens__PairsNotCreated();
    }

    /// @notice Return the price in collateral of a token from a V1 pair
    /// @param _collateral The address of the collateral (USDC or WNATIVE)
    /// @param _pairAddress The address of the V1 pair
    /// @param _tokenBase The address of the base token of the pair, i.e. the collateral one
    /// @param _token The address of the token
    /// @return priceInCollateral The price of the token in collateral, with the collateral's decimals
    function _getPriceInCollateralFromV1(
        address _collateral,
        address _pairAddress,
        address _tokenBase,
        address _token
    ) private view returns (uint256 priceInCollateral) {
        uint256 priceInBase = _getPriceFromV1(_pairAddress, _token);
        uint256 priceOfBase = _getTokenWeightedAveragePrice(_collateral, _tokenBase);

        // Return the price with the collateral's decimals
        return (priceInBase * priceOfBase) / PRECISION;
    }

    /// @notice Return the entire TVL of a pair in token A, with `DECIMALS` decimals
    /// @dev tokenA and tokenB needs to be the two tokens paired in the given pair
    /// @param _pairAddress The address of the pair
    /// @param _tokenA The address of one of the pair's token
    /// @param _tokenB The address of the other pair's token
    /// @return totalReserveInTokenA The total reserve of the pool in token A
    function _getReserveInTokenAFromV1(
        address _pairAddress,
        address _tokenA,
        address _tokenB
    ) private view returns (uint256 totalReserveInTokenA) {
        IJoePair pair = IJoePair(_pairAddress);

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint8 decimals = IERC20Metadata(_tokenA).decimals();

        if (_tokenA < _tokenB) totalReserveInTokenA = reserve0 * 2;
        else totalReserveInTokenA = reserve1 * 2;

        if (decimals < DECIMALS) totalReserveInTokenA *= 10**(DECIMALS - decimals);
        else if (decimals > DECIMALS) totalReserveInTokenA /= 10**(decimals - DECIMALS);
    }
}

