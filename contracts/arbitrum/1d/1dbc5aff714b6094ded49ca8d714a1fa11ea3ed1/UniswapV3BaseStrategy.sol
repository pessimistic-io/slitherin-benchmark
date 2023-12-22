// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./IAddressProvider.sol";
import "./IUniswapV3BaseStrategy.sol";
import "./ISwapper.sol";
import "./IOracle.sol";
import "./IController.sol";
import "./IStrategyVault.sol";
import "./ILendVault.sol";
import "./IWETH.sol";
import "./IUniswapV3Integration.sol";
import "./IUniswapV3StrategyLogic.sol";
import "./IUniswapV3StrategyData.sol";
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
     * @param leverage New borrower leverage
     * @param tick0 New lower tick
     * @param tick1 New upper tick
     */
    event SetLeverageAndTicks(uint leverage, int24 tick0, int24 tick1);

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

    /**
     * @notice Update the stored cached balances
     * @dev Should be called after any function that deals with movement of funds
     */
    function updateCache() public {
        IBorrowerBalanceCalculator balanceCalculator = IBorrowerBalanceCalculator(provider.borrowerBalanceCalculator());
        cache.prevCacheUpdateBlock = block.number;
        (cache.borrowedTokens, cache.borrowedAmounts, cache.availableTokens, cache.availableAmounts) = balanceCalculator.calculateDebtsAndLeftovers(address(this));
    }

    function updateTrackers() public {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature("updateTrackers()"));
    }

    modifier trackPriceChangeImpact() {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature("trackPriceChangeImpact()"));
        _;
        updateTrackers();
    } 

    // ---------- View Functions ----------

    /**
     * @notice Calculate the balance of the strategy in terms of the strategy vault's deposit token
     * @dev Balance can be negative, indicating how much deposit token is needed to repay the debts
     */
    function balance() public view returns (int) {
        IBorrowerBalanceCalculator balanceCalculator = IBorrowerBalanceCalculator(provider.borrowerBalanceCalculator());
        int stableBalance = balanceCalculator.balanceInTermsOf(getDepositToken(), address(this));
        return stableBalance;
    }

    /**
     * @notice Returns the value of all the assets in the borrower's possession expressed
     * in terms of the borrower's vault's deposit token
     */
    function tvl() public view returns (uint currentTvl) {
        currentTvl = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getTVL(address(this));
    }
    
    /**
     * @notice Returns cached balance if balance has previously been calculated
     * otherwise sets the cache with newly calculated balance
     */
    function balanceOptimized() public returns (int) {
        if (block.number>cache.prevCacheUpdateBlock) {
            updateCache();
        }
        int optimizedBalance;
        ISwapper swapper = ISwapper(provider.swapper());
        // If any debt is greater than 0, availableAmounts will all be 0
        if (cache.borrowedAmounts.sum()>0) {
            for (uint i = 0; i<cache.borrowedTokens.length; i++) {
                // balance-=int(oracle.getValueInTermsOf(borrowedTokens[i], borrowedAmounts[i], token));
                optimizedBalance-=int(swapper.getAmountIn(getDepositToken(), cache.borrowedAmounts[i], cache.borrowedTokens[i]));
            }
        } else {
            for (uint i = 0; i<cache.availableTokens.length; i++) {
                optimizedBalance+=int(swapper.getAmountOut(cache.availableTokens[i], cache.availableAmounts[i], getDepositToken()));
                // balance+=int(oracle.getValueInTermsOf(availableTokens[i], availableAmounts[i], token));
            }
        }
        return optimizedBalance;
    }
    
    /**
     * @notice Returns cached balance if balance has previously been calculated
     * otherwise sets the cache with newly calculated balance
     */
    function balanceOptimizedWithoutSlippage() public returns (int) {
        if (block.number>cache.prevCacheUpdateBlock) {
            updateCache();
        }
        int balanceWithoutSlippage;
        IOracle oracle = IOracle(provider.oracle());
        // If any debt is greater than 0, availableAmounts will all be 0
        if (cache.borrowedAmounts.sum()>0) {
            for (uint i = 0; i<cache.borrowedTokens.length; i++) {
                balanceWithoutSlippage-=int(oracle.getValueInTermsOf(cache.borrowedTokens[i], cache.borrowedAmounts[i], getDepositToken()));
            }
        } else {
            for (uint i = 0; i<cache.availableTokens.length; i++) {
                balanceWithoutSlippage+=int(oracle.getValueInTermsOf(cache.availableTokens[i], cache.availableAmounts[i], getDepositToken()));
            }
        }
        return balanceWithoutSlippage;
    }

    /**
     * @notice Returns all the tokens in the borrower's posession after liquidating everything
     * @dev Returned amounts are always in order stable token then volatile token and deposit token
     * @dev Deposit token is only included if it is not the same as stable token
     */
    function getAmounts() public view returns (address[] memory tokens, uint[] memory amounts) {
        (tokens, amounts) = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getAmounts(address(this));
    }

    /**
     * @notice Returns all the tokens borrowed and amounts of borrowed tokens
     * @dev Returned amounts are always in order stable token then volatile token
     */
    function getDebts() public view returns (address[] memory tokens, uint[] memory amounts) {
        (tokens, amounts) = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getDebts(address(this));
    }

    /**
     * @notice Caluclates the pending fees harvestable from the 
     * uniswap pool in terms of the stable token
     */
    function getHarvestable() public view returns (uint harvestable) {
        harvestable = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getHarvestable(address(this));
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
    function getPnl() external view returns (IUniswapV3StrategyData.PNLData memory data) {
        data = IUniswapV3StrategyData(provider.uniswapV3StrategyData()).getPnl(address(this));
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
     * @notice Update the strategy leverage and tick range
     * @dev This function can be used to change leverage, rebalance and set ticks,
     * since all of them involve a complete withdrawal followed by strategy parameter
     * changes and a new deposit
     * @dev Adding a tick update with leverage change and rebalance has the benefit of
     * ensuring the uniswap pool tick stays within range as well as ensuring that the
     * borrowed amounts are in the desired ratio based on the strategy leverage
     */
    function setLeverageAndTicks(
        uint _leverage,
        int24 _multiplier0,
        int24 _multiplier1
    ) external restrictAccess(KEEPER | GOVERNOR) requireAmmCheck trackPriceChangeImpact {
        require(_leverage>parameters.minLeverage && _leverage<parameters.maxLeverage, "E8");
        _withdraw(PRECISION);
        _harvest();
        parameters.leverage = _leverage;
        _setTicks(_multiplier0, _multiplier1);
        positionId = 0;
        numRebalances+=1;
        _deposit();

        // Update price anchor
        IOracle oracle = IOracle(provider.oracle());
        priceAnchor = oracle.getPrice(addresses.volatileToken);

        emit SetLeverageAndTicks(_leverage, parameters.tick0, parameters.tick1);
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
     * @notice Harvest the rewards from the liquidity position, swap them and reinvest them
     */
    function harvest() restrictAccess(GOVERNOR | KEEPER | CONTROLLER) external requireAmmCheck trackPriceChangeImpact {
        _harvest();
        // _deposit();
    }

    /**
     * @notice Exit liquidity position and repay all debts
     */
    function exit() external restrictAccess(LENDVAULT | GOVERNOR | KEEPER | GUARDIAN) requireAmmCheck trackPriceChangeImpact {
        _withdraw(PRECISION);
        _harvest();

        emit Exit(IERC20(addresses.stableToken).balanceOf(address(this)));
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

        (tokens, amounts) = abi.decode(returnData, (address[], uint[]));
    }

    /**
     * @notice Reduce leverage in order to pay back the specified debt
     * @param token Token that needs to be paid back
     * @param amount Amount of token that needs to be paid back
     */
    function delever(address token, uint amount) external restrictAccess(LENDVAULT | KEEPER | GOVERNOR) trackPriceChangeImpact {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "delever(address,uint256)",
            token, amount
        ));
    }

    // ---------- Controller Functions ----------

    /**
     * @notice Deposits all available funds into the appropriate liquidity position
     * @dev The amount of stable token to be borrowed is calculated first based on leverage
     * Then, based on the ratio of tokens needed based on ticks, the amount of volatile token
     * to borrow is calculated
     */
    function deposit() external restrictAccess(GOVERNOR | CONTROLLER) trackPriceChangeImpact {
        _deposit();
    }

    /**
     * @notice Permissioned function called from controller or vault to withdraw to vault
     */
    function withdraw(uint256 amount) external restrictAccess(GOVERNOR | CONTROLLER) trackPriceChangeImpact {
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "swapTokensTo(address)",
            getDepositToken()
        ));
        uint currentBalance = IERC20(getDepositToken()).balanceOf(address(this));
        if (currentBalance<amount) {
            uint extraNeeded = amount - currentBalance;
            uint fraction = extraNeeded * PRECISION / uint(balanceOptimized());
            _withdraw(fraction);
            provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
                "swapTokensTo(address)",
                getDepositToken()
            ));
        }
        provider.uniswapV3StrategyLogic().functionDelegateCall(abi.encodeWithSignature(
            "transferToVault(uint256)",
            Math.min(amount, IERC20(getDepositToken()).balanceOf(address(this)))
        ));
    }

    /**
     * @notice Permissioned function called from controller or vault to withdraw all funds to vault
     */
    function withdrawAll() external restrictAccess(GOVERNOR | CONTROLLER) trackPriceChangeImpact {
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
        realizedPriceChangeImpact+=unrealizedPriceChangeImpact * int(fraction) / int(PRECISION);
        unrealizedPriceChangeImpact = unrealizedPriceChangeImpact * (int(PRECISION) - int(fraction)) / int(PRECISION);
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

    receive() external payable {
        IWETH(payable(provider.networkToken())).deposit{value: address(this).balance}();
    }
}
