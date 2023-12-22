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
 * @notice Abstract base class for all uniswap v3 based strategies
 */
abstract contract UniswapV3BaseStrategy is UniswapV3StrategyStorage, AccessControl, IBorrower {
    using AddressArray for address[];
    using Address for address;
    using SafeERC20 for IERC20;
    using UintArray for uint[];

    /**
     * @notice Event triggered whenever the strategy completely exits the uniswap pool
     * @param balanceAfter Balance of stable token after exiting pool
     */
    event Exit(uint balanceAfter);

    /**
     * @param balanceBefore Balance of strategy in terms of deposit token before rebalancing
     * @param balanceAfter Balance of strategy in terms of deposit token after rebalancing
     */
    event Rebalance(int balanceBefore, int balanceAfter);

    /**
     * @param balanceBefore Balance of strategy in terms of deposit token before setting ticks
     * @param balanceAfter Balance of strategy in terms of deposit token after setting ticks
     * @param tick0 Lower tick
     * @param tick1 Upper tick
     */
    event SetTicks(int balanceBefore, int balanceAfter, int24 tick0, int24 tick1);

    /**
     * @param balanceBefore Balance of strategy in terms of deposit token before changing leverage
     * @param balanceAfter Balance of strategy in terms of deposit token after changing leverage
     * @param leverage New borrower leverage
     */
    event ChangeLeverage(int balanceBefore, int balanceAfter, uint leverage);

    /**
     * @notice Initialize upgradeable contract
     */
    function _UniswapV3BaseStrategy__init(
        address _provider,
        Addresses memory _addresses,
        Thresholds memory _thresholds,
        Parameters memory _parameters
    ) internal onlyInitializing {
        __AccessControl_init(_provider);
        addresses = _addresses;
        thresholds = _thresholds;
        parameters = _parameters;
        _setTicks(_parameters.tick0, _parameters.tick1);
        
        // Input validation
        IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
        require(
            pool.token0()==addresses.stableToken && pool.token1()==addresses.volatileToken ||
            pool.token1()==addresses.stableToken && pool.token0()==addresses.volatileToken,
            "Incorrect token addresses"
        );
        INonfungiblePositionManager(addresses.positionsManager).factory();

        // Update price anchor
        IOracle oracle = IOracle(provider.oracle());
        priceAnchor = oracle.getPrice(addresses.volatileToken);

        // Approvals
        IERC20(addresses.stableToken).safeApprove(provider.lendVault(), 2 ** 256 - 1);
        IERC20(addresses.volatileToken).safeApprove(provider.lendVault(), 2 ** 256 - 1);
        IERC20(addresses.stableToken).safeApprove(provider.swapper(), 2 ** 256 - 1);
        IERC20(addresses.volatileToken).safeApprove(provider.swapper(), 2 ** 256 - 1);
        IERC20(addresses.stableToken).safeApprove(addresses.positionsManager, 2 ** 256 - 1);
        IERC20(addresses.volatileToken).safeApprove(addresses.positionsManager, 2 ** 256 - 1);
    }

    // ---------- Modifiers ----------
    /**
     * @notice Requires that the oracle price is close to the pool price
     * @dev It will trigger a revert if the ammCheck is false
     */
    function _requireAmmCheckPass() internal view {
        require(_ammCheck() == true, "E2");
    }

    modifier requireAmmCheck() {
        _requireAmmCheckPass();
        _;
    }

    // ---------- View Functions ----------

    /**
     * @notice Calculate the balance of the strategy in terms of the strategy vault's deposit token
     * @dev Balance can be negative, indicating how much deposit token is needed to repay the debts
     */
    function balance() public view returns (int) {
        IBorrowerBalanceCalculator balanceCalculator = IBorrowerBalanceCalculator(provider.borrowerBalanceCalculator());
        ISwapper swapper = ISwapper(provider.swapper());
        int stableBalance = balanceCalculator.balanceInTermsOf(addresses.stableToken, address(this));
        if (stableBalance>0) {
            return int(swapper.getAmountOut(addresses.stableToken, uint(stableBalance), getDepositToken()));
        } else {
            return -int(swapper.getAmountIn(getDepositToken(), uint(-stableBalance), addresses.stableToken));
        }
    }
    
    /**
     * @notice Returns cached balance if balance has previously been calculated
     * otherwise sets the cache with newly calculated balance
     */
    function balanceOptimized() public returns (int) {
        if (block.number>prevCacheUpdateBlock) {
            _updateCache();
        }
        return cachedBalance;
    }

    /**
     * @notice Returns all the tokens in the borrower's posession after liquidating everything
     * @dev Returned amounts are always in order stable token then volatile token and deposit token
     * @dev Deposit token is only included if it is not the same as stable token
     */
    function getAmounts() public view returns (address[] memory tokens, uint[] memory amounts) {
        uint128 liquidity;
        if (positionId!=0) {
            (,,,,,,,liquidity,,,,) = INonfungiblePositionManager(addresses.positionsManager).positions(positionId);
        }
        IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(parameters.tick0),
            TickMath.getSqrtRatioAtTick(parameters.tick1),
            liquidity
        );

        address depositToken = getDepositToken();
        if (depositToken!=addresses.stableToken && depositToken!=addresses.volatileToken) {
            tokens = new address[](3);
            amounts = new uint256[](3);
            tokens[2] = depositToken;
            amounts[2] = IERC20(depositToken).balanceOf(address(this));
        } else {
            tokens = new address[](2);
            amounts = new uint256[](2);
        }

        tokens[0] = addresses.stableToken;
        tokens[1] = addresses.volatileToken;
        amounts[0] = pool.token0()==addresses.stableToken?amount0:amount1;
        amounts[1] = pool.token1()==addresses.volatileToken?amount1:amount0;
        amounts[0]+=IERC20(addresses.stableToken).balanceOf(address(this));
        amounts[1]+=IERC20(addresses.volatileToken).balanceOf(address(this));
        amounts[0]+=getHarvestable();
    }

    /**
     * @notice Returns all the tokens borrowed and amounts of borrowed tokens
     * @dev Returned amounts are always in order stable token then volatile token
     */
    function getDebts() public view returns (address[] memory tokens, uint[] memory amounts) {
        ILendVault lendVault = ILendVault(provider.lendVault());
        tokens = new address[](2);
        amounts = new uint[](2);
        tokens[0] = addresses.stableToken;
        tokens[1] = addresses.volatileToken;
        amounts[0] = lendVault.getDebt(addresses.stableToken, address(this));
        amounts[1] = lendVault.getDebt(addresses.volatileToken, address(this));
    }

    /**
     * @notice Caluclates the pending fees harvestable from the 
     * uniswap pool in terms of the stable token
     */
    function getHarvestable() public view returns (uint harvestable) {
        IUniswapV3Pool pool = IUniswapV3Pool(addresses.want);
        ISwapper swapper = ISwapper(provider.swapper());
        IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
        (uint feeAmt0, uint feeAmt1) = integration.getPendingFees(addresses.positionsManager, positionId);
        if (pool.token0()==addresses.stableToken) {
            harvestable = feeAmt0 + swapper.getAmountOut(addresses.volatileToken, feeAmt1, addresses.stableToken);
        } else {
            harvestable = feeAmt1 + swapper.getAmountOut(addresses.volatileToken, feeAmt0, addresses.stableToken);
        }
    }

    /**
     * @notice Calculate the fraction of the debt from stable token
     * fraction = PRECISION * usdDebt_stable/(usdDebt_stable + usdDebt_volatile)
     */
    function getStableDebtFraction() external view returns (uint ratio) {
        IOracle oracle = IOracle(provider.oracle());
        (,uint[] memory debts) = getDebts();
        return (PRECISION * debts[0]) / Math.max(1, debts[0] + oracle.getValueInTermsOf(addresses.volatileToken, debts[1], addresses.stableToken));
    }

    /**
     * @notice Fetches the pnl data for the strategy
     * @dev The data is calculated assuming an exit at the current block to realize all profits/losses
     * @dev The profits and losses are reported in terms of the vault's deposit token
     */
    function getPnl() external view returns (int pnl, int rewardProfit, int rebalanceLoss, int slippageLoss, int debtLoss, int priceChangeLoss) {
        IUniswapV3StrategyLogic logic = IUniswapV3StrategyLogic(provider.uniswapV3StrategyLogic());
        IUniswapV3StrategyLogic.PNLData memory data = logic.getPnl(address(this));
        (pnl, rewardProfit, rebalanceLoss, slippageLoss, debtLoss, priceChangeLoss) = (
            data.pnl,
            data.rewardProfit,
            data.rebalanceLoss,
            data.slippageLoss,
            data.debtLoss,
            data.priceChangeLoss
        );
    }

    /**
     * @notice Fetch the deposit token for the strategy vault
     */
    function getDepositToken() public view returns (address depositToken) {
        IController controller = IController(provider.controller());
        IStrategyVault vault = IStrategyVault(controller.vaults(address(this)));
        depositToken = vault.depositToken();
    }

    /**
     * @notice Perform amm check and check if strategy needs rebalancing, returns equity, price change and amount to rebalance by
     * @return ammCheck Wether uniswap pool and oracle price are close to each other
     * @return health Health of the strategy calculated by the LendVault
     * @return equity Total asset value minus total debt value reported in terms of the deposit token
     * @return currentPrice current price of the volatile token
     */
    function heartBeat()
        public
        view
        returns (
            bool ammCheck,
            int256 health,
            int256 equity,
            uint256 currentPrice
        )
    {
        ILendVault lendVault = ILendVault(provider.lendVault());
        IOracle oracle = IOracle(provider.oracle());
        equity = balance();
        ammCheck = _ammCheck();
        health = lendVault.checkHealth(address(this));
        currentPrice = oracle.getPrice(addresses.volatileToken);
    }

    // ---------- Parameter Update Functions ----------

    /**
     * @notice Set the leverage for the strategy
     * @dev Changing leverage will trigger a rebalance
     */
    function setLeverage(uint _leverage) external restrictAccess(GOVERNOR) {
        require(_leverage>parameters.minLeverage && _leverage<parameters.maxLeverage, "E8");
        int balanceBefore = balanceOptimized();
        parameters.leverage = _leverage;
        _withdraw(PRECISION);
        _harvest();
        _deposit();
        _updateCache();
        rebalanceImpact += cachedBalance - balanceBefore;

        emit ChangeLeverage(balanceBefore, cachedBalance, _leverage);
    }

    /**
     * @notice Set the bottom limit for the leverage when changing leverage by keeper or LendVault
     */
    function setMinLeverage(uint _minLeverage) external restrictAccess(GOVERNOR) {
        require(_minLeverage>=PRECISION, "E8");
        parameters.minLeverage = _minLeverage;
    }

    /**
     * @notice Set the upper limit for leverage
     */
    function setMaxLeverage(uint _maxLeverage) external restrictAccess(GOVERNOR) {
        require(_maxLeverage>=PRECISION, "E8");
        parameters.maxLeverage = _maxLeverage;
    }

    /**
     * @notice Set the thresholds used during calculation
     */
    function setThresholds(Thresholds memory _thresholds) external restrictAccess(GOVERNOR) {
        // Max limit of 20% deviation between pool and oracle prices
        require(_thresholds.ammCheckThreshold<=2*PRECISION/10, "E9");
        // Max limit of 100% on slippage
        require(_thresholds.slippage <= PRECISION, "E12");
        thresholds = _thresholds;
    }

    // ---------- Keeper Functions ----------

    /**
     * @notice Rebalances the strategy
     * @dev It will payback any excess debt or liquidate part of the LP Position to achieve the
     * Pseudo Delta Neutral balance
     * @dev It triggers a partial or full liquidation in order to re-set the effective leverage of the position
     * @dev During rebalance impermanent loss could be realized
     */
    function rebalance() external restrictAccess(GOVERNOR | KEEPER) requireAmmCheck {
        int balanceBefore = balanceOptimized();
        // Withdraw partially, repay debts partially and deposit again
        _withdraw(PRECISION);
        _deposit();

        // Update price anchor
        IOracle oracle = IOracle(provider.oracle());
        priceAnchor = oracle.getPrice(addresses.volatileToken);
        
        _updateCache();
        rebalanceImpact += cachedBalance - balanceBefore;
        emit Rebalance(balanceBefore, cachedBalance);
    }

    /**
     * @notice This function sets the ticks (range) for the UniswapV3 liquidity position
     * @dev It uses a multiplier to calculate the correct tick range to use
     * @dev When changing the ticks a new position id is generated as the liquidity is completely exited and funds are re-deposited.
     */
    function setTicks(int24 multiplier0, int24 multiplier1) external restrictAccess(KEEPER | GOVERNOR) requireAmmCheck {
        int balanceBefore = balanceOptimized();
        _withdraw(PRECISION);
        _harvest();
        _setTicks(multiplier0, multiplier1);
        positionId = 0;
        _deposit();

        // Update price anchor
        IOracle oracle = IOracle(provider.oracle());
        priceAnchor = oracle.getPrice(addresses.volatileToken);

        _updateCache();
        rebalanceImpact += cachedBalance - balanceBefore;
        emit SetTicks(balanceBefore, cachedBalance, parameters.tick0, parameters.tick1);
    }

    /**
     * @notice Harvest the rewards from the liquidity position, swap them and reinvest them
     */
    function harvest() restrictAccess(GOVERNOR | KEEPER | CONTROLLER) external requireAmmCheck {
        _harvest();
        _deposit();
        _updateCache();
    }

    /**
     * @notice Exit liquidity position and repay all debts
     */
    function exit() external restrictAccess(LENDVAULT | GOVERNOR | KEEPER | GUARDIAN) requireAmmCheck {
        _withdraw(PRECISION);
        _harvest();
        _updateCache();
    }
    
    // ---------- LendVault Functions ----------

    /**
     * @notice Function to liquidate everything and transfer all funds to LendVault
     * @notice Called in case it is believed that the borrower won't be able to cover its debts
     * @dev _withdraw is not used here since that will attempt to repay debts which will probably fail
     * if siezeFunds is being called
     * @return tokens Siezed tokens
     * @return amounts Amounts of siezed tokens
     */
    function siezeFunds() external restrictAccess(LENDVAULT) returns (address[] memory tokens, uint[] memory amounts) {
        bytes memory returnData = provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "siezeFunds()"
        ));
        _updateCache();
        (tokens, amounts) = abi.decode(returnData, (address[], uint[]));
    }

    /**
     * @notice Reduce leverage in order to pay back the specified debt
     * @param token Token that needs to be paid back
     * @param amount Amount of token that needs to be paid back
     */
    function delever(address token, uint amount) external restrictAccess(LENDVAULT | KEEPER | GOVERNOR) {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "delever(address,uint256)",
            token, amount
        ));
        _updateCache();
    }

    // ---------- Controller Functions ----------

    /**
     * @notice Deposits all available funds into the appropriate liquidity position
     * @dev The amount of stable token to be borrowed is calculated first based on leverage
     * Then, based on the ratio of tokens needed based on ticks, the amount of volatile token
     * to borrow is calculated
     */
    function deposit() external restrictAccess(GOVERNOR | CONTROLLER) {
        _deposit();
        _updateCache();
    }

    /**
     * @notice Permissioned function called from controller or vault to withdraw to vault
     */
    function withdraw(uint256 amount) external restrictAccess(GOVERNOR | CONTROLLER) {
        uint equity = uint(balanceOptimized());
        uint fraction = amount * PRECISION / equity;
        _withdraw(fraction);
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "swapTokensTo(address)",
            getDepositToken()
        ));
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "transferToVault(uint256)",
            Math.min(amount, IERC20(getDepositToken()).balanceOf(address(this)))
        ));
        _updateCache();
    }

    /**
     * @notice Permissioned function called from controller or vault to withdraw all funds to vault
     */
    function withdrawAll() external restrictAccess(GOVERNOR | CONTROLLER) {
        _withdraw(PRECISION);
        _harvest();
        address depositToken = getDepositToken();
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "swapTokensTo(address)",
            depositToken
        ));
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "transferToVault(uint256)",
            IERC20(depositToken).balanceOf(address(this))
        ));
        _updateCache();
    }

    /**
     * @notice Permissioned function for controller to withdraw a token from the borrower
     */
    function withdrawOther(address token) external restrictAccess(GOVERNOR | CONTROLLER) {
        uint tokenBalance = IERC20(token).balanceOf(address(this));
        require(tokenBalance>0, "E21");
        IERC20(token).safeTransfer(provider.controller(), tokenBalance);
    }

    // ---------- Internal Helper Functions ----------

    /**
     * @notice Deposit all available funds into the uniswap v3 pool
     * @dev If a uniswap position has not been created, a new one will be minted
     */
    function _deposit() internal {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "deposit()"
        ));
    }

    /**
     * @notice Withdraws a fraction of the assets from the uniswap pool
     */
    function _withdraw(uint fraction) internal {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "withdraw(uint256)", fraction
        ));
    }

    /**
     * @notice Harvests the fees generated from the uniswap pool
     */
    function _harvest() internal {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "harvest()"
        ));
    }

    /**
     * @notice Check if uniswap pool price matches the oracle price
     */
    function _ammCheck() internal view returns (bool) {
        IUniswapV3Integration integration = IUniswapV3Integration(provider.uniswapV3Integration());
        IOracle oracle = IOracle(provider.oracle());
        uint256 ratio = (integration.pairPrice(addresses.want, addresses.volatileToken) * PRECISION) /
            oracle.getPriceInTermsOf(addresses.volatileToken, addresses.stableToken);
        return Math.max(PRECISION, ratio)-Math.min(PRECISION, ratio) < thresholds.ammCheckThreshold;
    }

    /**
     * @notice This function sets the ticks (range) for the UniswapV3 liquidity position
     * @dev It uses a multiplier to calculate the correct tick range to use
     * @dev This is an internal function
     */
    function _setTicks(int24 multiplier0, int24 multiplier1) internal {
        IUniswapV3StrategyLogic logic = IUniswapV3StrategyLogic(provider.uniswapV3StrategyLogic());
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSelector(
            logic.setTicks.selector,
            multiplier0, multiplier1
        ));
    }

    /**
     * @notice Update the stored cached balances
     * @dev Should be called after any function that deals with movement of funds
     */
    function _updateCache() internal {
        prevCacheUpdateBlock = block.number;
        cachedBalance = balance();
    }

    receive() external payable {
        IWETH(payable(provider.networkToken())).deposit{value: address(this).balance}();
    }
}
