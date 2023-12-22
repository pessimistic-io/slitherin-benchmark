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
import "./IUniswapV3StrategyLogic.sol";
import "./IBorrowerBalanceCalculator.sol";
import "./AddressArray.sol";
import "./UintArray.sol";
import "./UniswapV3StrategyStorage.sol";
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
 * @notice Contract containing logic common to uniswap V3 based strategies
 * @dev UniswapV3StrategyLogic is meant to be called by uniswap v3 strategies via delegateCall only
 * UniswapV3StrategyLogic follows the same inheritance chain as UniswapV3BaseStrategy for this reason
 */
contract UniswapV3StrategyLogic is UniswapV3StrategyStorage, AccessControl, IUniswapV3StrategyLogic {
    using AddressArray for address[];
    using Address for address;
    using SafeERC20 for IERC20;
    using UintArray for uint[];

    /**
     * @param amountHarvested Amount of tokens harvested expressed in terms of stabl token
     */
    event Harvest(uint amountHarvested);

    /**
     * @param amount Amount of tokens withdrawn from the strategy
     */
    event Withdraw(uint amount);
    
    /**
     * @param amount Amount of tokens deposited in the strategy
     */
    event Deposit(uint amount);

    /**
     * @param balanceBefore Balance of strategy in terms of deposit token before changing leverage
     * @param balanceBefore Balance of strategy in terms of deposit token after changing leverage
     * @param leverage New borrower leverage
     */
    event ChangeLeverage(int balanceBefore, int balanceAfter, uint leverage);

    /// @notice Private variable storing the address of the logic contract
    address private immutable self = address(this);

    /**
     * @notice Require that the current call is a delegatecall
     */
    function checkDelegateCall() private view {
        require(address(this) != self, "delegatecall only");
    }

    modifier onlyDelegateCall() {
        checkDelegateCall();
        _;
    }

    /**
     * @notice Fetches the pnl data for the strategy
     * @dev The data is calculated assuming an exit at the current block to realize all profits/losses
     * @dev The profits and losses are reported in terms of the vault's deposit token
     */
    function getPnl(address strategyAddress) external view returns (PNLData memory pnlData) {
        UniswapV3BaseStrategy strategy = UniswapV3BaseStrategy(payable(strategyAddress));
        (,address stableToken, address volatileToken, ) = strategy.addresses();
        IAddressProvider addressProvider = IAddressProvider(strategy.provider());
        {
            ISwapper swapper = ISwapper(addressProvider.swapper());
            pnlData.rewardProfit = int(swapper.getAmountOut(stableToken, strategy.getHarvestable() + strategy.harvested(), strategy.getDepositToken()));
        }

        pnlData.rebalanceLoss = strategy.rebalanceImpact();
        pnlData.slippageLoss = strategy.slippageImpact();

        {
            IOracle oracle = IOracle(addressProvider.oracle());
            ILendVault lendVault = ILendVault(addressProvider.lendVault());
            uint stableDebt = oracle.getValueInTermsOf(
                stableToken,
                lendVault.getDebt(stableToken, strategyAddress),
                strategy.getDepositToken()
            );
            uint volatileDebt = oracle.getValueInTermsOf(
                volatileToken,
                lendVault.getDebt(volatileToken, strategyAddress),
                strategy.getDepositToken()
            );
            pnlData.debtLoss = strategy.interestPaymentImpact() - int(stableDebt) - int(volatileDebt);
        }

        IController controller = IController(addressProvider.controller());
        IStrategyVault vault = IStrategyVault(controller.vaults(strategyAddress));
        pnlData.pnl = int(vault.withdrawn(strategyAddress)) + pnlData.rewardProfit + strategy.balance() - int(vault.deposited(strategyAddress));

        pnlData.priceChangeLoss = pnlData.pnl - pnlData.rewardProfit - pnlData.rebalanceLoss - pnlData.slippageLoss - pnlData.debtLoss;
    }

    /**
     * @notice Swap all available tokens for another token
     * @dev Slippage is calculated and recorded in terms of the vault's deposit token
     */
    function swapTokensTo(address token) public onlyDelegateCall {
        ISwapper swapper = ISwapper(provider.swapper());
        IOracle oracle = IOracle(provider.oracle());
        (address[] memory availableTokens,) = IBorrower(address(this)).getAmounts();

        for (uint i = 0; i<availableTokens.length; i++) {
            if(availableTokens[i]==provider.networkToken() && address(this).balance>0) {
                IWETH(payable(provider.networkToken())).deposit{value: address(this).balance}();
            }
            uint tokenBalance = IERC20(availableTokens[i]).balanceOf(address(this));
            if (tokenBalance>0 && availableTokens[i]!=token) {
                _approve(address(swapper), availableTokens[i], tokenBalance);
                uint amountOut = swapper.swapExactTokensForTokens(availableTokens[i], tokenBalance, token, thresholds.slippage);
                uint valueIn = oracle.getValueInTermsOf(availableTokens[i], tokenBalance, IBorrower(address(this)).getDepositToken());
                uint valueOut = oracle.getValueInTermsOf(token, amountOut, IBorrower(address(this)).getDepositToken());
                int slippage = int(valueOut) - int(valueIn);
                slippageImpact+=slippage;
            }
        }
    }

    /**
     * @notice Transfer specified amount of the deposit token back to the vault
     */
    function transferToVault(uint amount) public onlyDelegateCall {
        IController controller = IController(provider.controller());
        address vault = controller.vaults(address(this));
        emit Withdraw(amount);
        IERC20(IBorrower(address(this)).getDepositToken()).safeTransfer(vault, amount);
    }

    /**
     * @notice Deposit all available funds into the uniswap v3 pool
     * @dev If a uniswap position has not been created, a new one will be minted
     */
    function deposit() public onlyDelegateCall {
        swapTokensTo(addresses.stableToken);
        emit Deposit(IERC20(addresses.stableToken).balanceOf(address(this)));
        address depositToken = IBorrower(address(this)).getDepositToken();
        ILendVault lendVault = ILendVault(provider.lendVault());
        ISwapper swapper = ISwapper(provider.swapper());
        IOracle oracle = IOracle(provider.oracle());
        (, int[] memory borrowAmounts) = IBorrower(address(this)).calculateBorrowAmounts();

        // In case liquidity is out of range, no stable might be needed, in which case we sell whatever stable token is present
        if (borrowAmounts[0]<0) {
            swapper.swapExactTokensForTokens(addresses.stableToken, uint(-borrowAmounts[0]), addresses.volatileToken, thresholds.slippage);
        } else {
            interestPaymentImpact+=int(oracle.getValueInTermsOf(
                addresses.stableToken, uint(borrowAmounts[0]), depositToken
            ));
            lendVault.borrow(addresses.stableToken, uint(borrowAmounts[0]));
        }
        interestPaymentImpact+=int(oracle.getValueInTermsOf(
            addresses.volatileToken, uint(borrowAmounts[1]), depositToken
        ));
        lendVault.borrow(addresses.volatileToken, uint(borrowAmounts[1]));

        if (
            IERC20(addresses.stableToken).balanceOf(address(this))==0 &&
            IERC20(addresses.volatileToken).balanceOf(address(this))==0
        ) return;

        IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
        if (positionId==0) {
            bytes memory mintData = address(integration).functionDelegateCall(abi.encodeWithSelector(
                integration.mint.selector, addresses.positionsManager, addresses.want,
                parameters.tick0, parameters.tick1
            ));
            positionId = abi.decode(mintData, (uint));

            // Update price anchor
            priceAnchor = oracle.getPrice(addresses.volatileToken);
        } else {
            address(integration).functionDelegateCall(abi.encodeWithSelector(
                integration.increaseLiquidity.selector, addresses.positionsManager, positionId, addresses.want
            ));
        }
    }

    /**
     * @notice Withdraws a fraction of the assets from the uniswap pool
     */
    function withdraw(uint fraction) public onlyDelegateCall {
        if (positionId!=0) {
            (,,,,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(addresses.positionsManager).positions(positionId);
            uint toWithdraw = liquidity * fraction / PRECISION;
            IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
            if(toWithdraw>0) {
                address(integration).functionDelegateCall(abi.encodeWithSelector(
                    integration.decreaseLiquidity.selector, addresses.positionsManager, positionId, uint128(toWithdraw)
                ));
                repay(fraction);
                swapTokensTo(addresses.stableToken);
            }
        }
    }

    /**
     * @notice Harvests the fees generated from the uniswap pool
     */
    function harvest() public onlyDelegateCall {
        if (positionId!=0) {
            uint stableBalance = IERC20(addresses.stableToken).balanceOf(address(this));
            IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
            address(integration).functionDelegateCall(abi.encodeWithSelector(
                integration.harvest.selector, addresses.positionsManager, positionId
            ));
            swapTokensTo(addresses.stableToken);
            uint stableHarvested = IERC20(addresses.stableToken).balanceOf(address(this)) - stableBalance;
            IOracle oracle = IOracle(provider.oracle());
            uint amountHarvested = oracle.getValueInTermsOf(addresses.stableToken, stableHarvested, IBorrower(address(this)).getDepositToken());
            harvested+=amountHarvested;
            emit Harvest(amountHarvested);
        }
    }

    /**
     * @notice Repay all the debts that can be repaid using the available tokens
     */
    function repay(uint fraction) public onlyDelegateCall {
        ILendVault lendVault = ILendVault(provider.lendVault());
        ISwapper swapper = ISwapper(provider.swapper());
        IOracle oracle = IOracle(provider.oracle());
        address depositToken = IBorrower(address(this)).getDepositToken();
        (, uint[] memory borrowedAmounts) = IBorrower(address(this)).getDebts();
        uint amountStableRepay = (fraction * borrowedAmounts[0] / PRECISION) + 1;
        uint amountVolatileRepay = (fraction * borrowedAmounts[1] / PRECISION) + 1;

        // Insufficient stable balance to repay debt
        if (
            amountStableRepay>IERC20(addresses.stableToken).balanceOf(address(this)) &&
            amountVolatileRepay<IERC20(addresses.volatileToken).balanceOf(address(this))
        ) {
            uint amountAvailable = IERC20(addresses.volatileToken).balanceOf(address(this));
            uint amountNeeded = amountStableRepay-IERC20(addresses.stableToken).balanceOf(address(this));
            uint amountObtainable = swapper.getAmountOut(addresses.volatileToken, amountAvailable, addresses.stableToken);
            uint amount = Math.min(amountObtainable, amountNeeded);
            swapper.swapTokensForExactTokens(addresses.volatileToken, amount, addresses.stableToken, thresholds.slippage);
        }
        // Insufficient volatile balance to repay debt
        else if (
            amountStableRepay<IERC20(addresses.stableToken).balanceOf(address(this)) &&
            amountVolatileRepay>IERC20(addresses.volatileToken).balanceOf(address(this))
        ) {
            uint amountAvailable = IERC20(addresses.stableToken).balanceOf(address(this));
            uint amountNeeded = amountVolatileRepay-IERC20(addresses.volatileToken).balanceOf(address(this));
            uint amountObtainable = swapper.getAmountOut(addresses.stableToken, amountAvailable, addresses.volatileToken);
            uint amount = Math.min(amountObtainable, amountNeeded);
            swapper.swapTokensForExactTokens(addresses.stableToken, amount, addresses.volatileToken, thresholds.slippage);
        }
        // Revert if failed to swap and get enough funds to repay debts
        if (
            amountStableRepay>IERC20(addresses.stableToken).balanceOf(address(this)) ||
            amountVolatileRepay>IERC20(addresses.volatileToken).balanceOf(address(this))
        ) {
            revert("Unable to repay debts");
        }

        // Record the amount of debt repaid to track pnl
        interestPaymentImpact-=int(oracle.getValueInTermsOf(addresses.stableToken, amountStableRepay, depositToken));
        interestPaymentImpact-=int(oracle.getValueInTermsOf(addresses.volatileToken, amountVolatileRepay, depositToken));

        // Repay debts
        lendVault.repayShares(addresses.stableToken, lendVault.debtShare(addresses.stableToken, address(this)) * fraction / PRECISION);
        lendVault.repayShares(addresses.volatileToken, lendVault.debtShare(addresses.volatileToken, address(this)) * fraction / PRECISION);
    }

    /**
     * @notice This function sets the ticks (range) for the UniswapV3 liquidity position
     * @dev It uses a multiplier to calculate the correct tick range to use
     * @dev This is an public function
     */
    function setTicks(int24 multiplier0, int24 multiplier1) public onlyDelegateCall {
        IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
        require(multiplier0>0 && multiplier1>0, "E1");
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 absTick = currentTick < 0 ? -currentTick : currentTick;
        int24 tickSpacing = pool.tickSpacing();
        absTick -= absTick % tickSpacing;
        currentTick = currentTick < 0 ? -absTick : absTick;
        
        parameters.tick0 = currentTick - multiplier0 * tickSpacing;
        parameters.tick1 = currentTick + multiplier1 * tickSpacing;
    }
    
    /**
     * @notice Function to liquidate everything and transfer all funds to LendVault
     * @notice Called in case it is believed that the borrower won't be able to cover its debts
     * @dev _withdraw is not used here since that will attempt to repay debts which will probably fail
     * if siezeFunds is being called
     * @return tokens Siezed tokens
     * @return amounts Amounts of siezed tokens
     */
    function siezeFunds() external onlyDelegateCall returns (address[] memory tokens, uint[] memory amounts) {
        if (positionId!=0) {
            (,,,,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(addresses.positionsManager).positions(positionId);
            IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
            address(integration).functionDelegateCall(abi.encodeWithSelector(
                integration.decreaseLiquidity.selector, addresses.positionsManager, positionId, uint128(liquidity)
            ));
            provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
                "harvest()"
            ));
        }
        (tokens, amounts) = IBorrower(address(this)).getAmounts();
        for(uint i = 0; i<tokens.length; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).safeTransfer(provider.lendVault(), amounts[i]);
        }

        // Note: Need to update this in case strategy was unable to repay debt fully
        // Update loss from repaying debt
        ILendVault lendVault = ILendVault(provider.lendVault());
        IOracle oracle = IOracle(provider.oracle());
        uint debtStable = lendVault.getDebt(addresses.stableToken, address(this));
        uint debtVolatile = lendVault.getDebt(addresses.volatileToken, address(this));
        interestPaymentImpact-=int(debtStable);
        interestPaymentImpact-=int(oracle.getValueInTermsOf(addresses.volatileToken, debtVolatile, addresses.stableToken));
    }


    /**
     * @notice Reduce leverage in order to pay back the specified debt
     * @param token Token that needs to be paid back
     * @param amount Amount of token that needs to be paid back
     */
    function delever(address token, uint amount) external onlyDelegateCall {
        ISwapper swapper = ISwapper(provider.swapper());
        (address[] memory borrowedTokens, uint[] memory debts) = IBorrower(address(this)).getDebts();

        // Check if the strategy has borrowed the token that the Vault is requesting
        uint index = borrowedTokens.findFirst(token);
        if (index<borrowedTokens.length) {
            uint supplied;
            address otherToken = token==addresses.stableToken?addresses.volatileToken:addresses.stableToken;
            uint requestedAmount; uint otherTokenRequestedAmount;

            {
                IBorrowerBalanceCalculator balanceCalculator = IBorrowerBalanceCalculator(provider.borrowerBalanceCalculator());
                supplied = uint(balanceCalculator.balanceInTermsOf(addresses.stableToken, address(this)));
                // Amount of debt that is needed to free up funds for the LendVault
                uint requestedDebt = debts[index]>amount?debts[index] - amount:0;

                // Amount of token that the strategy should have based on requestedDebt
                requestedAmount = token==addresses.stableToken?requestedDebt + supplied: requestedDebt;

                if (IUniswapV3Pool(addresses.want).token0()==token) {
                    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(parameters.tick0);
                    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(parameters.tick1);
                    uint128 requestedLiquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, requestedAmount);
                    otherTokenRequestedAmount = LiquidityAmounts.getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, requestedLiquidity);
                } else {
                    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(parameters.tick0);
                    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(parameters.tick1);
                    uint128 requestedLiquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, requestedAmount);
                    otherTokenRequestedAmount = LiquidityAmounts.getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, requestedLiquidity);
                }
            }
            // Calculated requested leverage based on requested amounts
            uint totalETHValue = swapper.getETHValue(token, requestedAmount) + swapper.getETHValue(otherToken, otherTokenRequestedAmount);
            uint requestedLeverage = PRECISION * totalETHValue / Math.max(1, swapper.getETHValue(addresses.stableToken, supplied));

            // Reduce leverage until minLeverage
            parameters.leverage = Math.max(parameters.minLeverage, requestedLeverage);
            int balanceBefore = IBorrower(address(this)).balanceOptimized();
            withdraw(PRECISION);
            harvest();
            deposit();
            
            prevCacheUpdateBlock = block.number;
            cachedBalance = IBorrower(address(this)).balance();
            rebalanceImpact += cachedBalance - balanceBefore;
            emit ChangeLeverage(balanceBefore, cachedBalance, parameters.leverage);
        }
    }

    /**
     * @notice Set approval to max for spender if approval isn't high enough
     */
    function _approve(address spender, address token, uint amount) internal {
        uint allowance = IERC20(token).allowance(address(this), spender);
        if(allowance<amount) {
            IERC20(token).safeIncreaseAllowance(spender, 2**256-1-allowance);
        }
    }
}
