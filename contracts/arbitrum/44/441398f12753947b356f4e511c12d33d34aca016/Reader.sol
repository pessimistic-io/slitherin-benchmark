// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

import "./IVault.sol";
import "./IVaultUtils.sol";
import "./IVaultPriceFeed.sol";
import "./VaultMSData.sol";
import "./IYieldTracker.sol";
import "./IYieldToken.sol";

// import "../staking/interfaces/IVester.sol";

interface IVaultTarget {
    function vaultUtils() external view returns (address);
}
contract Reader {
    using SafeMath for uint256;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant POSITION_PROPS_LENGTH = 9;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDX_DECIMALS = 18;

    address public nativeToken;
    address public priceFeed;
    constructor(
        address _nativeToken,
        address _priceFeed
    ) {
        nativeToken = _nativeToken;
        priceFeed = _priceFeed;
    }

    function getMaxAmountIn(IVault _vault, address _tokenIn, address _tokenOut) public view returns (uint256) {
        uint256 priceIn = IVaultPriceFeed(priceFeed).getPriceUnsafe(_tokenIn, false, false, false);
        uint256 priceOut = IVaultPriceFeed(priceFeed).getPriceUnsafe(_tokenOut, false, false, false);

        uint256 tokenInDecimals = _vault.tokenDecimals(_tokenIn);
        uint256 tokenOutDecimals = _vault.tokenDecimals(_tokenOut);

        uint256 amountIn;

        {
            uint256 poolAmount = 0;//_vault.poolAmounts(_tokenOut);
            uint256 reservedAmount = 0;// _vault.reservedAmounts(_tokenOut);
            uint256 bufferAmount = 0;//_vault.bufferAmounts(_tokenOut);
            uint256 subAmount = reservedAmount > bufferAmount ? reservedAmount : bufferAmount;
            if (subAmount >= poolAmount) {
                return 0;
            }
            uint256 availableAmount = poolAmount.sub(subAmount);
            amountIn = availableAmount.mul(priceOut).div(priceIn).mul(10 ** tokenInDecimals).div(10 ** tokenOutDecimals);
        }

        uint256 maxUsdxAmount = 0;//_vault.maxUSDAmounts(_tokenIn);

        if (maxUsdxAmount != 0) {
            if (maxUsdxAmount < _vault.usdxAmounts(_tokenIn)) {
                return 0;
            }

            uint256 maxAmountIn = maxUsdxAmount.sub(_vault.usdxAmounts(_tokenIn));
            maxAmountIn = maxAmountIn.mul(10 ** tokenInDecimals).div(10 ** USDX_DECIMALS);
            maxAmountIn = maxAmountIn.mul(PRICE_PRECISION).div(priceIn);

            if (amountIn > maxAmountIn) {
                return maxAmountIn;
            }
        }

        return amountIn;
    }

    function getFeeBasisPoints(IVault _vault, address _tokenIn, address _tokenOut, uint256 _amountIn) public view returns (uint256, uint256, uint256) {
        uint256 priceIn = IVaultPriceFeed(priceFeed).getPriceUnsafe(_tokenIn, false, false, false);
        uint256 tokenInDecimals = _vault.tokenDecimals(_tokenIn);
        IVaultUtils _vaultUtils = IVaultUtils(IVaultTarget(address(_vault)).vaultUtils());

        uint256 usdxAmount = _amountIn.mul(priceIn).div(PRICE_PRECISION);
        usdxAmount = usdxAmount.mul(10 ** USDX_DECIMALS).div(10 ** tokenInDecimals);
       
        uint256 baseBps = 0;
        uint256 taxBps = 0;
        {
            VaultMSData.TokenBase memory _tbIn = _vault.getTokenBase(_tokenIn);
            VaultMSData.TokenBase memory _tbOut = _vault.getTokenBase(_tokenOut);

            bool isStableSwap = _tbIn.isStable && _tbOut.isStable;
            baseBps = isStableSwap ? _vaultUtils.stableSwapFeeBasisPoints() : _vaultUtils.swapFeeBasisPoints();
            taxBps = isStableSwap ? _vaultUtils.stableTaxBasisPoints() : _vaultUtils.taxBasisPoints();
        }

        uint256 feesBasisPoints0 = _vaultUtils.getFeeBasisPoints(_tokenIn, usdxAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = _vaultUtils.getFeeBasisPoints(_tokenOut, usdxAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        uint256 feeBasisPoints = feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;

        return (feeBasisPoints, feesBasisPoints0, feesBasisPoints1);
    }

    function getFees(address _vault, address[] memory _tokens) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            amounts[i] = IVault(_vault).feeReserves(_tokens[i]);
        }
        return amounts;
    }

    function getTotalStaked(address[] memory _yieldTokens) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_yieldTokens.length);
        for (uint256 i = 0; i < _yieldTokens.length; i++) {
            IYieldToken yieldToken = IYieldToken(_yieldTokens[i]);
            amounts[i] = yieldToken.totalStaked();
        }
        return amounts;
    }

    function getStakingInfo(address _account, address[] memory _yieldTrackers) public view returns (uint256[] memory) {
        uint256 propsLength = 2;
        uint256[] memory amounts = new uint256[](_yieldTrackers.length * propsLength);
        for (uint256 i = 0; i < _yieldTrackers.length; i++) {
            IYieldTracker yieldTracker = IYieldTracker(_yieldTrackers[i]);
            amounts[i * propsLength] = yieldTracker.claimable(_account);
            amounts[i * propsLength + 1] = yieldTracker.getTokensPerInterval();
        }
        return amounts;
    }


    function getPairInfo(address /*_factory*/, address[] memory _tokens) public pure returns (uint256[] memory) {
        uint256 inputLength = 2;
        uint256 propsLength = 2;
        uint256[] memory amounts = new uint256[](_tokens.length / inputLength * propsLength);

        return amounts;
    }


    function getTokenSupply(IERC20 _token, address[] memory _excludedAccounts) public view returns (uint256) {
        uint256 supply = _token.totalSupply();
        for (uint256 i = 0; i < _excludedAccounts.length; i++) {
            address account = _excludedAccounts[i];
            uint256 balance = _token.balanceOf(account);
            supply = supply.sub(balance);
        }
        return supply;
    }

    function getTotalBalance(IERC20 _token, address[] memory _accounts) public view returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            uint256 balance = _token.balanceOf(account);
            totalBalance = totalBalance.add(balance);
        }
        return totalBalance;
    }

    function getTokenBalances(address _account, address[] memory _tokens) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                balances[i] = _account.balance;
                continue;
            }
            balances[i] = IERC20(token).balanceOf(_account);
        }
        return balances;
    }

    function getTokenBalancesWithSupplies(address _account, address[] memory _tokens) public view returns (uint256[] memory) {
        uint256 propsLength = 2;
        uint256[] memory balances = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                balances[i * propsLength] = _account.balance;
                balances[i * propsLength + 1] = 0;
                continue;
            }
            balances[i * propsLength] = IERC20(token).balanceOf(_account);
            balances[i * propsLength + 1] = IERC20(token).totalSupply();
        }
        return balances;
    }

    function getPrices( address[] memory _tokens) public view returns (uint256[] memory) {
        uint256 propsLength = 6;
        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            amounts[i * propsLength] = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, true, true, false);
            amounts[i * propsLength + 1] = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, false, true, false);
            // (amounts[i * propsLength + 2], ) = _priceFeed.getPrimaryPrice(token, true);
            // (amounts[i * propsLength + 3], ) = _priceFeed.getPrimaryPrice(token, false);
            amounts[i * propsLength + 2] = amounts[i * propsLength];
            amounts[i * propsLength + 3] = amounts[i * propsLength + 1];
            amounts[i * propsLength + 4] = IVaultPriceFeed(priceFeed).isAdjustmentAdditive(token) ? 1 : 0;
            amounts[i * propsLength + 5] = IVaultPriceFeed(priceFeed).adjustmentBasisPoints(token);
        }
        return amounts;
    }

}
