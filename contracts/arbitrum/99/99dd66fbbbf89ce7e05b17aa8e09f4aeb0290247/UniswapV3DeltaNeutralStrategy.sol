// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ISwapper.sol";
import "./IOracle.sol";
import "./IUniswapV3StrategyData.sol";
import "./AddressArray.sol";
import "./UniswapV3BaseStrategy.sol";
import "./Math.sol";
import "./Address.sol";
import "./ERC20.sol";

/**
 * @notice Strategy that borrows from LendVault and deposits into a uni v3 pool
 */
contract UniswapV3DeltaNeutralStrategy is UniswapV3BaseStrategy {
    using AddressArray for address[];

    /**
     * @notice Initialize upgradeable contract
     */
    function initialize(
        address _provider,
        Addresses memory _addresses,
        Thresholds memory _thresholds,
        Parameters memory _parameters
    ) external virtual initializer {
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
     * @notice Calculate the token amounts that the strategy will borrow for a given deposit amount and lend vault reserves
     * @param amount The amount to be deposited to the strategy
     * @param lendTokens The tokens available for borrowing from the lend vault
     * @param availableLendTokens The amount of each token in lendTokens that is available for borrowing
     * @return borrowTokens The tokens that the strategy would borrow
     * @return borrowAmounts The amount of each token in borrowTokens that would be borrowed
     */
    function getBorrowForDeposit(
        uint amount,
        address[] memory lendTokens,
        uint[] memory availableLendTokens
    ) external view returns (address[] memory borrowTokens, uint[] memory borrowAmounts) {
        // Calculate supplied amount based on existing token balances and input amount
        {
            ISwapper swapper = ISwapper(provider.swapper());
            amount = swapper.getAmountOut(getDepositToken(), amount, addresses.stableToken);
            amount+=IERC20(addresses.stableToken).balanceOf(address(this));
            amount+=swapper.getAmountOut(addresses.volatileToken, IERC20(addresses.volatileToken).balanceOf(address(this)), addresses.stableToken);
        }
        {
            address depositToken = getDepositToken();
            if (addresses.stableToken!=depositToken) {
                amount+=ISwapper(provider.swapper()).getAmountOut(depositToken, IERC20(depositToken).balanceOf(address(this)), addresses.stableToken);
            }
        }

        // Calculate amount of stable and volatile tokens that need to be borrowed based on supplied amount
        uint borrowStable; uint borrowVolatile;
        {
            (uint stableRatio, uint volatileRatio, uint volatileRatioInStablePrice) = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getPoolRatios(address(this));
            int borrowStableInt = int((amount * parameters.leverage * stableRatio / (stableRatio + volatileRatioInStablePrice)) / PRECISION) - int(amount);
            borrowVolatile = uint(borrowStableInt + int(amount)) * volatileRatio / Math.max(1, stableRatio);
            borrowStable = borrowStableInt<0?0:uint(borrowStableInt);
        }

        // Get tokens that need to be borrowed to satisfy borrowStable and borrowVolatile
        (address[] memory stableBorrowTokens, uint[] memory stableBorrowAmounts) = _getBorrowTokens(addresses.stableToken, borrowStable, lendTokens, availableLendTokens);
        (address[] memory volatileBorrowTokens, uint[] memory volatileBorrowAmounts) = _getBorrowTokens(addresses.volatileToken, borrowVolatile, lendTokens, availableLendTokens);

        // Combine stable and volatile borrow arrays
        borrowTokens = new address[](stableBorrowTokens.length + volatileBorrowTokens.length);
        borrowAmounts = new uint[](stableBorrowTokens.length + volatileBorrowTokens.length);
        for (uint i = 0; i<borrowTokens.length; i++) {
            borrowTokens[i] = i<stableBorrowTokens.length?stableBorrowTokens[i]:volatileBorrowTokens[i-stableBorrowTokens.length];
            borrowAmounts[i] = i<stableBorrowAmounts.length?stableBorrowAmounts[i]:volatileBorrowAmounts[i-stableBorrowAmounts.length];
        }
    }

    /**
     * @notice Get the tokens that would be borrowed if desiredBorrow amount of token needs to be borrowed
     * @dev If the lend vault can't cover the borrow of the desired token, then interchangeable tokens
     * for the token will be borrowed instead, this is included in the returned arrays of this function
     */
    function _getBorrowTokens(
        address token,
        uint desiredBorrow,
        address[] memory lendTokens,
        uint[] memory availableLendTokens
    ) internal view returns (address[] memory tokens, uint[] memory amounts) {
        tokens = new address[](1 + interchangeableTokens[token].length);
        tokens[0] = token;
        amounts = new uint[](1 + interchangeableTokens[token].length);
        amounts[0] = Math.min(availableLendTokens[lendTokens.findFirst(token)], desiredBorrow);
        uint borrowSum = amounts[0];
        for (uint i = 0; i<interchangeableTokens[token].length; i++) {
            tokens[i+1] = interchangeableTokens[token][i];
            uint borrowable = availableLendTokens[lendTokens.findFirst(interchangeableTokens[token][i])];
            uint value = IOracle(provider.oracle()).getValueInTermsOf(interchangeableTokens[token][i], borrowable, token);
            amounts[i+1] = borrowable * Math.min(value, (desiredBorrow - borrowSum)) / Math.max(1, value);
            borrowSum+=Math.min(value, (desiredBorrow - borrowSum));
        }
        if (borrowSum<desiredBorrow) {
            amounts[0]+=desiredBorrow - borrowSum;
        }
    }

    /// @inheritdoc UniswapV3BaseStrategy
    function getAddresses() public view virtual override returns (address want, address stableToken, address volatileToken, address positionsManager) {
        want = addresses.want;
        stableToken = addresses.stableToken;
        volatileToken = addresses.volatileToken;
        positionsManager = addresses.positionsManager;
    }

    /// @inheritdoc UniswapV3BaseStrategy
    function strategyType() external pure virtual override returns (string memory) {
        return "Delta Neutral";
    }
}
