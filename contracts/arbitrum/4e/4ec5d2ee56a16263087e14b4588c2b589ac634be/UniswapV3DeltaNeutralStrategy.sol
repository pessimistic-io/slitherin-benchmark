// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./IAddressProvider.sol";
import "./IBorrower.sol";
import "./ISwapper.sol";
import "./IOracle.sol";
import "./IController.sol";
import "./IStrategyVault.sol";
import "./ILendVault.sol";
import "./IWETH.sol";
import "./IUniswapV3Integration.sol";
import "./AddressArray.sol";
import "./UintArray.sol";
import "./UniswapV3BaseStrategy.sol";
import "./Math.sol";
import "./Address.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeERC20.sol";
import {FullMath} from "./FullMath.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";

/**
 * @notice Strategy that borrows from LendVault and deposits into a uni v3 pool
 */
contract UniswapV3DeltaNeutralStrategy is UniswapV3BaseStrategy {
    using AddressArray for address[];
    using Address for address;
    using SafeERC20 for IERC20;
    using UintArray for uint[];

    /**
     * @notice Initialize upgradeable contract
     */
    function initialize(
        address _provider,
        Addresses memory _addresses,
        Thresholds memory _thresholds,
        Parameters memory _parameters
    ) external initializer {
        _UniswapV3BaseStrategy__init(_provider, _addresses, _thresholds, _parameters);
    }

    function calculateBorrowAmounts() public view returns (address[] memory tokens, int[] memory amounts) {
        IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
        IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
        ISwapper swapper = ISwapper(provider.swapper());
        (uint token0Ratio, uint token1Ratio) = integration.getRatio(addresses.want, parameters.tick0, parameters.tick1);
        uint stableRatio; uint volatileRatio;
        uint volatilePrice = integration.pairPrice(addresses.want, addresses.volatileToken);
        if (addresses.stableToken==pool.token0()) {
            (stableRatio, volatileRatio) = (token0Ratio, token1Ratio);
        } else {
            (volatileRatio, stableRatio) = (token0Ratio, token1Ratio);
        }
        uint volatileRatioInStablePrice = volatilePrice * volatileRatio / 10**ERC20(addresses.volatileToken).decimals();
        uint supplied = IERC20(addresses.stableToken).balanceOf(address(this));
        supplied+=swapper.getAmountOut(addresses.volatileToken, IERC20(addresses.volatileToken).balanceOf(address(this)), addresses.stableToken);
        address depositToken = getDepositToken();
        if (addresses.stableToken!=depositToken) {
            supplied+=swapper.getAmountOut(depositToken, IERC20(depositToken).balanceOf(address(this)), addresses.stableToken);
        }
        int borrowStable = int((supplied * parameters.leverage * stableRatio / (stableRatio + volatileRatioInStablePrice)) / PRECISION) - int(supplied);

        // Note: borrowVolatile can be 0, if the liquidity is completely out of range and stableRatio is 0
        // However, that position wouldn't produce fee anyway, so borrowing is pointless
        int borrowVolatile = (borrowStable + int(supplied)) * int(volatileRatio) / int(Math.max(1, stableRatio));
        tokens = new address[](2);
        amounts = new int[](2);
        tokens[0] = addresses.stableToken;
        tokens[1] = addresses.volatileToken;
        amounts[0] = borrowStable;
        amounts[1] = borrowVolatile;
    }

    function getDepositable() external view returns (uint amount) {
        uint stableBorrowable; uint volatileBorrowable;
        uint stableRatio; uint volatileRatio;
        ILendVault lendVault = ILendVault(provider.lendVault());
        IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
        (, uint[] memory debts) = getDebts();
        uint volatilePrice = integration.pairPrice(addresses.want, addresses.volatileToken);
        {
            (uint token0Ratio, uint token1Ratio) = integration.getRatio(addresses.want, parameters.tick0, parameters.tick1);
            IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
            if (addresses.stableToken==pool.token0()) {
                (stableRatio, volatileRatio) = (token0Ratio, token1Ratio);
            } else {
                (volatileRatio, stableRatio) = (token0Ratio, token1Ratio);
            }
        }
        {
            uint maxBorrowable = lendVault.totalAssets(addresses.stableToken) * lendVault.creditLimits(addresses.stableToken, address(this)) / PRECISION;
            stableBorrowable = maxBorrowable - Math.min(maxBorrowable, debts[0]);
        }
        {
            uint maxBorrowable = lendVault.totalAssets(addresses.volatileToken) * lendVault.creditLimits(addresses.volatileToken, address(this)) / PRECISION;
            volatileBorrowable = maxBorrowable - Math.min(maxBorrowable, debts[1]);
        }

        uint stableSupplied;
        {
            uint volatileRatioInStablePrice = volatilePrice * volatileRatio / 10**ERC20(addresses.volatileToken).decimals();
            uint stableMultiplier = parameters.leverage * stableRatio / (stableRatio + volatileRatioInStablePrice);
            uint stableBasedOnRatio = volatileBorrowable * stableRatio / Math.max(1, volatileRatio);
            uint suppliedBasedOnRatio = stableBasedOnRatio * PRECISION / stableMultiplier;
            uint suppliedBasedOnBorrowable = stableBorrowable * PRECISION / (stableMultiplier - PRECISION);

            stableSupplied = Math.min(suppliedBasedOnBorrowable, suppliedBasedOnRatio);
        }
        ISwapper swapper = ISwapper(provider.swapper());
        amount = swapper.getAmountIn(getDepositToken(), stableSupplied, addresses.stableToken);
    }
}
