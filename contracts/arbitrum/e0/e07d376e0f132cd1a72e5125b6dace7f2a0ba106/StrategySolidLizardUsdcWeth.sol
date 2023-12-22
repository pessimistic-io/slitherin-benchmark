// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./SolidLizardStakeLibrary.sol";
import "./AaveV3BorrowLibrary.sol";
import "./UniswapV3SwapLibrary.sol";
import "./HedgeStrategy.sol";

import "./console.sol";

contract StrategySolidLizardUsdcWeth is HedgeStrategy, StakeModule, BorrowModule, SwapModule {

    struct SetupParams {
        //Common
        address baseToken;
        address sideToken;

        //Stake
        address router;
        address gauge;
        address pair;
        address staker;
        address slizToken;
        bool isStable;
        bool isStableReward0;
        uint256 allowedStakeSlippageBp;

        //Borrow
        address poolAddressesProvider;
        uint256 neededHealthFactor;
        uint256 liquidationThreshold;

        //Swap
        address uniswapV3Router;
        uint24 poolFee0;
        uint256 allowedSlippageBp;
    }

    bool public isExit;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __Strategy_init();
    }

    function setUnitParams(UnitParams calldata params) external onlyUnit {
        neededHealthFactor = params.neededHealthFactor * 10 ** 15;
        allowedStakeSlippageBp = params.allowedStakeSlippageBp;
        allowedSlippageBp = params.allowedSlippageBp;
    }

    function setParams(SetupParams calldata params) external onlyAdmin {
        //Common
        baseToken = IERC20(params.baseToken);
        sideToken = IERC20(params.sideToken);
        baseDecimals = 10 ** IERC20Metadata(params.baseToken).decimals();
        sideDecimals = 10 ** IERC20Metadata(params.sideToken).decimals();
        IAaveOracle priceOracleGetter = IAaveOracle(IPoolAddressesProvider(params.poolAddressesProvider).getPriceOracle());
        baseOracle = IPriceFeed(priceOracleGetter.getSourceOfAsset(params.baseToken));
        sideOracle = IPriceFeed(priceOracleGetter.getSourceOfAsset(params.sideToken));

        //Stake
        router = ILizardRouter01(params.router);
        gauge = ILizardGauge(params.gauge);
        pair = ILizardPair(params.pair);
        staker = IStaker(params.staker);
        slizToken = IERC20(params.slizToken);
        isStable = params.isStable;
        isStableReward0 = params.isStableReward0;
        allowedStakeSlippageBp = params.allowedStakeSlippageBp;

        //Borrow
        poolAddressesProvider = params.poolAddressesProvider;
        neededHealthFactor = params.neededHealthFactor * 10 ** 15;
        liquidationThreshold = params.liquidationThreshold * 10 ** 15;

        //Swap
        uniswapV3Router = params.uniswapV3Router;
        poolFee0 = params.poolFee0;
        allowedSlippageBp = params.allowedSlippageBp;

        //Other
        setAsset(params.baseToken);
    }

    function _executeAction(Action memory action) internal {
        if (action.actionType == ActionType.ADD_LIQUIDITY) {
            console.log("execute action ADD_LIQUIDITY");
            _addLiquidity(action.amount);
        } else if (action.actionType == ActionType.REMOVE_LIQUIDITY) {
            console.log("execute action REMOVE_LIQUIDITY");
            _removeLiquidity(action.amount);
        } else if (action.actionType == ActionType.SUPPLY_BASE_TOKEN) {
            console.log("execute action SUPPLY_BASE_TOKEN");
            _supply(action.amount);
        } else if (action.actionType == ActionType.WITHDRAW_BASE_TOKEN) {
            console.log("execute action WITHDRAW_BASE_TOKEN");
            _withdraw(action.amount);
        } else if (action.actionType == ActionType.BORROW_SIDE_TOKEN) {
            console.log("execute action BORROW_SIDE_TOKEN");
            _borrow(action.amount);
        } else if (action.actionType == ActionType.REPAY_SIDE_TOKEN) {
            console.log("execute action REPAY_SIDE_TOKEN");
            _repay(action.amount);
        } else if (action.actionType == ActionType.SWAP_SIDE_TO_BASE) {
            console.log("execute action SWAP_SIDE_TO_BASE");
            _swapSideToBase(action.amount);
        } else if (action.actionType == ActionType.SWAP_BASE_TO_SIDE) {
            console.log("execute action SWAP_BASE_TO_SIDE");
            _swapBaseToSide(action.amount);
        }
    }

    function _stake(uint256 _amount) internal override {
        if (!isExit) {
            _calcDeltasAndExecActions(CalculationParams(Method.STAKE, _amount, 0, getCurrentDebtRatio(), false));
        } else {
            _supply(MAX_UINT_VALUE);
        }
    }

    function _unstake(uint256 _amount) internal override returns (uint256) {
        if (!isExit) {
            _calcDeltasAndExecActions(CalculationParams(Method.UNSTAKE, OvnMath.addBasisPoints(_amount, 1), 0, getCurrentDebtRatio(), false));
        } else {
            _withdrawBase(_amount);
        }
        return _amount;
    }

    function _balance(uint256 balanceRatio) internal override {
        if (!isExit) {
            int256 debtRatio = getCurrentDebtRatio();
            int256 K3 = debtRatio + int256(balanceRatio) - (debtRatio * int256(balanceRatio)) / 1e18;
            _calcDeltasAndExecActions(CalculationParams(Method.NOTHING, 0, 0, K3, true));
        } else {
            _swapSideToBase(MAX_UINT_VALUE);
            _supply(MAX_UINT_VALUE);
        }
    }

    function getCurrentDebtRatio() public override view returns (int256) {
        uint256 sidePool = _sideAmount();
        return int256(sidePool == 0 ? 1e18 : (_borrowAmount() * 1e18 / sidePool));
    }

    function _calcDeltasAndExecActions(CalculationParams memory calculationParams) internal override {
        (Action[] memory actions, ) = _calcDeltas(calculationParams);
        _execActions(actions);
    }

    function _calcDeltas(CalculationParams memory calculationParams) internal override view returns (Action[] memory actions, Deltas memory deltas) {
        Liquidity memory liq = currentLiquidity();
        if (calculationParams.K1 == 0) {
            calculationParams.K1 = _borrowBound(calculationParams.isBalance);
        }
        int256 K2 = _pricePool();
        int256 retAmount;
        if (calculationParams.method == Method.UNSTAKE) {
            uint256 nav = this.netAssetValue();
            require(nav >= calculationParams.amount, "Not enough NAV for UNSTAKE");
            // for unstake make deficit as amount
            retAmount = - toInt256(baseToUsd(calculationParams.amount));
        }

        return IBalanceMath(balanceMath).liquidityToActions(CalcContextRequest(calculationParams.K1, K2, calculationParams.K3, retAmount, liq, allowedSlippageBp));
    }

    function _execActions(Action[] memory actions) internal override {
        console.log("--------- execute actions");
        for (uint j; j < actions.length; j++) {
            console.log(j, uint(actions[j].actionType), actions[j].amount);
            _executeAction(actions[j]);
        }
        console.log("---------");
    }

    function _currentAmounts() internal override view returns (Amounts memory) {
        (uint256 baseTokenPoolAmount, uint256 sideTokenPoolAmount) = _getStakeLiquidity();
        (uint256 baseCollateralAmount, uint256 sideBorrowAmount) = _getBorrowLiquidity();
        (uint256 baseFreeAmount, uint256 sideFreeAmount) = _getSwapLiquidity();

        return Amounts(
            baseCollateralAmount,
            sideBorrowAmount,
            baseTokenPoolAmount,
            sideTokenPoolAmount,
            baseFreeAmount,
            sideFreeAmount
        );
    }

    function _claimRewards(address _to) internal override returns (uint256) {
        if (isExit) {
            return 0;
        }

        uint256 baseBalanceBefore = baseToken.balanceOf(address(this));

        _claimStakeRewards();
        _claimBorrowRewards();

        return baseToken.balanceOf(address(this)) - baseBalanceBefore;
    }

    function _enter() internal override {
        if (!isExit) {
            return;
        }

        _calcDeltasAndExecActions(CalculationParams(Method.NOTHING, 0, 0, 1e18, true));

        isExit = false;
    }

    function _exit() internal override {
        if (isExit) {
            return;
        }

        // 0. Claim rewards before exit
        _claimRewards(address(this));

        // 1. Remove liquidity from pool
        _removeLiquidity(MAX_UINT_VALUE);

        // 2. Swap base token to side token for repay
        (, uint256 sideBorrowAmount) = _getBorrowLiquidity();
        if (sideBorrowAmount > 0) {
            sideBorrowAmount = OvnMath.addBasisPoints(sideBorrowAmount + 10, 10);
            uint256 sideTokenBalance = sideToken.balanceOf(address(this));
            if (sideBorrowAmount > sideTokenBalance) {
                _swapBaseToSide(sideToUsd(sideBorrowAmount - sideTokenBalance));
            }
        }

        // 3. Repay side token
        _repay(MAX_UINT_VALUE);

        // 4. Swap side token to base token
        _swapSideToBase(MAX_UINT_VALUE);

        // 5. Supply rest base token
        _supply(MAX_UINT_VALUE);

        // 6. Set isExit = true
        isExit = true;
    }
}

