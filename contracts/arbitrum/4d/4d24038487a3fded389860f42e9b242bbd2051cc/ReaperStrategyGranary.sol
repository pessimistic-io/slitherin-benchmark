// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperBaseStrategyv4} from "./ReaperBaseStrategyv4.sol";
import {IVault} from "./IVault.sol";
import {IAToken} from "./IAToken.sol";
import {IAaveProtocolDataProvider} from "./IAaveProtocolDataProvider.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {ILeverageable} from "./ILeverageable.sol";
import {IRewardsController} from "./IRewardsController.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {MathUpgradeable} from "./MathUpgradeable.sol";
import {ReaperMathUtils} from "./ReaperMathUtils.sol";

/**
 * @dev This strategy will deposit and leverage a token on Granary to maximize yield
 */
contract ReaperStrategyGranary is ReaperBaseStrategyv4, ILeverageable {
    using ReaperMathUtils for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    ILendingPoolAddressesProvider public addressProvider;
    IAaveProtocolDataProvider public dataProvider;
    IRewardsController public rewarder;

    // this strategy's configurable tokens
    IAToken public gWant;

    uint256 public targetLtv; // in hundredths of percent, 8000 = 80%
    uint256 public maxLtv; // in hundredths of percent, 8000 = 80%
    uint256 public minLeverageAmount;
    uint256 public maxDeleverageLoopIterations;
    uint256 public constant LTV_SAFETY_ZONE = 0.98 ether;
    uint256 public constant LTV_UNIT = 1 ether;
    uint256 public constant LTV_SCALING_FACTOR = 0.0001 ether; // Used to convert the Granary LTV (in BPS) to units of 1e18

    // Misc constants
    uint16 private constant LENDER_REFERRAL_CODE_NONE = 0;
    uint256 private constant INTEREST_RATE_MODE_VARIABLE = 2;
    uint256 private constant LEVER_SAFETY_ZONE = 0.999 ether; // Used to stay under the max limit when changing leverage

    /**
     * @dev Tokens Used:
     * {rewardClaimingTokens} - Array containing gWant + corresponding variable debt token,
     *                          used for claiming rewards
     */
    address[] public rewardClaimingTokens;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address _swapper,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        IAToken _gWant,
        uint256 _targetLtv,
        uint256 _maxLtv,
        address _addressProvider,
        address _dataProvider,
        address _rewarder
    ) public initializer {
        gWant = _gWant;
        want = _gWant.UNDERLYING_ASSET_ADDRESS();
        __ReaperBaseStrategy_init(_vault, _swapper, want, _strategists, _multisigRoles, _keepers);
        maxDeleverageLoopIterations = 10;
        minLeverageAmount = 1000;

        addressProvider = ILendingPoolAddressesProvider(_addressProvider);
        dataProvider = IAaveProtocolDataProvider(_dataProvider);
        rewarder = IRewardsController(_rewarder);

        (,, address vToken) = IAaveProtocolDataProvider(dataProvider).getReserveTokensAddresses(address(want));
        rewardClaimingTokens = [address(_gWant), vToken];

        _safeUpdateTargetLtv(_targetLtv, _maxLtv);
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _delever(type(uint256).max);
        _withdrawUnderlying(balanceOfPool());
        return balanceOfWant();
    }

    /**
     * @dev Core function of the strat, in charge of collecting rewards
     */
    function _beforeHarvestSwapSteps() internal override {
        rewarder.claimAllRewardsToSelf(rewardClaimingTokens);
    }

    function lendingPool() public view returns (ILendingPool) {
        return ILendingPool(addressProvider.getLendingPool());
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * !audit we increase the allowance in the balance amount but we deposit the amount specified
     */
    function _deposit(uint256 toReinvest) internal override {
        if (toReinvest != 0) {
            address lendingPoolAddress = addressProvider.getLendingPool();
            IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, toReinvest);
            lendingPool().deposit(want, toReinvest, address(this), LENDER_REFERRAL_CODE_NONE);
        }

        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 currentLtv = supply != 0 ? (borrow * LTV_UNIT) / supply : 0;

        if (currentLtv > maxLtv) {
            _delever(0);
        } else if (currentLtv < targetLtv) {
            _leverUpMax();
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        if (_amount == 0) {
            return;
        }

        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        supply -= _amount;
        uint256 postWithdrawLtv = supply != 0 ? (borrow * LTV_UNIT) / supply : 0;

        if (postWithdrawLtv > maxLtv) {
            _delever(_amount);
            _withdrawUnderlying(_amount);
        } else if (postWithdrawLtv < targetLtv) {
            _withdrawUnderlying(_amount);
            _leverUpMax();
        } else {
            _withdrawUnderlying(_amount);
        }
    }

    /**
     * @dev Delevers by manipulating supply/borrow such that {_withdrawAmount} can
     *      be safely withdrawn from the pool afterwards.
     */
    function _delever(uint256 _withdrawAmount) internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        uint256 newRealSupply = realSupply > _withdrawAmount ? realSupply - _withdrawAmount : 0;
        uint256 newBorrow = (newRealSupply * targetLtv) / (LTV_UNIT - targetLtv);

        require(borrow >= newBorrow);
        uint256 borrowReduction = borrow - newBorrow;
        for (uint256 i = 0; i < maxDeleverageLoopIterations && borrowReduction > 0; i = i.uncheckedInc()) {
            uint256 currentBorrowReduction = _leverDownStep(borrowReduction);
            if (currentBorrowReduction == 0 || currentBorrowReduction > borrowReduction) {
                break;
            }
            borrowReduction -= currentBorrowReduction;
        }
    }

    /**
     * @dev Deleverages one step in an attempt to reduce borrow by {_totalBorrowReduction}.
     *      Returns the amount by which borrow was actually reduced.
     */
    function _leverDownStep(uint256 _totalBorrowReduction) internal returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();

        if (borrow == 0) {
            return 0;
        }

        (,, uint256 threshLtv,,,,,,,) = dataProvider.getReserveConfigurationData(address(want));
        uint256 scaledThreshLtv = _getScaledLTV(threshLtv);
        uint256 threshSupply = (borrow * LTV_UNIT) / scaledThreshLtv;

        // don't use 100% of excess supply, leave a smidge
        uint256 allowance = ((supply - threshSupply) * LEVER_SAFETY_ZONE) / LTV_UNIT;
        allowance = MathUpgradeable.min(allowance, borrow);
        if (borrow > _totalBorrowReduction && (borrow - _totalBorrowReduction >= 5)) {
            allowance = MathUpgradeable.min(allowance, _totalBorrowReduction);
        }

        ILendingPool pool = lendingPool();
        pool.withdraw(address(want), allowance, address(this));
        address lendingPoolAddress = addressProvider.getLendingPool();
        IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, allowance);
        pool.repay(address(want), allowance, INTEREST_RATE_MODE_VARIABLE, address(this));

        return allowance;
    }

    /**
     * @dev Attempts to reach max leverage as per {targetLtv} using a flash loan.
     */
    function _leverUpMax() internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        uint256 desiredBorrow = (realSupply * targetLtv) / (LTV_UNIT - targetLtv);

        if (desiredBorrow > borrow + minLeverageAmount) {
            uint256 borrowIncrease = desiredBorrow - borrow;

            for (
                uint256 i = 0;
                i < maxDeleverageLoopIterations && borrowIncrease > minLeverageAmount;
                i = i.uncheckedInc()
            ) {
                borrowIncrease -= _leverUpStep(borrowIncrease);
            }
        }
    }

    /**
     * @dev Leverages up one step in an attempt to increase borrow by {_totalBorrowIncrease}.
     *      Returns the actual amount by which borrow was increased.
     */
    function _leverUpStep(uint256 _totalBorrowIncrease) internal returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        (, uint256 threshLtv,,,,,,,,) = dataProvider.getReserveConfigurationData(address(want));
        uint256 scaledThreshLtv = _getScaledLTV(threshLtv);
        uint256 threshBorrow = (supply * scaledThreshLtv) / LTV_UNIT;

        // don't use 100% of borrow allowance, leave a smidge
        uint256 allowance = ((threshBorrow - borrow) * LEVER_SAFETY_ZONE) / LTV_UNIT;
        allowance = MathUpgradeable.min(allowance, IERC20Upgradeable(want).balanceOf(address(gWant)));
        allowance = MathUpgradeable.min(allowance, _totalBorrowIncrease);

        if (allowance != 0) {
            ILendingPool pool = lendingPool();
            pool.borrow(address(want), allowance, INTEREST_RATE_MODE_VARIABLE, LENDER_REFERRAL_CODE_NONE, address(this));
            address lendingPoolAddress = addressProvider.getLendingPool();
            IERC20Upgradeable(want).safeIncreaseAllowance(lendingPoolAddress, allowance);
            pool.deposit(address(want), allowance, address(this), LENDER_REFERRAL_CODE_NONE);
        }

        return allowance;
    }

    /**
     * @dev Attempts to Withdraw {_withdrawAmount} from pool. Withdraws max amount that can be
     *      safely withdrawn if {_withdrawAmount} is too high.
     */
    function _withdrawUnderlying(uint256 _withdrawAmount) internal {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 necessarySupply = maxLtv != 0 ? (borrow * LTV_UNIT) / maxLtv : 0; // use maxLtv instead of targetLtv here
        require(supply > necessarySupply);

        uint256 withdrawable = supply - necessarySupply;
        _withdrawAmount = MathUpgradeable.min(_withdrawAmount, withdrawable);

        if (_withdrawAmount != 0) {
            if (necessarySupply == borrow && _withdrawAmount > 1) {
                // Rounding at small amounts like 2 wei can cause reverts
                _withdrawAmount = _withdrawAmount - 1;
            }
            lendingPool().withdraw(address(want), _withdrawAmount, address(this));
        }
    }

    /**
     * Returns the current supply and borrow balance for this strategy.
     * Supply is the amount we have deposited in the lending pool as collateral.
     * Borrow is the amount we have taken out on loan against our collateral.
     */
    function getSupplyAndBorrow() public view returns (uint256 supply, uint256 borrow) {
        (supply,, borrow,,,,,,) = dataProvider.getUserReserveData(address(want), address(this));
        return (supply, borrow);
    }

    /**
     * @dev Frees up {_amount} of want by manipulating supply/borrow.
     */
    function authorizedDelever(uint256 _amount) external {
        _atLeastRole(STRATEGIST);
        _delever(_amount);
    }

    /**
     * @dev Attempts to safely withdraw {_amount} from the pool and optionally sends it
     *      to the vault.
     */
    function authorizedWithdrawUnderlying(uint256 _amount) external {
        _atLeastRole(STRATEGIST);
        _withdrawUnderlying(_amount);
    }

    function balanceOfPool() public view override returns (uint256) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        uint256 realSupply = supply - borrow;
        return realSupply;
    }

    /**
     * @dev This function is designed to be called by a keeper to set the desired
     *      leverage params within the strategy. The units of the parameters may vary
     *      from strategy to strategy: some strategies may use basis points, others may
     *      use ether precision. Moreover, not all parameters will apply to all strategies.
     *      Strategies are free to ignore parameters they don't care about.
     * @param targetLeverage the leverage/ltv to target
     * @param maxLeverage the maximum tolerable leverage/ltv
     * @param triggerHarvest whether to call the harvest function at the end
     */
    function setLeverage(uint256 targetLeverage, uint256 maxLeverage, bool triggerHarvest) external override {
        _atLeastRole(KEEPER);
        _safeUpdateTargetLtv(targetLeverage, maxLeverage);
        if (triggerHarvest) {
            harvest();
        }
    }

    /**
     * @dev Returns the current state of the strategy in terms of leverage params.
     *      If all is working as intended, targetLeverage <= realLeverage <= maxLeverage.
     *      Ideally realLeverage is very close to targetLeverage. The units of the return
     *      values will vary from strategy to strategy: some strategies may use basis points,
     *      others may use ether precision.
     * @return realLeverage the current leverage calculated using real loan values
     * @return targetLeverage the current value of targetLeverage set within the strategy
     * @return maxLeverage the current value of maxLeverage set within the strategy
     */
    function getCurrentLeverageSnapshot()
        external
        view
        returns (uint256 realLeverage, uint256 targetLeverage, uint256 maxLeverage)
    {
        realLeverage = calculateLTV();
        targetLeverage = targetLtv;
        maxLeverage = maxLtv;
    }

    /**
     * @dev Updates target LTV (safely), maximum iterations for the
     *      deleveraging loop, can only be called by strategist or owner.
     */
    function setLeverageParams(
        uint256 _newTargetLtv,
        uint256 _newMaxLtv,
        uint256 _newMaxDeleverageLoopIterations,
        uint256 _newMinLeverageAmount
    ) external {
        _atLeastRole(STRATEGIST);
        _safeUpdateTargetLtv(_newTargetLtv, _newMaxLtv);
        maxDeleverageLoopIterations = _newMaxDeleverageLoopIterations;
        minLeverageAmount = _newMinLeverageAmount;
    }

    /**
     * @dev Updates {targetLtv} and {maxLtv} safely, ensuring
     *      - maxLtv is less than or equal to maximum allowed LTV for asset
     *      - targetLtv is less than or equal to maxLtv
     */
    function _safeUpdateTargetLtv(uint256 _newTargetLtv, uint256 _newMaxLtv) internal {
        if (_newTargetLtv != 0) {
            require(_newTargetLtv >= LTV_SCALING_FACTOR);
        }
        (, uint256 ltv,,,,,,,,) = dataProvider.getReserveConfigurationData(address(want));
        uint256 scaledLtv = _getScaledLTV(ltv);
        require(_newMaxLtv <= (scaledLtv * LTV_SAFETY_ZONE) / LTV_UNIT);
        require(_newTargetLtv <= _newMaxLtv);
        maxLtv = _newMaxLtv;
        targetLtv = _newTargetLtv;
    }

    function calculateLTV() public view returns (uint256 ltv) {
        (uint256 supply, uint256 borrow) = getSupplyAndBorrow();
        if (supply != 0) {
            ltv = (borrow * LTV_UNIT) / supply;
        } else {
            ltv = 0;
        }
    }

    function _getScaledLTV(uint256 _ltvToScale) internal view returns (uint256 scaledLTV) {
        return _ltvToScale * LTV_SCALING_FACTOR;
    }
}

