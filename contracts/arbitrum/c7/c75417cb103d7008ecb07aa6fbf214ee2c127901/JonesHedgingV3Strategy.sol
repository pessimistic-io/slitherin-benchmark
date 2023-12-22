// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

// Openzeppelin
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

// Adapters
import {GmxAdapter} from "./GmxAdapter.sol";
import {SushiAdapter} from "./SushiAdapter.sol";

// Interfaces
import {IGMXRouter} from "./IGMXRouter.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IStakingRewardsV3} from "./IStakingRewardsV3.sol";

// Shared
import {JonesSwappableV3Strategy} from "./JonesSwappableV3Strategy.sol";
import {JonesStrategyV3Base} from "./JonesStrategyV3Base.sol";

import {IwETH} from "./IwETH.sol";

/// To save our a$$es
contract JonesHedgingV3Strategy is JonesSwappableV3Strategy {
    using SushiAdapter for IUniswapV2Router02;
    using SafeERC20 for IERC20;

    /// Farm information used to stake and unstake on Dopex
    struct DopexFarmInfo {
        IStakingRewardsV3 farm;
        IERC20 underlyingToken;
        IERC20 stakingToken; // same as `underlyingToken` for single staking
    }

    /**
     * List of farm info for staking and LPing:
     *
     * 0. WETH/DPX
     * farm           : address of WETH/DPX dopex farm
     * underlyingToken: address of DPX token
     * stakingToken   : address of the WETH/DPX sushi lp token
     *
     * 1. WETH/RDPX
     * farm           : address of WETH/RDPX dopex farm
     * underlyingToken: address of RDPX token
     * stakingToken   : address of WETH/RDPX sushi lp token
     *
     */
    DopexFarmInfo[2] public farmInfo;

    /// GMX Router contract
    IGMXRouter public constant GMXRouter = IGMXRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);

    /// GMX Position Manager used to execute GMX strategies.
    address public constant GMXPositionManager = 0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C;

    address public constant GMXOrderBook = 0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB;

    constructor(bytes32 _name, address _asset, address _governor, address[] memory _tokensToWhitelist)
        JonesStrategyV3Base(_name, _asset, _governor)
    {
        GMXRouter.approvePlugin(GMXPositionManager);
        GMXRouter.approvePlugin(GMXOrderBook);
        _setFarmInfo();
        _whitelistTokens(_tokensToWhitelist);
    }

    /* ========== Dopex Farm ========== */

    /**
     * Stakes a specific `_amount` of tokens into the Dopex farm.
     * @param _farmIndex the index value of the Dopex farm info. Enter the index value of `farmInfo` array.
     */
    function stake(uint8 _farmIndex, uint256 _amount) public virtual onlyRole(KEEPER) {
        _validateStakeParamIndex(_farmIndex);
        DopexFarmInfo memory targetFarm = farmInfo[_farmIndex];

        targetFarm.stakingToken.approve(address(targetFarm.farm), _amount);
        targetFarm.farm.stake(_amount);

        emit Stake(msg.sender, address(targetFarm.farm), address(targetFarm.stakingToken), _amount);
    }

    /**
     * Claims Dopex farming rewards
     * @param _farmIndex the index value of the Dopex farm info. Enter the index value of `farmInfo` array.
     */
    function claimDopexFarmingRewardTokens(uint8 _farmIndex) public onlyRole(KEEPER) {
        _validateStakeParamIndex(_farmIndex);
        farmInfo[_farmIndex].farm.claim();
    }

    /**
     * Unstakes a specific `_amount` of tokens from the Dopex farm.
     * @param _farmIndex the index value of the Dopex farm info. Enter the index value of `farmInfo` array.
     * @param _amount The amount to unstake
     * @param _claimRewards It will try to claim rewards if `true`
     */
    function unstake(uint8 _farmIndex, uint256 _amount, bool _claimRewards) public virtual onlyRole(KEEPER) {
        _validateStakeParamIndex(_farmIndex);

        farmInfo[_farmIndex].farm.unstake(_amount);

        emit Unstake(
            msg.sender,
            address(farmInfo[_farmIndex].farm),
            address(farmInfo[_farmIndex].stakingToken),
            _amount,
            _claimRewards
            );
    }

    /* ========== GMX Interaction ========== */

    /**
     * Opens or increases position on GMX.
     *
     * @param _tokenIn The address of token to deposit that will be swapped for `_collateralToken`. Enter the same address as `_collateralToken` if token swap isn't necessary.
     * @param _collateralToken the address of the collateral token. For longs, it must be the same as the `_indexToken`
     * @param _indexToken the address of the index token to long or shot
     * @param _amountIn the amount of `_tokenIn` to deposit as collateral
     * @param _minOut the min amount of `_collateralToken` output from swapping `_tokenIn` to `_collateralToken`. Enter 0 if swapping is not necessary
     * @param _sizeDelta: the USD value of the change in position size. Needs to be scaled to 30 decimals.
     * @param _price the USD value of the max (for longs) or min (for shorts) index price accepted when opening the position. Must be multiplied by (10 ** 30).
     * @param _isLong Indicates if position is long. Enter false if short.
     *
     * Note: GMXVault has convenient functions getMinPrice/getMaxPrice that are properly formatted.
     *
     * Returns a boolean to indicate if position was successfully increased.
     */
    function increasePosition(
        address _tokenIn,
        address _collateralToken,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        uint256 _price,
        bool _isLong
    )
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        return GmxAdapter.increasePosition(
            _tokenIn, _collateralToken, _indexToken, _amountIn, _minOut, _sizeDelta, _price, _isLong
        );
    }

    /**
     * Closes or decreases position on GMX.
     *
     * If `_sizeDelta` is the same size as the position, the collateral after adding profits or
     * deducting losses will be sent to the receiver address
     *
     * @param _collateralToken the collateral token used
     * @param _indexToken the index token of the position
     * @param _collateralDelta the amount of collateral in USD value to withdraw. Needs to be scaled to 30 decimals.
     * @param _sizeDelta: the USD value of the change in position size. Needs to be scaled to 30 decimals.
     * @param _price the USD value of the min (for shorts) or max (for longs) index price accepted when decreasing the position. Must be scaled to 30 decimals.
     * @param _isLong Indicate if position is long
     *
     * Note: GMXVault has convenient functions getMinPrice/getMaxPrice that are properly formatted.
     *
     * Returns a boolean to indicate if decreasing long position was successful.
     */
    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _price,
        bool _isLong
    )
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        return GmxAdapter.decreasePosition(
            _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _price, _isLong, address(this)
        );
    }

    /**
     * Creates increase order on GMX.
     *
     * @param _tokenIn ERC20 address to swap **to** `_purchaseToken`. Enter same address as `_purchaseToken` if swap is not necessary.
     * @param _purchaseToken ERC20 address to swap **from** `_tokenIn`. Must be same as `_indexToken` for longs.
     * @param _amountIn The amount of `_tokenIn` to deposit.
     * @param _indexToken The index token to create order.
     * @param _minOut The min amount of `_purchaseToken` to output when swapping `_tokenIn` for `_purchaseToken`.
     * @param _sizeDelta The USD value (in 30 decimals) of the order size.
     * @param _collateralToken The ERC20 token used as collateral to create order. Must be a stablecoin for shorts.
     * @param _isLong Indicate if creating long order.
     * @param _triggerPrice The USD value (in 30 decimals) of triggering price for the `_indexToken`.
     * @param _triggerAboveThreshold Indicate if order should be triggered above threshold.
     *
     * note Make sure to send ETH for execution fee. You can use `GMXOrderBook.minExecutionFee` to calculate the amount required.
     */
    function createGMXIncreaseOrder(
        address _tokenIn,
        address _purchaseToken,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    )
        public
        payable
        onlyRole(KEEPER)
    {
        GmxAdapter.createIncreaseOrder(
            _tokenIn,
            _purchaseToken,
            _amountIn,
            _indexToken,
            _minOut,
            _sizeDelta,
            _collateralToken,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    /**
     * Creates decrease order on GMX.
     *
     * @param _indexToken The index token to create order.
     * @param _sizeDelta The USD value (in 30 decimals) of the order size.
     * @param _collateralToken The ERC20 token used as collateral to create order. Must be a stablecoin for shorts.
     * @param _collateralDelta The position collateral delta.
     * @param _isLong Indicate if creating long order.
     * @param _triggerPrice The USD value (in 30 decimals) of triggering price for the `_indexToken`.
     * @param _triggerAboveThreshold Indicate if order should be triggered above threshold.
     *
     * note Make sure to send ETH for execution fee. You can use `GMXOrderBook.minExecutionFee` to calculate the amount required.
     */
    function createGMXDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    )
        public
        payable
        onlyRole(KEEPER)
    {
        GmxAdapter.createDecreaseOrder(
            _indexToken, _sizeDelta, _collateralToken, _collateralDelta, _isLong, _triggerPrice, _triggerAboveThreshold
        );
    }

    /**
     * Cancels a created order on GMX.
     *
     * @param _isIncreaseOrder Indicate if cancelling increase order. True if cancelling increase order, false if cancelling decrease order.
     * @param _orderIndex The order index of the order to cancel.
     */
    function cancelGMXOrder(bool _isIncreaseOrder, uint256 _orderIndex) public onlyRole(KEEPER) {
        GmxAdapter.cancelOrder(_isIncreaseOrder, _orderIndex);
    }

    /* ========== Swaping ========== */

    /**
     * Swaps source token to destination token on GMX
     * @param _source source asset
     * @param _destination destination asset
     * @param _amountIn the amount of source asset to swap
     * @param _amountOutMin minimum amount of destination asset that must be received for the transaction not to revert
     *
     * Note: GMX Reader has convenient functions getMaxAmountIn/getAmountOut that could be used pre-compute values `_amountIn` and `_amountOutMin`.
     *
     */
    function swapTokensOnGmx(address _source, address _destination, uint256 _amountIn, uint256 _amountOutMin)
        public
        onlyRole(KEEPER)
    {
        _validateSwapParams(_source, _destination);
        GmxAdapter.swapTokens(_source, _destination, _amountIn, _amountOutMin);
    }

    /* ========== Liquidity ========== */
    /**
     * Add liquidity to acquire Dopex LP token
     *
     * @param _farmIndex the index value of the Dopex farm info. Enter the index value of `farmInfo` array.
     * @param _amountEthDesired	The amount of wETH to add as liquidity if the token/wETH price is <= _tokenAmountDesired/_amountEthDesired (wETH depreciates).
     * @param _tokenAmountDesired The amount of tokens (ex DPX or rDPX) to add as liquidity if the LP price is <= _amountEthDesired/_tokenAmountDesired (token depreciates).
     * @param _amountEthMin Bounds the extent to which the token/wETH price can go up before the transaction reverts. Must be <= _amountEthDesired.
     * @param _tokenMin Bounds the extent to which the wETH/token price can go up before the transaction reverts. Must be <= _tokenAmountDesired.
     *
     * @return _amountWETH The amount of wETH sent to the pool.
     * @return _amountTokens The amount of tokens sent to the pool.
     * @return _liquidity The amount of liquidity tokens minted.
     */
    function addETHLiquidityPair(
        uint8 _farmIndex,
        uint256 _amountEthDesired,
        uint256 _tokenAmountDesired,
        uint256 _amountEthMin,
        uint256 _tokenMin
    )
        public
        onlyRole(KEEPER)
        returns (uint256 _amountWETH, uint256 _amountTokens, uint256 _liquidity)
    {
        _validateLPParamIndex(_farmIndex);

        IERC20(wETH).safeApprove(address(sushiRouter), _amountEthDesired);

        farmInfo[_farmIndex].underlyingToken.safeApprove(address(sushiRouter), _tokenAmountDesired);

        (_amountWETH, _amountTokens, _liquidity) = sushiRouter.addLiquidity(
            wETH,
            address(farmInfo[_farmIndex].underlyingToken),
            _amountEthDesired,
            _tokenAmountDesired,
            _amountEthMin,
            _tokenMin,
            address(this),
            block.timestamp
        );

        IERC20(wETH).safeApprove(address(sushiRouter), 0);

        farmInfo[_farmIndex].underlyingToken.safeApprove(address(sushiRouter), 0);
    }

    /**
     * Remove liquidity from Dopex LP
     *
     * @param _farmIndex the index value of the Dopex farm info. Enter the index value of `farmInfo` array.
     * @param _amountLiquidity	The amount of liquidity tokens to remove.
     * @param _amountEthMin The minimum amount of ETH that must be received for the transaction not to revert.
     * @param _tokensMin The minimum amount of tokens (ex DPX or RDPX) that must be received for the transaction not to revert.
     *
     * @return _amountWETH The amount of wETH received.
     * @return _amountTokens The amount of tokens (ex DPX or rDPX) received.
     */
    function removeETHLiquidityPair(
        uint8 _farmIndex,
        uint256 _amountLiquidity,
        uint256 _amountEthMin,
        uint256 _tokensMin
    )
        public
        onlyRole(KEEPER)
        returns (uint256 _amountWETH, uint256 _amountTokens)
    {
        _validateLPParamIndex(_farmIndex);

        farmInfo[_farmIndex].stakingToken.safeApprove(address(sushiRouter), _amountLiquidity);

        (_amountWETH, _amountTokens) = sushiRouter.removeLiquidity(
            wETH,
            address(farmInfo[_farmIndex].underlyingToken),
            _amountLiquidity,
            _amountEthMin,
            _tokensMin,
            address(this),
            block.timestamp
        );

        farmInfo[_farmIndex].stakingToken.safeApprove(address(sushiRouter), 0);
    }

    /* ========== Internal/Private ========== */

    function _setFarmInfo() private {
        // WETH/DPX Farm
        farmInfo[0] = DopexFarmInfo(
            IStakingRewardsV3(0x1f80C96ca521d7247a818A09b0b15C38E3e58a28), // weth/dpx dopex farm
            IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55), // dpx
            IERC20(0x0C1Cf6883efA1B496B01f654E247B9b419873054) // weth/dpx sushi lp token
        );

        // WETH/RDPX Farm
        farmInfo[1] = DopexFarmInfo(
            IStakingRewardsV3(0xEb0F03A203F25F08c7aFF0e1b1C2E0EE25Ca29Eb), // weth/rdpx dopex farm
            IERC20(0x32Eb7902D4134bf98A28b963D26de779AF92A212), // rdpx
            IERC20(0x7418F5A2621E13c05d1EFBd71ec922070794b90a) // weth/rdpx sushi lp token
        );
    }

    function _validateStakeParamIndex(uint256 _index) internal view {
        if (_index >= farmInfo.length) {
            revert INVALID_INDEX();
        }
    }

    function _validateLPParamIndex(uint256 _index) internal view {
        if (_index >= farmInfo.length - 1) {
            revert INVALID_INDEX();
        }
    }

    /// @inheritdoc JonesSwappableV3Strategy
    function _afterRemoveWhitelistedToken(address _token) internal override {
        IERC20(_token).safeApprove(address(GMXRouter), 0);
    }

    /* ========== SYSTEM ========== */

    /**
     * Used for GMX interactions - DO NOT USE THIS TO FUND STRATEGY!
     */
    receive() external payable {
        IwETH(wETH).deposit{value: msg.value}();
    }

    /* ========== EVENTS ========== */

    /**
     * Emitted when staking token into Dopex Farm
     *
     * @param _keeper the address of the sender that performed this action
     * @param _farm the address of the Dopex farm
     * @param _token the address of the token that was staked
     * @param _amount the amount of tokens staked into farm
     */
    event Stake(address indexed _keeper, address indexed _farm, address indexed _token, uint256 _amount);

    /**
     * Emitted when staking into Dopex Farm
     *
     * @param _keeper the address of the sender that performed this action
     * @param _farm the address of the Dopex farm
     * @param _token the address of the token that was unstaked
     * @param _amount the amount of tokens unstaked from farm
     * @param _claimRewards if rewards were claimed
     */
    event Unstake(
        address indexed _keeper, address indexed _farm, address indexed _token, uint256 _amount, bool _claimRewards
    );

    /* ========== ERRORS ========== */
    error INVALID_INDEX();
}

