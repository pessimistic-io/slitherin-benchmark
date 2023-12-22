// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "./EnumerableSetUpgradeable.sol";
import "./SafeCastUpgradeable.sol";

import "./ILiquidityPool.sol";

import "./AMMModule.sol";
import "./LiquidityPoolShutdownModule.sol";
import "./PerpetualModule.sol";

import "./Getter.sol";
import "./PerpetualShutdown.sol";
import "./Governance.sol";
import "./LibraryEvents.sol";
import "./Storage.sol";
import "./Type.sol";

/**
 * This is a minimal pool implementation for DAO pool after Dec.1 2022.
 */
contract LiquidityPoolShutdown is Storage, PerpetualShutdown, Getter, Governance, LibraryEvents {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using SafeCastUpgradeable for uint256;
    using PerpetualModule for PerpetualStorage;
    using LiquidityPoolShutdownModule for LiquidityPoolStorage;
    using AMMModule for LiquidityPoolStorage;

    receive() external payable {
        revert("contract does not accept ether");
    }

    /**
     * @notice  Begin shutdown.
     *
     *          The same as Governance.setEmergencyState(SET_ALL_PERPETUALS_TO_EMERGENCY_STATE).
     *          CAUTION: anyone can call this. make sure the Oracle is working.
     */
    function beginShutdown() public syncState(true) {
        _liquidityPool.setAllPerpetualsToEmergencyState();
    }

    // shutdown /**
    // shutdown  * @notice  Initialize the liquidity pool and set up its configuration
    // shutdown  *
    // shutdown  * @param   operator                The address of operator which should be current pool creator.
    // shutdown  * @param   collateral              The address of collateral token.
    // shutdown  * @param   collateralDecimals      The decimals of collateral token, to support token without decimals interface.
    // shutdown  * @param   governor                The address of governor, who is able to call governance methods.
    // shutdown  * @param   initData                A bytes array contains data to initialize new created liquidity pool.
    // shutdown  */
    // shutdown function initialize(
    // shutdown     address operator,
    // shutdown     address collateral,
    // shutdown     uint256 collateralDecimals,
    // shutdown     address governor,
    // shutdown     bytes calldata initData
    // shutdown ) external override initializer {
    // shutdown     _liquidityPool.initialize(
    // shutdown         _msgSender(),
    // shutdown         collateral,
    // shutdown         collateralDecimals,
    // shutdown         operator,
    // shutdown         governor,
    // shutdown         initData
    // shutdown     );
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Create new perpetual of the liquidity pool.
    // shutdown  *          The operator can create perpetual only when the pool is not running or isFastCreationEnabled is true.
    // shutdown  *          Otherwise a perpetual can only be create by governor (say, through voting).
    // shutdown  *
    // shutdown  * @param   oracle              The oracle's address of the perpetual.
    // shutdown  * @param   baseParams          The base parameters of the perpetual, see whitepaper for details.
    // shutdown  * @param   riskParams          The risk parameters of the perpetual,
    // shutdown  *                              Must be within range [minRiskParamValues, maxRiskParamValues].
    // shutdown  * @param   minRiskParamValues  The minimum values of risk parameters.
    // shutdown  * @param   maxRiskParamValues  The maximum values of risk parameters.
    // shutdown  */
    // shutdown function createPerpetual(
    // shutdown     address oracle,
    // shutdown     int256[9] calldata baseParams,
    // shutdown     int256[9] calldata riskParams,
    // shutdown     int256[9] calldata minRiskParamValues,
    // shutdown     int256[9] calldata maxRiskParamValues
    // shutdown ) external onlyNotUniverseSettled {
    // shutdown     if (!_liquidityPool.isRunning || _liquidityPool.isFastCreationEnabled) {
    // shutdown         require(
    // shutdown             _msgSender() == _liquidityPool.getOperator(),
    // shutdown             "only operator can create perpetual"
    // shutdown         );
    // shutdown     } else {
    // shutdown         require(_msgSender() == _liquidityPool.governor, "only governor can create perpetual");
    // shutdown     }
    // shutdown     _liquidityPool.createPerpetual(
    // shutdown         oracle,
    // shutdown         baseParams,
    // shutdown         riskParams,
    // shutdown         minRiskParamValues,
    // shutdown         maxRiskParamValues
    // shutdown     );
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Set the liquidity pool to running state. Can be call only once by operater.m n
    // shutdown  */
    // shutdown function runLiquidityPool() external override onlyOperator {
    // shutdown     require(!_liquidityPool.isRunning, "already running");
    // shutdown     _liquidityPool.runLiquidityPool();
    // shutdown }

    /**
     * @notice  If you want to get the real-time data, call this function first
     */
    function forceToSyncState() public syncState(false) {}

    // shutdown /**
    // shutdown  * @notice  Add liquidity to the liquidity pool.
    // shutdown  *          Liquidity provider deposits collaterals then gets share tokens back.
    // shutdown  *          The ratio of added cash to share token is determined by current liquidity.
    // shutdown  *          Can only called when the pool is running.
    // shutdown  *
    // shutdown  * @param   cashToAdd   The amount of cash to add. always use decimals 18.
    // shutdown  */
    // shutdown function addLiquidity(int256 cashToAdd)
    // shutdown     external
    // shutdown     override
    // shutdown     onlyNotUniverseSettled
    // shutdown     syncState(false)
    // shutdown     nonReentrant
    // shutdown {
    // shutdown     require(_liquidityPool.isRunning, "pool is not running");
    // shutdown     _liquidityPool.addLiquidity(_msgSender(), cashToAdd);
    // shutdown }

    // shutdown /**
    // shutdown  * @notice  Remove liquidity from the liquidity pool.
    // shutdown  *          Liquidity providers redeems share token then gets collateral back.
    // shutdown  *          The amount of collateral retrieved may differ from the amount when adding liquidity,
    // shutdown  *          The index price, trading fee and positions holding by amm will affect the profitability of providers.
    // shutdown  *          Can only called when the pool is running.
    // shutdown  *
    // shutdown  * @param   shareToRemove   The amount of share token to remove. The amount always use decimals 18.
    // shutdown  * @param   cashToReturn    The amount of cash(collateral) to return. The amount always use decimals 18.
    // shutdown  */
    // shutdown function removeLiquidity(int256 shareToRemove, int256 cashToReturn)
    // shutdown     external
    // shutdown     override
    // shutdown     nonReentrant
    // shutdown     syncState(false)
    // shutdown {
    // shutdown     require(_liquidityPool.isRunning, "pool is not running");
    // shutdown     if (IPoolCreatorFull(_liquidityPool.creator).isUniverseSettled()) {
    // shutdown         require(
    // shutdown             _liquidityPool.isAllPerpetualIn(PerpetualState.CLEARED),
    // shutdown             "all perpetual must be cleared"
    // shutdown         );
    // shutdown     }
    // shutdown     _liquidityPool.removeLiquidity(_msgSender(), shareToRemove, cashToReturn);
    // shutdown }

    /**
     * @notice  Remove liquidity from the liquidity pool.
     *          Liquidity providers redeems share token then gets collateral back.
     *          The amount of collateral retrieved may differ from the amount when adding liquidity,
     *          The index price, trading fee and positions holding by amm will affect the profitability of providers.
     *          Can only called when the pool is running.
     */
    function removeLiquidityFor(address lp)
        external
        nonReentrant
        syncState(false)
    {
        require(_liquidityPool.isRunning, "pool is not running");
        require(
            _liquidityPool.isAllPerpetualIn(PerpetualState.CLEARED),
            "all perpetual must be cleared"
        );
        IGovernor shareToken = IGovernor(_liquidityPool.shareToken);
        int256 shareToRemove = shareToken.balanceOf(lp).toInt256();
        _liquidityPool.removeLiquidity(lp, shareToRemove, 0 /* cashToReturn */);
    }

    /**
     * @notice  Donate collateral to the insurance fund of the pool.
     *          Can only called when the pool is running.
     *          Donated collateral is not withdrawable but can be used to improve security.
     *          Unexpected loss (bankrupt) will be deducted from insurance fund then donated insurance fund.
     *          Until donated insurance fund is drained, the perpetual will not enter emergency state and shutdown.
     *
     * @param   amount          The amount of collateral to donate. The amount always use decimals 18.
     */
    function donateInsuranceFund(int256 amount) external nonReentrant {
        require(_liquidityPool.isRunning, "pool is not running");
        _liquidityPool.donateInsuranceFund(_msgSender(), amount);
    }

    /**
     * @notice  Add liquidity to the liquidity pool without getting shares.
     *
     * @param   cashToAdd   The amount of cash to add. The amount always use decimals 18.
     */
    function donateLiquidity(int256 cashToAdd) external nonReentrant {
        require(_liquidityPool.isRunning, "pool is not running");
        _liquidityPool.donateLiquidity(_msgSender(), cashToAdd);
    }

    bytes32[50] private __gap;
}

