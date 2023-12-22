pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/TokenPrices.sol)

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {Math} from "./Math.sol";

import {IAggregatorV3Interface} from "./IAggregatorV3Interface.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IJoeLBQuoter} from "./IJoeLBQuoter.sol";

import {ITokenPrices} from "./ITokenPrices.sol";
import {IRepricingToken} from "./IRepricingToken.sol";

/// @title Token Prices
/// @notice A utility contract to pull token prices on-chain.
/// @dev Composable functions (using encoded function calldata) to build up price formulas
/// Do NOT use these prices for direct on-chain purposes, as they can generally be abused.
/// eg single block sandwich attacks, multi-block attacks by block producers, etc.
/// They are only to be used for utilities such as showing estimated $USD equiv. prices in a dapp, etc
contract TokenPrices is ITokenPrices, Ownable {
    uint8 public immutable override decimals;
    
    /// @notice Token address to function calldata for how to lookup the price for this token
    mapping(address => bytes) public priceFnCalldata;

    error InvalidPrice(int256);
    error FailedPriceLookup(bytes fnCalldata);
    event TokenPriceFunctionSet(address indexed token, bytes fnCalldata);

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    /// @notice Map a token address to a function calldata defining how to retrieve the price
    function setTokenPriceFunction(address token, bytes calldata fnCalldata) external onlyOwner {
        emit TokenPriceFunctionSet(token, fnCalldata);
        priceFnCalldata[token] = fnCalldata;
    }

    /** TOKEN->PRICE LOOKUP FUNCTIONS */

    /// @notice Retrieve the price for a given token.
    /// @dev If not mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    function tokenPrice(address token) public override view returns (uint256 price) {
        return runPriceFunction(priceFnCalldata[token]);
    }

    /// @notice Retrieve the price for a list of tokens.
    /// @dev If any aren't mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    /// Not particularly gas efficient - wouldn't recommend to use on-chain
    function tokenPrices(address[] memory tokens) external override view returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            prices[i] = runPriceFunction(priceFnCalldata[tokens[i]]);
        }
    }

    /** EXTERNAL PRICE LOOKUPS */

    /// @notice Lookup the price of an oracle, scaled to `pricePrecision`
    function oraclePrice(address _oracle, uint256 _stalenessThreshold) external view returns (uint256 price) {
        IAggregatorV3Interface oracle = IAggregatorV3Interface(_oracle);
        (uint80 roundId, int256 feedValue, , uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
		if (answeredInRound <= roundId && block.timestamp - updatedAt > _stalenessThreshold) revert InvalidPrice(feedValue);

        if (feedValue < 0) revert InvalidPrice(feedValue);
        price = scaleToPrecision(uint256(feedValue), oracle.decimals());
    }

    /// @notice Fetch the Trader Joe pair price, not inclusive of swap fees or price impact.
    /// @dev Do not use this for on-chain calculations, as it can be exploited 
    /// with a single block sandwhich attack. Only use for off-chain utilities (eg informational purposes only)
    function traderJoeBestPrice(IJoeLBQuoter joeQuoter, address sellToken, address buyToken) external view returns (uint256) {
        address[] memory route = new address[](2);
        route[0] = sellToken;
        route[1] = buyToken;
        uint8 buyTokenDecimals = ERC20(buyToken).decimals();
        uint8 sellTokenDecimals = ERC20(sellToken).decimals();

        // Get the quote details to sell 1 token, across all v1 and v2 pools
        IJoeLBQuoter.Quote memory quote = joeQuoter.findBestPathFromAmountIn(route, 10 ** sellTokenDecimals);

        // Scale to 1e30.
        uint256 sellTokenAmount = scaleToPrecision(quote.virtualAmountsWithoutSlippage[0], sellTokenDecimals);
        uint256 sellTokenFeeAmount = sellTokenAmount * quote.fees[0] / 1e18; // fees are a percentage of the sell token amount
        uint256 buyTokenAmount = scaleToPrecision(quote.virtualAmountsWithoutSlippage[1], buyTokenDecimals);

        return buyTokenAmount * 10 ** decimals / (sellTokenAmount - sellTokenFeeAmount);
    }

    /// @notice Fetch the price from a univ3 pool, in quoted order (token0Price), to `pricePrecision`
    /// @dev https://web.archive.org/web/20210918154903/https://docs.uniswap.org/sdk/guides/fetching-prices
    /// @dev Do not use this for on-chain calculations, as it can be exploited 
    /// with a multi block attacks by block producers. Only use for off-chain utilities (eg informational purposes only)
    function univ3Price(IUniswapV3Pool pool, bool inQuotedOrder) external view returns (uint256) {
        // Pull the current price from the pool
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            
        // Use mulDiv as otherwise the calc would overflow.        
        // https://xn--2-umb.com/21/muldiv/index.html
        if (inQuotedOrder) {
            // price = sqrtPriceX96^2 / 2^192
            return Math.mulDiv(uint256(sqrtPriceX96) * sqrtPriceX96, 10 ** decimals, 1 << 192);
        } else {
            // price = 2^192 / sqrtPriceX96^2
            return Math.mulDiv(1 << 192, 10 ** decimals, sqrtPriceX96) / sqrtPriceX96;
        }
    }

    /// @notice Lookup the price of $GLP, scaled to `pricePrecision`
    /// @dev price = assets under management / glp supply
    /// GMX FE: https://github.com/gmx-io/gmx-interface/blob/98d20457aa313b9bac08b2b5cbb18486f598d8a0/src/pages/Dashboard/DashboardV2.js#L290-L291
    function glpPrice(IGlpManager glpManager) external view returns (uint256) {
        // Assets Under Management
        uint256[] memory aums = glpManager.getAums();
        uint256 avgAum = (aums[0] + aums[1]) / 2;
        uint256 glpSupply = IERC20(glpManager.glp()).totalSupply();

        if (avgAum != 0 && glpSupply != 0) {
            // GMX reports price to 30 dp
            return scaleToPrecision(avgAum * 1e18 / glpSupply, 30);
        } else {
            return 10 ** decimals;
        }
    }

    /// @notice Fetch the token price from the GMX Vault
    function gmxVaultPrice(address vault, address token) external view returns (uint256) {
        return scaleToPrecision(IGmxVault(vault).getMinPrice(token), 30);
    }

    /// @notice Calculate the Repricing Token price based
    /// on the [reserveToken price] * [reservesPerShare()]
    function repricingTokenPrice(address _repricingToken) external view returns (uint256) {
        IRepricingToken repricingToken = IRepricingToken(_repricingToken);
        return tokenPrice(repricingToken.reserveToken()) * repricingToken.reservesPerShare() / (10 ** ERC20(_repricingToken).decimals());
    }

    /** INTERNAL PRIMATIVES AND COMPOSITION FUNCTIONS */

    /// @notice A fixed scalar amount, which can be used in mul/div operations
    function scalar(uint256 _amount) external pure returns (uint256) {
        return _amount;
    }

    /// @notice Use the price function from another source token.
    function aliasFor(address sourceToken) external view returns (uint256) {
        return tokenPrice(sourceToken);
    }

    /// @notice Multiply the result of two separate price lookup functions
    function mul(bytes calldata v1, bytes calldata v2) external view returns (uint256) {
        return runPriceFunction(v1) * runPriceFunction(v2) / 10 ** decimals;
    }

    /// @notice Divide the result of two separate price lookup functions
    function div(bytes calldata numerator, bytes calldata denominator) external view returns (uint256) {
        return runPriceFunction(numerator) * 10 ** decimals / runPriceFunction(denominator);
    }

    function runPriceFunction(bytes memory fnCalldata) internal view returns (uint256 price) {
        (bool success, bytes memory returndata) = address(this).staticcall(fnCalldata);

        if (success) {
            return abi.decode(returndata, (uint256));
        } else {
            revert FailedPriceLookup(fnCalldata);
        }
    }

    /// @notice Scale the price precision of the source to the target `pricePrecision`
    function scaleToPrecision(uint256 price, uint8 sourcePrecision) internal view returns (uint256) {
        unchecked {
            if (sourcePrecision <= decimals) {
                // Scale up (no-op if sourcePrecision == pricePrecision)
                return price * 10 ** (decimals - sourcePrecision);
            } else {
                // scale down
                return price / 10 ** (sourcePrecision - decimals);
            }
        }
    }
}
