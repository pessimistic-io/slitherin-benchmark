//SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "./IERC20Metadata.sol";
import "./IERC165.sol";

import "./IOracle.sol";
import "./ObservationLibrary.sol";
import "./SimpleQuotationMetadata.sol";

abstract contract AbstractOracle is IERC165, IOracle, SimpleQuotationMetadata {
    constructor(address quoteToken_) SimpleQuotationMetadata(quoteToken_) {}

    /// @param data The encoded address of the token for which to perform the update.
    /// @inheritdoc IUpdateable
    function update(bytes memory data) public virtual override returns (bool);

    /// @param data The encoded address of the token for which to perform the update.
    /// @inheritdoc IUpdateable
    function needsUpdate(bytes memory data) public view virtual override returns (bool);

    /// @param data The encoded address of the token for which to perform the update.
    /// @inheritdoc IUpdateable
    function canUpdate(bytes memory data) public view virtual override returns (bool);

    function getLatestObservation(
        address token
    ) public view virtual returns (ObservationLibrary.Observation memory observation);

    /// @param data The encoded address of the token for which the update relates to.
    /// @inheritdoc IUpdateable
    function lastUpdateTime(bytes memory data) public view virtual override returns (uint256) {
        address token = abi.decode(data, (address));

        return getLatestObservation(token).timestamp;
    }

    /// @param data The encoded address of the token for which the update relates to.
    /// @inheritdoc IUpdateable
    function timeSinceLastUpdate(bytes memory data) public view virtual override returns (uint256) {
        return block.timestamp - lastUpdateTime(data);
    }

    function consultPrice(address token) public view virtual override returns (uint112 price) {
        if (token == quoteTokenAddress()) return uint112(10 ** quoteTokenDecimals());

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");

        return observation.price;
    }

    /// @inheritdoc IPriceOracle
    function consultPrice(address token, uint256 maxAge) public view virtual override returns (uint112 price) {
        if (token == quoteTokenAddress()) return uint112(10 ** quoteTokenDecimals());

        if (maxAge == 0) {
            (price, , ) = instantFetch(token);

            return price;
        }

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");
        require(block.timestamp <= observation.timestamp + maxAge, "AbstractOracle: RATE_TOO_OLD");

        return observation.price;
    }

    /// @inheritdoc ILiquidityOracle
    function consultLiquidity(
        address token
    ) public view virtual override returns (uint112 tokenLiquidity, uint112 quoteTokenLiquidity) {
        if (token == quoteTokenAddress()) return (0, 0);

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");

        tokenLiquidity = observation.tokenLiquidity;
        quoteTokenLiquidity = observation.quoteTokenLiquidity;
    }

    /// @inheritdoc ILiquidityOracle
    function consultLiquidity(
        address token,
        uint256 maxAge
    ) public view virtual override returns (uint112 tokenLiquidity, uint112 quoteTokenLiquidity) {
        if (token == quoteTokenAddress()) return (0, 0);

        if (maxAge == 0) {
            (, tokenLiquidity, quoteTokenLiquidity) = instantFetch(token);

            return (tokenLiquidity, quoteTokenLiquidity);
        }

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");
        require(block.timestamp <= observation.timestamp + maxAge, "AbstractOracle: RATE_TOO_OLD");

        tokenLiquidity = observation.tokenLiquidity;
        quoteTokenLiquidity = observation.quoteTokenLiquidity;
    }

    /// @inheritdoc IOracle
    function consult(
        address token
    ) public view virtual override returns (uint112 price, uint112 tokenLiquidity, uint112 quoteTokenLiquidity) {
        if (token == quoteTokenAddress()) return (uint112(10 ** quoteTokenDecimals()), 0, 0);

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");

        price = observation.price;
        tokenLiquidity = observation.tokenLiquidity;
        quoteTokenLiquidity = observation.quoteTokenLiquidity;
    }

    /// @inheritdoc IOracle
    function consult(
        address token,
        uint256 maxAge
    ) public view virtual override returns (uint112 price, uint112 tokenLiquidity, uint112 quoteTokenLiquidity) {
        if (token == quoteTokenAddress()) return (uint112(10 ** quoteTokenDecimals()), 0, 0);

        if (maxAge == 0) return instantFetch(token);

        ObservationLibrary.Observation memory observation = getLatestObservation(token);

        require(observation.timestamp != 0, "AbstractOracle: MISSING_OBSERVATION");
        require(block.timestamp <= observation.timestamp + maxAge, "AbstractOracle: RATE_TOO_OLD");

        price = observation.price;
        tokenLiquidity = observation.tokenLiquidity;
        quoteTokenLiquidity = observation.quoteTokenLiquidity;
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(SimpleQuotationMetadata, IERC165) returns (bool) {
        return
            interfaceId == type(IOracle).interfaceId ||
            interfaceId == type(IUpdateable).interfaceId ||
            interfaceId == type(IPriceOracle).interfaceId ||
            interfaceId == type(ILiquidityOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Fetches the instant rates as of the latest block, straight from the source.
     * @dev This is costly in gas and the rates are easier to manipulate.
     * @param token The token to get the rates for.
     * @return price The quote token denominated price for a whole token.
     * @return tokenLiquidity The amount of the token that is liquid in the underlying pool, in wei.
     * @return quoteTokenLiquidity The amount of the quote token that is liquid in the underlying pool, in wei.
     */
    function instantFetch(
        address token
    ) internal view virtual returns (uint112 price, uint112 tokenLiquidity, uint112 quoteTokenLiquidity);
}

