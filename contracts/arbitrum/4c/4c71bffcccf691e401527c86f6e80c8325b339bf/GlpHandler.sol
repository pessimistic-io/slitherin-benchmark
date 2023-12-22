// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {IHandlerContract} from "./IHandlerContract.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {GMX_GLP_REWARD_ROUTER, GMX_VAULT, TOKEN_FRAX} from "./constants.sol";
import {IGlpRewardRouter} from "./IGlpRewardRouter.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IVault} from "./IVault.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IPositionRouter} from "./IPositionRouter.sol";

/// @title GlpHandler
/// @author Umami DAO
/// @notice A handler contract for managing GLP related functionalities
contract GlpHandler is BaseHandler {
    using SafeTransferLib for ERC20;

    error NotStableToken(address _token);
    error NoMintCapacity();

    struct CollateralUtilization {
        address token;
        uint poolAmount;
        uint reservedAmount;
        uint utilization;
    }

    bytes32 public constant GLP_HANDLER_CONFIG_SLOT =
        keccak256("handlers.glp.config");

    IGlpRewardRouter public constant glpRewardRouter =
        IGlpRewardRouter(GMX_GLP_REWARD_ROUTER);
    IVault public constant vault = IVault(GMX_VAULT);
    uint public constant FUNDING_RATE_PRECISION = 1_000_000;
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FALLBACK_SWAP_SLIPPAGE = 1000;

    IGlpManager public immutable glpManager;
    IPositionRouter public immutable positionRouter;

    constructor(
        IGlpManager _glpManager,
        IPositionRouter _positionRouter
    ) {
        glpManager = _glpManager;
        positionRouter = _positionRouter;
    }

    /**
     * @dev Returns the GLP composition for the given volatile tokens
     * @param volatileTokens An array of volatile token addresses
     * @return _composition An array of the GLP composition for the given volatile tokens
     */
    function getGlpComposition(
        address[] calldata volatileTokens
    ) external view returns (uint[] memory _composition) {
        uint precision = 1e18;

        _composition = new uint[](volatileTokens.length + 1);

        address[] memory stableTokens = _getUnderlyingGlpTokens(true);
        uint totalStablesWorth;
        for (uint i = 0; i < stableTokens.length; ++i) {
            (, uint _usdgAmount) = _getPoolAmounts(stableTokens[i]);
            totalStablesWorth += _usdgAmount;
        }

        uint[] memory volatilesWorth = new uint[](volatileTokens.length);
        uint totalVolatilesWorth;

        for (uint i = 0; i < volatileTokens.length; ++i) {
            (, uint _usdgAmount) = _getPoolAmounts(volatileTokens[i]);
            volatilesWorth[i] = _usdgAmount;
            totalVolatilesWorth += _usdgAmount;
        }

        uint totalGlpWorth = totalVolatilesWorth + totalStablesWorth;

        uint totalVolatilesComposition;
        for (uint i = 0; i < volatileTokens.length; ++i) {
            _composition[i] = (volatilesWorth[i] * precision) / totalGlpWorth;
            totalVolatilesComposition += _composition[i];
        }

        // add stables composition
        _composition[volatileTokens.length] =
            precision -
            totalVolatilesComposition;
    }

    /**
     * @dev Previews the amount of token to be received for minting or burning the specified GLP amount
     * @param _tokenOut The output token to be received
     * @param _glpAmount The amount of GLP to be minted or burned
     * @param _mint True if minting, false if burning
     * @return _amtOut The amount of output token to be received
     */
    function previewGlpMintBurn(
        address _tokenOut,
        uint _glpAmount,
        bool _mint
    ) public view returns (uint _amtOut) {
        uint priceMin = glpManager.getPrice(_mint);
        uint usdgAmount = (_glpAmount * priceMin) / 1e30;
        uint maxFees = vault.mintBurnFeeBasisPoints() + vault.taxBasisPoints();

        uint usdgAmountFees = _mint
            ? (usdgAmount * (1e4 + maxFees)) / 1e4
            : (usdgAmount * (1e4 - maxFees)) / 1e4;

        uint tokenPrice = vault.getMaxPrice(_tokenOut);
        uint tokenDecimals = ERC20(_tokenOut).decimals();
        _amtOut = (usdgAmountFees * 1e30) / tokenPrice;
        return (_amtOut * (10 ** tokenDecimals)) / (10 ** 18);
    }

    /**
     * @dev Previews the amount of token to be received for minting and burning the specified GLP amount
     * @param _tokenOut The output token to be received
     * @param _glpAmount The amount of GLP to be minted and burned
     * @return _amtOut The average amount of output token to be received
     */
    function previewGlpMintBurn(
        address _tokenOut,
        uint _glpAmount
    ) external view returns (uint _amtOut) {
        uint mintAmount = previewGlpMintBurn(_tokenOut, _glpAmount, true);
        uint burnAmount = previewGlpMintBurn(_tokenOut, _glpAmount, false);
        _amtOut = (mintAmount + burnAmount) / 2;
    }

    /**
     * @dev Returns the price of the given token with the specified number of decimals
     * @param _token The token to get the price for
     * @param decimals The number of decimals for the returned price
     * @return _price The price of the token with the specified number of decimals
     */
    function getTokenPrice(
        address _token,
        uint decimals
    ) public view returns (uint _price) {
        uint maxPrice = vault.getMaxPrice(_token);
        uint minPrice = vault.getMinPrice(_token);
        uint price = (maxPrice + minPrice) / 2;
        _price = (price * (10 ** decimals)) / 1e30;
    }

    /**
     * @dev Returns the minimum price in GMX of the given token with the specified number of decimals
     * @param _token The token to get the minimum price for
     * @param decimals The number of decimals for the returned minimum price
     * @return _price The minimum price of the token with the specified number of decimals
     */
    function getTokenMinPrice(
        address _token,
        uint decimals
    ) public view returns (uint _price) {
        uint minPrice = vault.getMinPrice(_token);
        _price = (minPrice * (10 ** decimals)) / 1e30;
    }

    /**
    * @dev Returns the amount of the specified token equivalent to the given USD amount
    * @param _usdAmount The USD amount to be converted
    * @param _usdDecimals The number of decimals for the USD amount
    * @param _token The token to be converted to
    * @return _amountOut The equivalent amount of the specified token
    */
    function getUsdToToken(
        uint _usdAmount,
        uint _usdDecimals,
        address _token
    ) public view returns (uint _amountOut) {
        uint usdAmount = (_usdAmount * 1e30) / 10 ** _usdDecimals;
        uint decimals = ERC20(_token).decimals();
        uint price = getTokenPrice(_token, 30);
        _amountOut = (usdAmount * (10 ** decimals)) / price;
    }

    /**
     * @dev Returns the amount of USD equivalent to the given token amount
     * @param _token The token to be converted from
     * @param _tokenAmount The amount of the token to be converted
     * @param _usdDecimals The number of decimals for the returned USD amount
     * @return _usdAmount The equivalent amount of USD
     */
    function getTokenToUsd(
        address _token,
        uint _tokenAmount,
        uint _usdDecimals
    ) public view returns (uint _usdAmount) {
        uint decimals = ERC20(_token).decimals();
        uint price = getTokenPrice(_token, 30);
        _usdAmount =
            (_tokenAmount * price * 10 ** _usdDecimals) /
            ((10 ** decimals) * (10 ** 30));
    }

    /**
    * @dev Returns the equivalent amount of GLP for the given USD amount
    * @param _usdAmount The USD amount to be converted
    * @param _usdDecimals The number of decimals for the USD amount
    * @param _max True to use the maximum price for conversion, false to use the minimum price
    * @return _glpAmount The equivalent amount of GLP
    */
    function usdToGlp(
        uint _usdAmount,
        uint _usdDecimals,
        bool _max
    ) external view returns (uint _glpAmount) {
        uint usdAmount = (_usdAmount * 1e30) / 10 ** _usdDecimals;
        uint glpPrice = glpManager.getPrice(_max);
        _glpAmount = (usdAmount * 1e18) / glpPrice;
    }

    /**
    * @dev Returns the average price of GLP
    * @return _price The average price of GLP
    */
    function getGlpPrice() external view returns (uint _price) {
        uint maxPrice = glpManager.getPrice(true);
        uint minPrice = glpManager.getPrice(false);
        _price = (maxPrice + minPrice) / 2;
    }

    /**
    * @dev Returns the GLP price based on the given _max parameter
    * @param _max True to return the maximum price, false to return the minimum price
    * @return _price The GLP price
    */
    function getGlpPrice(bool _max) external view returns (uint _price) {
        _price = glpManager.getPrice(_max);
    }

    /**
    * @dev Returns the minimum output amount of tokenOut for the given input amount and tokens
    * @param _tokenIn The input token
    * @param _tokenOut The output token
    * @param _amountIn The amount of input tokens
    * @return minOut The minimum output amount of tokenOut
    */
    function tokenToToken(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _toleranceBps
    ) public view returns (uint minOut) {
        uint tokenInDecimals = ERC20(_tokenIn).decimals();
        uint tokenOutDecimals = ERC20(_tokenOut).decimals();
        uint tokenInDollars = _amountIn * getTokenPrice(_tokenIn, 30);
        minOut = (tokenInDollars / getTokenPrice(_tokenOut, 30)) * ((BASIS_POINTS_DIVISOR - _toleranceBps)) / BASIS_POINTS_DIVISOR;
        minOut = minOut * 10 ** tokenOutDecimals / 10 ** tokenInDecimals;
    }

    /**
    * @dev Returns the minimum output amount of tokenOut for the given input amount and tokens
    * @param _tokenIn The input token
    * @param _tokenOut The output token
    * @param _amountIn The amount of input tokens
    * @return minOut The minimum output amount of tokenOut
    */
    function tokenToToken(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn
    ) public view returns (uint minOut) {
        minOut = tokenToToken(_tokenIn, _tokenOut, _amountIn, FALLBACK_SWAP_SLIPPAGE);
    }

    /**
    * @dev Returns the available liquidity and collateral utilization for long positions in the specified index token
    * @param _indexToken The index token to query for
    * @return _notional The available notional liquidity for long positions
    * @return _util The collateral utilization data for the specified index token
    */
    function getAvailableLiquidityLong(
        address _indexToken
    )
        external
        view
        returns (uint _notional, CollateralUtilization memory _util)
    {
        uint maxLongs = positionRouter.maxGlobalLongSizes(_indexToken);
        uint existingLongs = vault.guaranteedUsd(_indexToken);
        uint poolAmount = vault.poolAmounts(_indexToken);
        uint reservedAmount = vault.reservedAmounts(_indexToken);
        uint availableAmount = poolAmount - reservedAmount;
        uint maxPrice = vault.getMaxPrice(_indexToken); // price of 1 token in 30 decimals
        uint availableUsd = (availableAmount * maxPrice) /
            (10 ** ERC20(_indexToken).decimals());

        _util.token = _indexToken;
        _util.poolAmount = poolAmount;
        _util.reservedAmount = reservedAmount;
        _util.utilization =
            (reservedAmount * FUNDING_RATE_PRECISION) /
            poolAmount;

        if (maxLongs > existingLongs) {
            uint availableLongs = maxLongs - existingLongs;
            _notional = availableLongs > availableUsd
                ? availableUsd
                : availableLongs;
        } else {
            _notional = 0;
        }
    }

    /**
    * @dev Returns the available liquidity and collateral utilization for short positions in the specified index token
    * @param _indexToken The index token to query for
    * @param _collateralTokens An array of collateral token addresses to query for
    * @return _availableNotional The available notional liquidity for short positions
    * @return _availableStables An array of available stablecoin notional amounts for each collateral token
    * @return _utilizations An array of collateral utilization data for each collateral token
    */
    function getAvailableLiquidityShort(
        address _indexToken,
        address[] calldata _collateralTokens
    )
        external
        view
        returns (
            uint _availableNotional,
            uint[] memory _availableStables,
            CollateralUtilization[] memory _utilizations
        )
    {
        _availableStables = new uint[](_collateralTokens.length);
        _utilizations = new CollateralUtilization[](_collateralTokens.length);

        uint maxShorts = positionRouter.maxGlobalShortSizes(_indexToken);
        uint globalShorts = vault.globalShortSizes(_indexToken);
        _availableNotional = maxShorts > globalShorts
            ? maxShorts - globalShorts
            : 0;

        for (uint i = 0; i < _collateralTokens.length; ++i) {
            address _collateralToken = _collateralTokens[i];
            _validateStableToken(_collateralToken);

            uint poolAmounts = vault.poolAmounts(_collateralToken);
            uint reservedAmounts = vault.reservedAmounts(_collateralToken);
            uint availableAmount = poolAmounts - reservedAmounts;
            uint availableStableNotional = (availableAmount * 1e30) /
                (10 ** ERC20(_collateralToken).decimals());
            _availableStables[i] = _availableNotional > availableStableNotional
                ? availableStableNotional
                : _availableNotional;

            _utilizations[i].token = _collateralToken;
            _utilizations[i].poolAmount = poolAmounts;
            _utilizations[i].reservedAmount = reservedAmounts;
            _utilizations[i].utilization =
                (reservedAmounts * FUNDING_RATE_PRECISION) /
                poolAmounts;
        }
    }

    /**
    * @dev Calculates the increased token amount for minting considering the fees
    * @param _mintToken The token to be minted
    * @param _tokenAmount The amount of the token to be minted
    * @return increasedTokenAmount The increased
    */
    function calculateTokenMintAmount(address _mintToken, uint _tokenAmount) external view returns (uint256 increasedTokenAmount) {
        uint price = getTokenMinPrice(_mintToken, 30);
        uint256 usdgAmount = _tokenAmount * price / 1e30;
        uint feeBasisPoints = vault.getFeeBasisPoints(_mintToken, usdgAmount, vault.mintBurnFeeBasisPoints(), vault.taxBasisPoints(), true);
        uint increasePoints = BASIS_POINTS_DIVISOR * 1e30 / (BASIS_POINTS_DIVISOR - feeBasisPoints);
        increasedTokenAmount = increasePoints * _tokenAmount / 1e30;
    }

    function routeGlpMint(address _intendedMintAsset, uint256 _dollarMint, bool _onlyStables) external view returns (address _mintToken, uint256 _minOut) {
        if (checkGlpMintCapacity(_intendedMintAsset, _dollarMint)) {
            return (_intendedMintAsset, 0);
        } else {
            address[] memory possibleMintTokens = _getUnderlyingGlpTokens(_onlyStables);
            for (uint i = 0; i < possibleMintTokens.length; ++i) {
                // note frax removed due to low liquidity
                if (checkGlpMintCapacity(possibleMintTokens[i], _dollarMint) && possibleMintTokens[i] != TOKEN_FRAX) {
                    return (possibleMintTokens[i], getUsdToToken(_dollarMint, 18, possibleMintTokens[i]) * (BASIS_POINTS_DIVISOR - FALLBACK_SWAP_SLIPPAGE) / BASIS_POINTS_DIVISOR);
                }
            }
            revert NoMintCapacity();
        }
    }
    
    /**
    * @notice Checks whether the GLP mint has sufficient capacity for the specified asset and amount.
    * @param intendedMintAsset The address of the asset to be minted.
    * @param dollarMint The amount of dollars to be minted.
    * @return - True if the mint capacity is sufficient, false otherwise.
    */
    function checkGlpMintCapacity(address intendedMintAsset, uint256 dollarMint) public view returns (bool) {
        uint256 tokenAmount = getUsdToToken(dollarMint, 18, intendedMintAsset); // 18 decimal standard for calcs
        uint price = vault.getMinPrice(intendedMintAsset);
        uint256 usdgAmount = tokenAmount * price / 1e30;
        usdgAmount = adjustForDecimals(usdgAmount, intendedMintAsset, vault.usdg());
        require(usdgAmount > 0, "GlpHandler: !usdgAmount");
        uint256 feeBasisPoints = vault.getFeeBasisPoints(intendedMintAsset, usdgAmount, vault.mintBurnFeeBasisPoints(), vault.taxBasisPoints(), true);
        uint256 amountAfterFees = tokenAmount * (BASIS_POINTS_DIVISOR - feeBasisPoints) / BASIS_POINTS_DIVISOR;
        uint256 mintAmount = amountAfterFees * price / 1e30;
        mintAmount = adjustForDecimals(mintAmount, intendedMintAsset, vault.usdg());
        uint256 currentUsdgAmount = vault.usdgAmounts(intendedMintAsset) + mintAmount;
        return  currentUsdgAmount <= vault.maxUsdgAmounts(intendedMintAsset);
    }

    /**
    * @notice Adjusts the given amount for the difference in decimals between two tokens.
    * @param _amount The amount to be adjusted.
    * @param _tokenDiv The address of the token to divide the amount by.
    * @param _tokenMul The address of the token to multiply the amount with.
    * @return The adjusted amount.
    */
    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) public view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == vault.usdg() ? USDG_DECIMALS : ERC20(_tokenDiv).decimals();
        uint256 decimalsMul = _tokenMul == vault.usdg() ? USDG_DECIMALS : ERC20(_tokenMul).decimals();
        return _amount * 10 ** decimalsMul / 10 ** decimalsDiv;
    }

    /**
    * @notice Returns an array of underlying GLP tokens based on the input parameter.
    * @param onlyStables If true, returns only stable tokens; otherwise, returns non-stable tokens.
    * @return _tokens An array of addresses representing the underlying GLP tokens.
    */
    function _getUnderlyingGlpTokens(
        bool onlyStables
    ) internal view returns (address[] memory _tokens) {
        address[] memory allWhitelistedTokens = _allWhitelistedTokens();
        _tokens = new address[](allWhitelistedTokens.length);
        uint foundTokens = 0;

        for (uint i = 0; i < allWhitelistedTokens.length; ++i) {
            bool isStable = vault.stableTokens(allWhitelistedTokens[i]);
            if (onlyStables && isStable) {
                _tokens[foundTokens++] = allWhitelistedTokens[i];
            } else if (!onlyStables && !isStable) {
                _tokens[foundTokens++] = allWhitelistedTokens[i];
            }
        }

        /// @solidity memory-safe-assembly
        assembly {
            mstore(_tokens, foundTokens) // change the array size to the actual number of tokens found
        }
    }

    /**
    * @notice Returns an array of all whitelisted tokens in the vault.
    * @return _tokens An array of addresses representing the whitelisted tokens.
    */
    function _allWhitelistedTokens()
        internal
        view
        returns (address[] memory _tokens)
    {
        _tokens = new address[](vault.allWhitelistedTokensLength());
        for (uint i = 0; i < _tokens.length; ++i) {
            _tokens[i] = vault.allWhitelistedTokens(i);
        }
    }

    /**
    * @notice Returns the pool amounts for the specified token.
    * @param _token The address of the token.
    * @return _tokenAmount The amount of the token in the pool.
    * @return _usdgAmount The amount of USDG in the pool, based on the token's average price.
    */
    function _getPoolAmounts(
        address _token
    ) internal view returns (uint _tokenAmount, uint _usdgAmount) {
        _tokenAmount = vault.poolAmounts(_token);
        uint maxPrice = vault.getMaxPrice(_token);
        uint minPrice = vault.getMinPrice(_token);
        uint tokenDecimals = vault.tokenDecimals(_token);
        uint avgPrice = (minPrice + maxPrice) / 2; // this should remove the spread from the price
        _usdgAmount = (_tokenAmount * avgPrice) / 10 ** tokenDecimals;
    }

    /**
    * @notice Returns the static AUM of the GLP based on pool amounts and prices.
    * @return _aum The static AUM value.
    */
    function _getGlpStaticAum() internal view returns (uint _aum) {
        address[] memory tokens = _allWhitelistedTokens();
        for (uint i = 0; i < tokens.length; ++i) {
            (, uint _usdgAmount) = _getPoolAmounts(tokens[i]);
            _aum += _usdgAmount;
        }

        return _aum;
    }

    /**
    * @notice Returns the dynamic AUM of the GLP based on the AUM values with max and min prices.
    * @return _aum The dynamic AUM value.
    */
    function _getGlpDynamicAum() internal view returns (uint _aum) {
        uint maxAum = glpManager.getAum(true);
        uint minAum = glpManager.getAum(false);
        return (maxAum + minAum) / 2;
    }

    /**
    * @notice Validates if the given token is a stable token in the vault.
    * @param _token The address of the token to validate.
    * @dev Reverts if the given token is not a stable token in the vault.
    */
    function _validateStableToken(address _token) internal view {
        if (!vault.stableTokens(_token)) {
            revert NotStableToken(_token);
        }
    }

    /**
     * @dev Returns the callback signatures
     * @return _ret An array of function signatures (bytes4) for the callback
     */
    function callbackSigs()
        external
        pure
        override
        returns (bytes4[] memory _ret)
    {
        _ret = new bytes4[](0);
    }
}

