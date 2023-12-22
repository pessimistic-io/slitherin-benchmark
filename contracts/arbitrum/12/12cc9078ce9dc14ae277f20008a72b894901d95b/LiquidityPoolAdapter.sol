// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./IController.sol";
import "./ILiquidityPool.sol";
import "./ILiquidityPoolAdapter.sol";
import "./Constants.sol";
import "./UnlimitedOwnable.sol";

contract LiquidityPoolAdapter is ILiquidityPoolAdapter, UnlimitedOwnable, Initializable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice Controller contract.
    IController public immutable controller;

    /// @notice Fee manager address.
    address public immutable feeManager;

    /// @notice The token that is used as a collateral
    IERC20 public immutable collateral;

    /// @notice Maximum payout proportion of the available liquidity
    /// @dev Denominated in BPS
    uint256 public maxPayoutProportion;

    /// @notice List of liquidity pools configurations used by the adapter
    LiquidityPoolConfig[] public liquidityPools;

    // Storage gap
    uint256[50] __gap;

    /**
     * @notice Constructs the `LiquidityPoolAdapter` contract.
     * @param unlimitedOwner_ The address of the unlimited owner.
     * @param controller_ The address of the controller.
     * @param feeManager_ The address of the fee manager.
     * @param collateral_ The address of the collateral token.
     */
    constructor(IUnlimitedOwner unlimitedOwner_, IController controller_, address feeManager_, IERC20 collateral_)
        UnlimitedOwnable(unlimitedOwner_)
    {
        controller = controller_;
        feeManager = feeManager_;
        collateral = collateral_;
    }

    /**
     * @notice Initializes the `LiquidityPoolAdapter` contract.
     * @param maxPayoutProportion_ The maximum payout proportion of the available liquidity.
     * @param liquidityPools_ The list of liquidity pools configurations used by the adapter.
     */
    function initialize(uint256 maxPayoutProportion_, LiquidityPoolConfig[] memory liquidityPools_)
        external
        onlyOwner
        initializer
    {
        _updateMaxPayoutProportion(maxPayoutProportion_);
        _updateLiquidityPools(liquidityPools_);
    }

    /* ========== ADMIN CONTROLLS ========== */

    /**
     * @notice Update list of liquidity pools
     * @param liquidityPools_ address and percentage of the liquidity pools
     */
    function updateLiquidityPools(LiquidityPoolConfig[] calldata liquidityPools_) external onlyOwner {
        _updateLiquidityPools(liquidityPools_);
    }

    /**
     * @notice Update list of liquidity pools
     * @param liquidityPools_ address and percentage of the liquidity pools
     */
    function _updateLiquidityPools(LiquidityPoolConfig[] memory liquidityPools_) private {
        require(
            liquidityPools_.length > 0, "LiquidityPoolAdapter::_updateLiquidityPools: Cannot set zero liquidity pools"
        );

        delete liquidityPools;

        for (uint256 i; i < liquidityPools_.length; ++i) {
            require(
                controller.isLiquidityPool(liquidityPools_[i].poolAddress),
                "LiquidityPoolAdapter::_updateLiquidityPools: Invalid pool"
            );

            require(
                liquidityPools_[i].percentage > 0 && liquidityPools_[i].percentage <= FULL_PERCENT,
                "LiquidityPoolAdapter::_updateLiquidityPools: Bad pool percentage"
            );
            liquidityPools.push(liquidityPools_[i]);
        }

        emit UpdatedLiquidityPools(liquidityPools_);
    }

    /**
     * @notice Update maximum proportion of available liquidity to payout at once
     * @param maxPayoutProportion_ Maximum proportion payout value
     */
    function updateMaxPayoutProportion(uint256 maxPayoutProportion_) external onlyOwner {
        _updateMaxPayoutProportion(maxPayoutProportion_);
    }

    /**
     * @notice Update maximum proportion of available liquidity to payout at once
     * @param maxPayoutProportion_ Maximum proportion payout value
     */
    function _updateMaxPayoutProportion(uint256 maxPayoutProportion_) private {
        require(
            maxPayoutProportion_ > 0 && maxPayoutProportion_ <= FULL_PERCENT,
            "LiquidityPoolAdapter::_updateMaxPayoutProportion: Bad max payout proportion"
        );

        maxPayoutProportion = maxPayoutProportion_;

        emit UpdatedMaxPayoutProportion(maxPayoutProportion_);
    }

    /**
     * @notice returns the total amount of available liquidity
     * @return availableLiquidity uint the available liquidity
     * @dev Sums up the liquidity of all liquidity pools allocated to this liquidity pool adapter
     */
    function availableLiquidity() public view returns (uint256) {
        uint256 _totalAvailableLiquidity;
        for (uint256 i; i < liquidityPools.length; ++i) {
            uint256 poolLiquidity = ILiquidityPool(liquidityPools[i].poolAddress).availableLiquidity();
            _totalAvailableLiquidity += poolLiquidity * liquidityPools[i].percentage / FULL_PERCENT;
        }

        return _totalAvailableLiquidity;
    }

    /**
     * @notice Returns maximum amount of available liquidity to payout at once
     * @return maxPayout uint256 the maximum amount of available liquidity to payout at once
     */
    function getMaximumPayout() external view returns (uint256) {
        return availableLiquidity() * maxPayoutProportion / FULL_PERCENT;
    }

    /**
     * @notice requests payout of a protocol loss when a trader made a profit
     * @dev pays out the user profit when msg.sender is a registered tradepair
     * and loss does not exceed the remaining liquidity.
     * Distributes loss to liquidity pools in respect to their allocated liquidity
     * @param requestedPayout_ the requested payout amount
     * @return actualPayout Actual payout transferred to the trade pair
     */
    function requestLossPayout(uint256 requestedPayout_) external onlyValidTradePair returns (uint256 actualPayout) {
        // get pool liquitities
        LiquidityPoolConfig[] memory _liquidityPools = liquidityPools;
        uint256[] memory poolLiquidities = new uint256[](_liquidityPools.length);

        uint256 _totalAvailableLiquidity;
        for (uint256 i; i < poolLiquidities.length; ++i) {
            uint256 poolLiquidity = ILiquidityPool(_liquidityPools[i].poolAddress).availableLiquidity();
            poolLiquidities[i] = poolLiquidity * _liquidityPools[i].percentage / FULL_PERCENT;
            _totalAvailableLiquidity += poolLiquidities[i];
        }

        // calculate maximum payout amount
        uint256 maxPayout = _totalAvailableLiquidity * maxPayoutProportion / FULL_PERCENT;

        if (requestedPayout_ > maxPayout) {
            requestedPayout_ = maxPayout;
        }

        if (requestedPayout_ > 0) {
            // request payouts from pools
            for (uint256 i; i < poolLiquidities.length; ++i) {
                uint256 poolPayout = requestedPayout_ * poolLiquidities[i] / _totalAvailableLiquidity;
                actualPayout += poolPayout;

                ILiquidityPool(_liquidityPools[i].poolAddress).requestLossPayout(poolPayout);
            }

            // transfer the payout to the trade pair
            collateral.safeTransfer(msg.sender, actualPayout);
        }

        emit PayedOutLoss(msg.sender, actualPayout);
    }

    /**
     * @notice deposits fees
     * @param feeAmount_ amount fees
     * @dev deposits fee when sender is FeeManager
     * The amount has to be sent to this LPA before calling this function.
     */
    function depositFees(uint256 feeAmount_) external onlyFeeManager {
        _depositToLiquidityPools(feeAmount_, true);
    }

    /**
     * @notice deposits a protocol profit when a trader made a loss
     * @param profitAmount_ the profit of the asset with respect to the asset multiplier
     * @dev deposits profit when msg.sender is a registered tradepair
     * The amount has to be sent to this LPA before calling this function.
     */
    function depositProfit(uint256 profitAmount_) external onlyValidTradePair {
        _depositToLiquidityPools(profitAmount_, false);
    }

    /**
     * @notice deposits assets to liquidity pools when a trader made a loss or fees are collected
     * @param amount_ the amount of the asset with respect to the asset multiplier
     * @param isFees_ flag if the `amount` is fees
     * @dev Distributes profit to liquidity pools in respect to their allocated liquidity
     * The amount has to be sent to this LPA before calling this function.
     */
    function _depositToLiquidityPools(uint256 amount_, bool isFees_) private {
        // get pool liquitities
        LiquidityPoolConfig[] memory _liquidityPools = liquidityPools;
        uint256[] memory poolLiquidities = new uint256[](_liquidityPools.length);

        uint256 _totalAvailableLiquidity;
        for (uint256 i; i < poolLiquidities.length; ++i) {
            uint256 poolLiquidity = ILiquidityPool(_liquidityPools[i].poolAddress).availableLiquidity();
            poolLiquidities[i] = poolLiquidity * _liquidityPools[i].percentage / FULL_PERCENT;
            _totalAvailableLiquidity += poolLiquidities[i];
        }

        // if total available liquidity is 0, so no pools have any liquidity, distribute equally
        if (_totalAvailableLiquidity == 0) {
            for (uint256 i; i < poolLiquidities.length; ++i) {
                poolLiquidities[i] = 1;
                _totalAvailableLiquidity++;
            }
        }

        // deposit profits to pools
        uint256 depositedProfit;
        for (uint256 i; i < poolLiquidities.length - 1; ++i) {
            uint256 poolAmount = amount_ * poolLiquidities[i] / _totalAvailableLiquidity;
            depositedProfit += poolAmount;

            // transfer from trade pair to liquidity pool directly
            _depositToLiquidityPool(_liquidityPools[i].poolAddress, poolAmount, isFees_);
        }

        // deposit in the last liquidity pool what's left in case of any rounding loss
        uint256 depositedProfitLeft = amount_ - depositedProfit;
        _depositToLiquidityPool(_liquidityPools[poolLiquidities.length - 1].poolAddress, depositedProfitLeft, isFees_);

        emit DepositedProfit(msg.sender, amount_);
    }

    function _depositToLiquidityPool(address liquidityPool_, uint256 amount_, bool isFees_) private {
        // if depositing fees approve spending
        if (collateral.allowance(address(this), liquidityPool_) > 0) {
            collateral.safeApprove(liquidityPool_, 0);
        }

        collateral.safeApprove(liquidityPool_, amount_);

        if (isFees_) {
            ILiquidityPool(liquidityPool_).depositFees(amount_);
        } else {
            ILiquidityPool(liquidityPool_).depositProfit(amount_);
        }
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    function _onlyValidTradePair() private view {
        require(
            controller.isTradePair(msg.sender), "LiquidityPoolAdapter::_onlyValidTradePair: Caller is not a trade pair"
        );
    }

    function _onlyFeeManager() private view {
        require(msg.sender == feeManager, "LiquidityPoolAdapter::_onlyFeeManager: Caller is not a fee manager");
    }

    /* ========== MODIFIERS ========== */

    modifier onlyValidTradePair() {
        _onlyValidTradePair();
        _;
    }

    modifier onlyFeeManager() {
        _onlyFeeManager();
        _;
    }
}

