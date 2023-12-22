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
import "./IUniswapV3StrategyData.sol";
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

    /**
     * @notice Calculate the amounts of stable and volatile token to borrow based on the current
     * stable balance and leverage
     */
    function calculateBorrowAmounts() public view returns (address[] memory tokens, int[] memory amounts) {
        IUniswapV3StrategyData strategyData = IUniswapV3StrategyData(provider.uniswapV3StrategyData());
        ISwapper swapper = ISwapper(provider.swapper());
        (uint stableRatio, uint volatileRatio, uint volatileRatioInStablePrice) = strategyData.getPoolRatios(address(this));
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

    /**
     * @notice Calculate the max amount of stable token that can be supplied and
     * the corresponding amount of stable and volatile tokens that will be borrowed
     * from the LendVault
     */
    function getDepositableAndBorrowables() external view returns (uint depositable, address[] memory tokens, uint[] memory borrowables) {
        IUniswapV3StrategyData strategyData = IUniswapV3StrategyData(provider.uniswapV3StrategyData());
        (uint stableRatio, uint volatileRatio, uint volatileRatioInStablePrice) = strategyData.getPoolRatios(address(this));

        uint stableBorrow;
        {
            uint stableMultiplier = parameters.leverage * stableRatio / (stableRatio + volatileRatioInStablePrice);
            uint suppliedBasedOnRatio;
            {
                uint volatileBorrowable = _getBorrowable(addresses.volatileToken);
                uint stableBasedOnRatio = volatileBorrowable * stableRatio / Math.max(1, volatileRatio);
                suppliedBasedOnRatio = stableBasedOnRatio * PRECISION / stableMultiplier;
            }
            uint stableBorrowable = _getBorrowable(addresses.stableToken);
            uint suppliedBasedOnBorrowable = stableBorrowable * PRECISION / stableMultiplier;

            depositable = Math.min(suppliedBasedOnBorrowable, suppliedBasedOnRatio);
            uint stableTotal = (depositable * stableMultiplier) / PRECISION;
            stableBorrow = stableTotal>depositable?stableTotal - depositable : 0;
        }
        uint volatileBorrow = (stableBorrow + depositable) * volatileRatio / Math.max(1, stableRatio);
        IOracle oracle = IOracle(provider.oracle());

        // Convert token amounts to vault's deposit token
        depositable = oracle.getValueInTermsOf(addresses.stableToken, depositable, getDepositToken());
        stableBorrow = oracle.getValueInTermsOf(addresses.stableToken, stableBorrow, getDepositToken());
        volatileBorrow = oracle.getValueInTermsOf(addresses.volatileToken, volatileBorrow, getDepositToken());

        tokens = new address[](2);
        borrowables = new uint[](2);
        tokens[0] = addresses.stableToken;
        tokens[1] = addresses.volatileToken;
        borrowables[0] = stableBorrow;
        borrowables[1] = volatileBorrow;
    }

    function _getBorrowable(address token) internal view returns (uint borrowable) {
        ILendVault lendVault = ILendVault(provider.lendVault());
        uint totalAssets = lendVault.totalAssets(token);
        uint utilizationCap = lendVault.maxUtilization();
        uint usableTokens = utilizationCap * totalAssets / PRECISION;
        uint usedTokens = lendVault.getTotalDebt(token);
        borrowable = usableTokens>usedTokens?usableTokens - usedTokens:0;
    }
}
