// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { ICreditAggregator } from "./ICreditAggregator.sol";
import { IAddressProvider } from "./IAddressProvider.sol";
import { IGmxRewardRouter } from "./IGmxRewardRouter.sol";
import { IGlpManager } from "./IGlpManager.sol";
import { IGmxVault } from "./IGmxVault.sol";

contract CreditAggregator is Initializable, ICreditAggregator {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant GMX_DIVISION_LOSS_COMPENSATION = 10000; // 0.01 %
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant MINT_BURN_FEE_BASIS_POINTS = 25;
    uint256 private constant TAX_BASIS_POINTS = 50;
    uint8 private constant GLP_DECIMALS = 18;
    uint8 private constant USDG_DECIMALS = 18;
    uint8 private constant PRICE_DECIMALS = 30;

    address public addressProvider;
    address public router;
    address public glpManager;
    address public vault;
    address public usdg;
    address public glp;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _addressProvider) external initializer {
        require(_addressProvider != address(0), "CreditAggregator: _addressProvider cannot be 0x0");
        require(_addressProvider.isContract(), "CreditAggregator: _addressProvider is not a contract");

        addressProvider = _addressProvider;
    }

    function update() public {
        router = IAddressProvider(addressProvider).getGmxRewardRouter();
        glpManager = IGmxRewardRouter(router).glpManager();
        glp = IGlpManager(glpManager).glp();
        vault = IGlpManager(glpManager).vault();
        usdg = IGlpManager(glpManager).usdg();
    }

    /// @dev Get glp price
    /// @return 1e30
    function getGlpPrice(bool _isBuying) public view override returns (uint256) {
        // uint256[] memory aums = IGlpManager(glpManager).getAums();

        // if (aums.length > 0) {
        //     uint256 aum;

        //     if (_isBuying) {
        //         aum = aums[0];
        //     } else {
        //         aum = aums[1];
        //     }

        //     uint256 glpSupply = _totalSupply(glp);

        //     if (glpSupply > 0) {
        //         return aum.mul(10**PRICE_DECIMALS) / glpSupply;
        //     }
        // }

        uint256 aumInUsdg = IGlpManager(glpManager).getAumInUsdg(_isBuying);
        uint256 glpSupply = _totalSupply(glp);

        if (glpSupply > 0) {
            return aumInUsdg.mul(10**PRICE_DECIMALS).div(glpSupply);
        }

        return 0;
    }

    /* 
        glpPrice = 939690091372936156490347029512
        btcPrice = 23199207122640000000000000000000000
        ethPrice = 1652374189683000000000000000000000
        usdcPrice = 1000000000000000000000000000000

        # glp to token
        3422 × 1e18 × 0.939 × 1e30  / btcPrice / 1e18 glp decimals
        3422 × 1e18 × 0.939 × 1e30 / ethPrice / 1e18 glp decimals
        3422 × 1e18 × 0.939 × 1e30 / usdcPrice / 1e18 glp decimals

        # token to glp
        2 × 1e8 × btcPrice  / glpPrice / 1e8 token decimals
        2 × 1e18 × ethPrice / glpPrice / 1e18 token decimals
        300 × 1e6 × usdcPrice / glpPrice / 1e6 token decimals
     */

    function getBuyGlpToAmount(address _fromToken, uint256 _tokenAmountIn) external view override returns (uint256, uint256) {
        uint256 tokenPrice = IGmxVault(vault).getMinPrice(_fromToken);
        uint256 glpPrice = getGlpPrice(true);
        uint256 glpAmount = _tokenAmountIn.mul(tokenPrice).div(glpPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_fromToken);
        uint256 usdgAmount = _tokenAmountIn.mul(tokenPrice).div(10**PRICE_DECIMALS);

        glpAmount = adjustForDecimals(glpAmount, tokenDecimals, GLP_DECIMALS);
        usdgAmount = adjustForDecimals(usdgAmount, tokenDecimals, USDG_DECIMALS);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_fromToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (glpAmount, feeBasisPoints);
    }

    function getSellGlpFromAmount(address _fromToken, uint256 _tokenAmountIn) external view override returns (uint256, uint256) {
        uint256 tokenPrice = IGmxVault(vault).getMaxPrice(_fromToken);
        uint256 glpPrice = getGlpPrice(false);

        uint256 glpAmount = _tokenAmountIn.mul(tokenPrice).div(glpPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_fromToken);
        uint256 usdgAmount = _tokenAmountIn.mul(tokenPrice).div(10**PRICE_DECIMALS);

        glpAmount = adjustForDecimals(glpAmount, tokenDecimals, GLP_DECIMALS);
        usdgAmount = adjustForDecimals(usdgAmount, tokenDecimals, USDG_DECIMALS);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_fromToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);
        glpAmount = glpAmount.add(glpAmount.div(GMX_DIVISION_LOSS_COMPENSATION));

        return (glpAmount, feeBasisPoints);
    }

    function getBuyGlpFromAmount(address _toToken, uint256 _glpAmountIn) external view override returns (uint256, uint256) {
        uint256 tokenPrice = IGmxVault(vault).getMinPrice(_toToken);
        uint256 glpPrice = getGlpPrice(true);

        uint256 tokenAmountOut = _glpAmountIn.mul(glpPrice).div(tokenPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_toToken);

        tokenAmountOut = adjustForDecimals(tokenAmountOut, GLP_DECIMALS, tokenDecimals);

        uint256 usdgAmount = _glpAmountIn.mul(glpPrice).div(10**PRICE_DECIMALS);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_toToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        tokenAmountOut = tokenAmountOut.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);

        return (tokenAmountOut, feeBasisPoints);
    }

    function getSellGlpToAmount(address _toToken, uint256 _glpAmountIn) external view override returns (uint256, uint256) {
        uint256 tokenPrice = IGmxVault(vault).getMaxPrice(_toToken);
        uint256 glpPrice = getGlpPrice(false);
        uint256 tokenAmountOut = _glpAmountIn.mul(glpPrice).div(tokenPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_toToken);

        tokenAmountOut = adjustForDecimals(tokenAmountOut, GLP_DECIMALS, tokenDecimals);

        uint256 usdgAmount = _glpAmountIn.mul(glpPrice).div(10**PRICE_DECIMALS);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_toToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        tokenAmountOut = tokenAmountOut.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (tokenAmountOut, feeBasisPoints);
    }

    function adjustForDecimals(
        uint256 _amountIn,
        uint256 _divDecimals,
        uint256 _mulDecimals
    ) public pure override returns (uint256) {
        return _amountIn.mul(10**_mulDecimals).div(10**_divDecimals);
    }

    function getVaultPool(address _token)
        external
        view
        returns (
            uint256 poolTotalUSD,
            uint256 poolMaxPoolCapacity,
            uint256 poolAvailables,
            uint256 tokenPrice
        )
    {
        tokenPrice = getTokenPrice(_token);

        bool isStable = IGmxVault(vault).stableTokens(_token);
        uint256 availableAmount = IGmxVault(vault).poolAmounts(_token).sub(IGmxVault(vault).reservedAmounts(_token));
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_token);
        uint256 availableUsd = isStable
            ? IGmxVault(vault).poolAmounts(_token).mul(tokenPrice).div(10**tokenDecimals)
            : availableAmount.mul(tokenPrice).div(10**tokenDecimals);

        poolTotalUSD = availableUsd.add(IGmxVault(vault).guaranteedUsd(_token));
        poolMaxPoolCapacity = IGmxVault(vault).maxUsdgAmounts(_token);
        poolAvailables = poolTotalUSD.mul(10**tokenDecimals).div(tokenPrice);
    }

    function _totalSupply(address _token) internal view returns (uint256) {
        return IERC20Upgradeable(_token).totalSupply();
    }

    function getTokenPrice(address _token) public view override returns (uint256) {
        uint256 diff = 0;
        uint256 price0 = getMinPrice(_token);
        uint256 price1 = getMaxPrice(_token);
        uint256 price = price0;

        if (price0 > price1) {
            diff = price0 - price1;

            price = price1;
        } else {
            diff = price1 - price0;
        }

        if (diff > 0) {
            diff = diff / 2;
        }

        return price + diff;
    }

    function getMaxPrice(address _token) public view returns (uint256) {
        return IGmxVault(vault).getMaxPrice(_token);
    }

    function getMinPrice(address _token) public view returns (uint256) {
        return IGmxVault(vault).getMinPrice(_token);
    }
}

