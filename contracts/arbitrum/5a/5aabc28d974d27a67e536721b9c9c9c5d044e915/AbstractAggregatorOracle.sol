//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./IOracleAggregator.sol";
import "./AbstractOracle.sol";
import "./HistoricalOracle.sol";
import "./IOracle.sol";
import "./ExplicitQuotationMetadata.sol";
import "./IValidationStrategy.sol";

abstract contract AbstractAggregatorOracle is
    IOracleAggregator,
    AbstractOracle,
    HistoricalOracle,
    ExplicitQuotationMetadata
{
    struct TokenSpecificOracle {
        address token;
        address oracle;
    }

    /**
     * @notice An event emitted when data is aggregated.
     * @param token The token for which the data is aggregated.
     * @param tick The identifier of the aggregation iteration (i.e. timestamp) at which the data is aggregated.
     * @param numDataPoints The number of data points (i.e. underlying oracle responses) aggregated.
     */
    event AggregationPerformed(address indexed token, uint256 indexed tick, uint256 numDataPoints);

    IAggregationStrategy internal immutable generalAggregationStrategy;

    IValidationStrategy internal immutable generalValidationStrategy;

    /// @notice One whole unit of the quote token, in the quote token's smallest denomination.
    uint256 internal immutable _quoteTokenWholeUnit;

    uint8 internal immutable _liquidityDecimals;

    Oracle[] internal oracles;
    mapping(address => Oracle[]) internal tokenSpecificOracles;

    mapping(address => bool) private oracleExists;
    mapping(address => mapping(address => bool)) private oracleForExists;

    /// @notice Emitted when an underlying oracle (or this oracle) throws an update error with a reason.
    /// @param oracle The address or the oracle throwing the error.
    /// @param token The token for which the oracle is throwing the error.
    /// @param reason The reason for or description of the error.
    event UpdateErrorWithReason(address indexed oracle, address indexed token, string reason);

    /// @notice Emitted when an underlying oracle (or this oracle) throws an update error without a reason.
    /// @param oracle The address or the oracle throwing the error.
    /// @param token The token for which the oracle is throwing the error.
    /// @param err Data corresponding with a low level error being thrown.
    event UpdateError(address indexed oracle, address indexed token, bytes err);

    struct AbstractAggregatorOracleParams {
        IAggregationStrategy aggregationStrategy;
        IValidationStrategy validationStrategy;
        string quoteTokenName;
        address quoteTokenAddress;
        string quoteTokenSymbol;
        uint8 quoteTokenDecimals;
        uint8 liquidityDecimals;
        address[] oracles;
        TokenSpecificOracle[] tokenSpecificOracles;
    }

    constructor(
        AbstractAggregatorOracleParams memory params
    )
        HistoricalOracle(1)
        AbstractOracle(params.quoteTokenAddress)
        ExplicitQuotationMetadata(
            params.quoteTokenName,
            params.quoteTokenAddress,
            params.quoteTokenSymbol,
            params.quoteTokenDecimals
        )
    {
        if (
            address(params.validationStrategy) != address(0) &&
            params.validationStrategy.quoteTokenDecimals() != params.quoteTokenDecimals
        ) {
            revert("AbstractAggregatorOracle: QUOTE_TOKEN_DECIMALS_MISMATCH");
        }

        generalAggregationStrategy = params.aggregationStrategy;
        generalValidationStrategy = params.validationStrategy;

        _quoteTokenWholeUnit = 10 ** params.quoteTokenDecimals;

        _liquidityDecimals = params.liquidityDecimals;

        // Setup general oracles
        for (uint256 i = 0; i < params.oracles.length; ++i) {
            require(!oracleExists[params.oracles[i]], "AbstractAggregatorOracle: DUPLICATE_ORACLE");

            oracleExists[params.oracles[i]] = true;

            oracles.push(
                Oracle({
                    oracle: params.oracles[i],
                    priceDecimals: IOracle(params.oracles[i]).quoteTokenDecimals(),
                    liquidityDecimals: IOracle(params.oracles[i]).liquidityDecimals()
                })
            );
        }

        // Setup token-specific oracles
        for (uint256 i = 0; i < params.tokenSpecificOracles.length; ++i) {
            TokenSpecificOracle memory oracle = params.tokenSpecificOracles[i];

            require(!oracleExists[oracle.oracle], "AbstractAggregatorOracle: DUPLICATE_ORACLE");
            require(!oracleForExists[oracle.token][oracle.oracle], "AbstractAggregatorOracle: DUPLICATE_ORACLE");

            oracleForExists[oracle.token][oracle.oracle] = true;

            tokenSpecificOracles[oracle.token].push(
                Oracle({
                    oracle: oracle.oracle,
                    priceDecimals: IOracle(oracle.oracle).quoteTokenDecimals(),
                    liquidityDecimals: IOracle(oracle.oracle).liquidityDecimals()
                })
            );
        }
    }

    /// @inheritdoc IOracleAggregator
    function aggregationStrategy(address token) external view virtual override returns (IAggregationStrategy) {
        return _aggregationStrategy(token);
    }

    /// @inheritdoc IOracleAggregator
    function validationStrategy(address token) external view virtual override returns (IValidationStrategy) {
        return _validationStrategy(token);
    }

    /// @inheritdoc IOracleAggregator
    function getOracles(address token) external view virtual override returns (Oracle[] memory) {
        return _getOracles(token);
    }

    /// @inheritdoc IOracleAggregator
    function minimumResponses(address token) external view virtual override returns (uint256) {
        return _minimumResponses(token);
    }

    /// @inheritdoc IOracleAggregator
    function maximumResponseAge(address token) external view virtual override returns (uint256) {
        return _maximumResponseAge(token);
    }

    /// @inheritdoc ExplicitQuotationMetadata
    function quoteTokenName()
        public
        view
        virtual
        override(ExplicitQuotationMetadata, IQuoteToken, SimpleQuotationMetadata)
        returns (string memory)
    {
        return ExplicitQuotationMetadata.quoteTokenName();
    }

    /// @inheritdoc ExplicitQuotationMetadata
    function quoteTokenAddress()
        public
        view
        virtual
        override(ExplicitQuotationMetadata, IQuoteToken, SimpleQuotationMetadata)
        returns (address)
    {
        return ExplicitQuotationMetadata.quoteTokenAddress();
    }

    /// @inheritdoc ExplicitQuotationMetadata
    function quoteTokenSymbol()
        public
        view
        virtual
        override(ExplicitQuotationMetadata, IQuoteToken, SimpleQuotationMetadata)
        returns (string memory)
    {
        return ExplicitQuotationMetadata.quoteTokenSymbol();
    }

    /// @inheritdoc ExplicitQuotationMetadata
    function quoteTokenDecimals()
        public
        view
        virtual
        override(ExplicitQuotationMetadata, IQuoteToken, SimpleQuotationMetadata)
        returns (uint8)
    {
        return ExplicitQuotationMetadata.quoteTokenDecimals();
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ExplicitQuotationMetadata, AbstractOracle) returns (bool) {
        return
            interfaceId == type(IHistoricalOracle).interfaceId ||
            interfaceId == type(IOracleAggregator).interfaceId ||
            ExplicitQuotationMetadata.supportsInterface(interfaceId) ||
            AbstractOracle.supportsInterface(interfaceId);
    }

    function canUpdate(bytes memory data) public view virtual override returns (bool) {
        if (!needsUpdate(data)) {
            return false;
        }

        if (canUpdateUnderlyingOracles(data)) {
            return true;
        }

        address token = abi.decode(data, (address));

        (, uint256 validResponses) = aggregateUnderlying(token, _maximumResponseAge(token));

        // Only return true if we have reached the minimum number of valid underlying oracle consultations
        return validResponses >= _minimumResponses(token);
    }

    /// @inheritdoc IOracle
    function liquidityDecimals() public view virtual override returns (uint8) {
        return _liquidityDecimals;
    }

    function getLatestObservation(
        address token
    ) public view virtual override returns (ObservationLibrary.Observation memory observation) {
        BufferMetadata storage meta = observationBufferMetadata[token];

        if (meta.size == 0) {
            // If the buffer is empty, return the default observation
            return ObservationLibrary.Observation({price: 0, tokenLiquidity: 0, quoteTokenLiquidity: 0, timestamp: 0});
        }

        return observationBuffers[token][meta.end];
    }

    /// @notice Checks if any of the underlying oracles for the token need to be updated.
    /// @dev This function is used to determine if the aggregator can be updated by updating one of the underlying
    /// oracles. Please ensure updateUnderlyingOracles will update the underlying oracles if this function returns true.
    /// @param data The encoded token address, along with any additional data required by the oracle.
    /// @return True if any of the underlying oracles can be updated, false otherwise.
    function canUpdateUnderlyingOracles(bytes memory data) internal view virtual returns (bool) {
        address token = abi.decode(data, (address));

        // Ensure all underlying oracles are up-to-date
        Oracle[] memory theOracles = _getOracles(token);
        for (uint256 i = 0; i < theOracles.length; ++i) {
            if (IOracle(theOracles[i].oracle).canUpdate(data)) {
                // We can update one of the underlying oracles
                return true;
            }
        }

        return false;
    }

    /// @notice Updates the underlying oracles for the token.
    /// @dev This function is used to update the underlying oracles before consulting them.
    /// @param data The encoded token address, along with any additional data required by the oracle.
    /// @return True if any of the underlying oracles were updated, false otherwise.
    function updateUnderlyingOracles(bytes memory data) internal virtual returns (bool) {
        bool underlyingUpdated;
        address token = abi.decode(data, (address));

        // Ensure all underlying oracles are up-to-date
        Oracle[] memory theOracles = _getOracles(token);
        for (uint256 i = 0; i < theOracles.length; ++i) {
            // We don't want any problematic underlying oracles to prevent this oracle from updating
            // so we put update in a try-catch block
            try IOracle(theOracles[i].oracle).update(data) returns (bool updated) {
                underlyingUpdated = underlyingUpdated || updated;
            } catch Error(string memory reason) {
                emit UpdateErrorWithReason(theOracles[i].oracle, token, reason);
            } catch (bytes memory err) {
                emit UpdateError(theOracles[i].oracle, token, err);
            }
        }

        return underlyingUpdated;
    }

    function _getOracles(address token) internal view virtual returns (Oracle[] memory) {
        Oracle[] memory generalOracles = oracles;
        Oracle[] memory specificOracles = tokenSpecificOracles[token];

        uint256 generalOraclesCount = generalOracles.length;
        uint256 specificOraclesCount = specificOracles.length;

        Oracle[] memory allOracles = new Oracle[](generalOraclesCount + specificOraclesCount);

        // Add the general oracles
        for (uint256 i = 0; i < generalOraclesCount; ++i) allOracles[i] = generalOracles[i];

        // Add the token specific oracles
        for (uint256 i = 0; i < specificOraclesCount; ++i) allOracles[generalOraclesCount + i] = specificOracles[i];

        return allOracles;
    }

    function performUpdate(bytes memory data) internal virtual returns (bool) {
        bool underlyingUpdated = updateUnderlyingOracles(data);

        address token = abi.decode(data, (address));

        (ObservationLibrary.Observation memory observation, uint256 validResponses) = aggregateUnderlying(
            token,
            _maximumResponseAge(token)
        );

        if (validResponses >= _minimumResponses(token)) {
            emit AggregationPerformed(token, block.timestamp, validResponses);

            push(token, observation);

            return true;
        } else emit UpdateErrorWithReason(address(this), token, "AbstractAggregatorOracle: INVALID_NUM_CONSULTATIONS");

        return underlyingUpdated;
    }

    function _minimumResponses(address token) internal view virtual returns (uint256);

    function _maximumResponseAge(address token) internal view virtual returns (uint256);

    function _aggregationStrategy(address token) internal view virtual returns (IAggregationStrategy) {
        token; // silence unused variable warning. We let subclasses override this function to use the token parameter.

        return generalAggregationStrategy;
    }

    function _validationStrategy(address token) internal view virtual returns (IValidationStrategy) {
        token; // silence unused variable warning. We let subclasses override this function to use the token parameter.

        return generalValidationStrategy;
    }

    function aggregateUnderlying(
        address token,
        uint256 maxAge
    ) internal view virtual returns (ObservationLibrary.Observation memory result, uint256 validResponses) {
        uint256 pDecimals = quoteTokenDecimals();
        uint256 lDecimals = liquidityDecimals();

        Oracle[] memory theOracles = _getOracles(token);
        ObservationLibrary.MetaObservation[] memory observations = new ObservationLibrary.MetaObservation[](
            theOracles.length
        );

        uint256 oPrice;
        uint256 oTokenLiquidity;
        uint256 oQuoteTokenLiquidity;

        IValidationStrategy validation = _validationStrategy(token);

        for (uint256 i = 0; i < theOracles.length; ++i) {
            // We don't want problematic underlying oracles to prevent us from calculating the aggregated
            // results from the other working oracles, so we use a try-catch block.
            try IOracle(theOracles[i].oracle).consult(token, maxAge) returns (
                uint112 _price,
                uint112 _tokenLiquidity,
                uint112 _quoteTokenLiquidity
            ) {
                // Promote returned data to uint256 to prevent scaling up from overflowing
                oPrice = _price;
                oTokenLiquidity = _tokenLiquidity;
                oQuoteTokenLiquidity = _quoteTokenLiquidity;
            } catch Error(string memory) {
                continue;
            } catch (bytes memory) {
                continue;
            }

            // Fix differing quote token decimal places (for price)
            if (theOracles[i].priceDecimals < pDecimals) {
                // Scale up
                uint256 scalar = 10 ** (pDecimals - theOracles[i].priceDecimals);

                oPrice *= scalar;
            } else if (theOracles[i].priceDecimals > pDecimals) {
                // Scale down
                uint256 scalar = 10 ** (theOracles[i].priceDecimals - pDecimals);

                oPrice /= scalar;
            }

            // Fix differing liquidity decimal places
            if (theOracles[i].liquidityDecimals < lDecimals) {
                // Scale up
                uint256 scalar = 10 ** (lDecimals - theOracles[i].liquidityDecimals);

                oTokenLiquidity *= scalar;
                oQuoteTokenLiquidity *= scalar;
            } else if (theOracles[i].liquidityDecimals > lDecimals) {
                // Scale down
                uint256 scalar = 10 ** (theOracles[i].liquidityDecimals - lDecimals);

                oTokenLiquidity /= scalar;
                oQuoteTokenLiquidity /= scalar;
            }

            if (
                // Check that the values are not too large
                oPrice <= type(uint112).max &&
                oTokenLiquidity <= type(uint112).max &&
                oQuoteTokenLiquidity <= type(uint112).max
            ) {
                ObservationLibrary.MetaObservation memory observation;

                {
                    bytes memory updateData = abi.encode(token);
                    uint256 timestamp = IOracle(theOracles[i].oracle).lastUpdateTime(updateData);

                    observation = ObservationLibrary.MetaObservation({
                        metadata: ObservationLibrary.ObservationMetadata({oracle: theOracles[i].oracle}),
                        data: ObservationLibrary.Observation({
                            price: uint112(oPrice),
                            tokenLiquidity: uint112(oTokenLiquidity),
                            quoteTokenLiquidity: uint112(oQuoteTokenLiquidity),
                            timestamp: uint32(timestamp)
                        })
                    });
                }

                if (address(validation) == address(0) || validation.validateObservation(token, observation)) {
                    // The observation is valid, so we add it to the array
                    observations[validResponses++] = observation;
                }
            }
        }

        if (validResponses == 0) {
            return (
                ObservationLibrary.Observation({price: 0, tokenLiquidity: 0, quoteTokenLiquidity: 0, timestamp: 0}),
                0
            );
        }

        result = _aggregationStrategy(token).aggregateObservations(token, observations, 0, validResponses - 1);

        if (address(validation) != address(0)) {
            // Validate the aggregated result
            ObservationLibrary.MetaObservation memory metaResult = ObservationLibrary.MetaObservation({
                metadata: ObservationLibrary.ObservationMetadata({oracle: address(this)}),
                data: result
            });
            if (!validation.validateObservation(token, metaResult)) {
                return (
                    ObservationLibrary.Observation({price: 0, tokenLiquidity: 0, quoteTokenLiquidity: 0, timestamp: 0}),
                    0
                );
            }
        }
    }

    /// @inheritdoc AbstractOracle
    function instantFetch(
        address token
    ) internal view virtual override returns (uint112 price, uint112 tokenLiquidity, uint112 quoteTokenLiquidity) {
        (ObservationLibrary.Observation memory result, uint256 validResponses) = aggregateUnderlying(token, 0);

        uint256 minResponses = _minimumResponses(token);
        require(validResponses >= minResponses, "AbstractAggregatorOracle: INVALID_NUM_CONSULTATIONS");

        price = result.price;
        tokenLiquidity = result.tokenLiquidity;
        quoteTokenLiquidity = result.quoteTokenLiquidity;
    }
}

