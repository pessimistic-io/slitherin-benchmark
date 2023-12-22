// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {UpgradeableGovernable, UpgradeableOperableKeepable} from "./UpgradeableOperableKeepable.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {IRouter} from "./IRouter.sol";
import {ILP} from "./ILP.sol";
import {IOption} from "./IOption.sol";
import {ISwap} from "./ISwap.sol";

contract OptionStrategy is IOptionStrategy, UpgradeableOperableKeepable {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    struct Deltainfo {
        Option[] options;
        uint32 strike;
        uint256 amount;
        uint256 cost;
        uint256 collateralPercentage;
        bytes optionData;
        uint256 optionIndex;
        Budget budget;
        uint256 currentAmountOfLP;
        uint256 spend;
        uint256 toBuyOptions;
        uint256 toFarm;
        bool isOverpaying;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // @notice Internal representation of 100%
    uint256 private constant BASIS_POINTS = 1e12;

    IERC20 private constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // @notice The ERC20 LP token for this OptionStrategy's Metavault
    IERC20 public lpToken;

    // @notice Compound Strategy for current Metavault
    // Responsible for handling most of LPs logic
    ICompoundStrategy public compoundStrategy;

    // @notice Pair adapter, used mostly to build/break LPs
    ILP public pairAdapter;

    // @notice Default dex for this Metavault
    ISwap public swapper;

    // @notice Epoch -> Options Provider  -> Type (BULL/BEAR) -> Options
    // if 0 - means we didnt buy any of this strike
    mapping(uint16 => mapping(address => mapping(IRouter.OptionStrategy => Option[]))) public options;

    // @notice Strike -> Option Index
    mapping(uint256 => uint256) public optionIndex;

    // @notice Check if the options provider is valid
    mapping(address => bool) public validProvider;

    // @notice Epoch providers
    mapping(uint16 => IOption[]) public bullProviders;
    mapping(uint16 => IOption[]) public bearProviders;

    // @notice Check if OptionStrategy (responsible for the options purchase logic) has been executed
    mapping(uint16 => mapping(IRouter.OptionStrategy => bool)) public executedStrategy;

    // @notice hash(epoch, type, strike) => lp spend
    mapping(bytes32 => uint256) public lpSpend;

    // @notice Epoch -> Budget (accoutability of assets distribution across Bull/Bear strategies)
    mapping(uint16 => Budget) public budget;

    // @notice Amount of LP tokens borrowed from strategy to be converted to options
    mapping(IRouter.OptionStrategy => uint256) public borrowedLP;

    // @notice Weth from options
    mapping(IRouter.OptionStrategy => uint256) public wethFromOp;

    // @notice Store collected "yield" for each strategy (Bull/Bear)
    mapping(uint16 => mapping(IRouter.OptionStrategy => uint256)) public rewards;

    // @notice Get defaut adapter to be used in mid epoch deposits
    mapping(IRouter.OptionStrategy => IOption) public defaultAdapter;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initializeOpStrategy(address _lp, address _pairAdapter, address _swapper) external initializer {
        __Governable_init(msg.sender);

        if (_lp == address(0) || _pairAdapter == address(0) || _swapper == address(0)) {
            revert ZeroAddress();
        }

        lpToken = IERC20(_lp);
        pairAdapter = ILP(_pairAdapter);
        swapper = ISwap(_swapper);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Deposit Lp assets to buy options.
     * @param _epoch Sytem epoch
     * @param _amount Total amount of assets
     * @param _bullAmount Amount of assets to buy bull options
     * @param _bearAmount Amount of assets to buy bear options
     */
    function deposit(uint16 _epoch, uint256 _amount, uint256 _bullAmount, uint256 _bearAmount) external onlyOperator {
        uint128 amount = uint128(_amount);

        uint128 amountBull = uint128(_bullAmount);
        uint128 amountBear = uint128(_bearAmount);

        Budget memory _budget = budget[_epoch];

        // Updates budget to include current epochs LPs spent in options
        budget[_epoch] = Budget({
            totalDeposits: _budget.totalDeposits + amount,
            bullDeposits: _budget.bullDeposits + amountBull,
            bearDeposits: _budget.bearDeposits + amountBear,
            bullEarned: _budget.bullEarned,
            bearEarned: _budget.bearEarned,
            totalEarned: _budget.totalEarned
        });

        // Increases strategy debt
        borrowedLP[IRouter.OptionStrategy.BULL] = _budget.bullDeposits + amountBull;
        borrowedLP[IRouter.OptionStrategy.BEAR] = _budget.bearDeposits + amountBear;

        emit DebtUpdated(IRouter.OptionStrategy.BULL, _budget.bullDeposits, borrowedLP[IRouter.OptionStrategy.BULL]);
        emit DebtUpdated(IRouter.OptionStrategy.BEAR, _budget.bullDeposits, borrowedLP[IRouter.OptionStrategy.BEAR]);

        emit Deposit(_epoch, _amount, amountBull, amountBear);
    }

    /**
     * @notice Performs an options purchase for user deposit when the strategies have already been executed
     * @param _provider Options provider that is going to be used to buy
     * @param _lpAmount Amount of LP that is going to be used
     * @param _params Params to execute option pruchase
     */
    function middleEpochOptionsBuy(IOption _provider, uint256 _lpAmount, IOption.OptionParams calldata _params)
        external
        onlyOperator
    {
        uint128 lpAmount_ = uint128(_lpAmount);

        // Update budget to add more money spent in options
        Budget storage _budget = budget[_params._epoch];

        if (_params._option.type_ == IRouter.OptionStrategy.BULL) {
            _budget.bullDeposits = _budget.bullDeposits + lpAmount_;
        } else {
            _budget.bearDeposits = _budget.bearDeposits + lpAmount_;
        }

        _budget.totalDeposits = _budget.totalDeposits + lpAmount_;

        // Transfer LP to pairAdapter to perform the LP breaking and swap
        lpToken.transfer(address(pairAdapter), _lpAmount);

        ISwap.SwapData memory data;

        // Receive WETH from the break and swap process
        uint256 wethAmount = pairAdapter.performBreakAndSwap(_lpAmount, ISwap.SwapInfo({swapper: swapper, data: data}));

        // After receiving WETH, send ETH to options provider to perform the options purchase
        WETH.transfer(address(_provider), wethAmount);

        // purchase options
        _provider.purchase(_params);

        bytes32 optionHash = keccak256(abi.encode(_params._epoch, _params._option.type_, _params._option.strike));

        lpSpend[optionHash] = lpSpend[optionHash] + _lpAmount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY KEEPER                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Execute bull strategy.
     * @param _toSpend Total amount of assets (LP) to spend in the execution
     * @param _execute Params to execute the strategy with providers
     */
    function executeBullStrategy(uint128 _toSpend, ExecuteStrategy calldata _execute, ISwap.SwapInfo calldata _swapInfo)
        external
        onlyOperatorOrKeeper
    {
        // Send LP tokens to the pair adapter to handle the LP break/build
        lpToken.safeTransfer(address(pairAdapter), _toSpend);

        // Break LP to be used to buy options
        uint256 wethAmount = pairAdapter.breakLP(_toSpend, _swapInfo);

        uint256 length = _execute.providers.length;

        if (length != _execute.params.length || length != _execute.providerPercentage.length) {
            revert LengthMismatch();
        }

        // To perform the options purchases in many providers, we need to have the needed collateral available here, otherwise reverts
        for (uint256 i; i < length;) {
            address providerAddress = address(_execute.providers[i]);

            if (!validProvider[providerAddress]) {
                revert InvalidProvider();
            }

            if (_execute.params[i]._option.type_ != IRouter.OptionStrategy.BULL) {
                revert InvalidOptionType();
            }

            uint256 providerAmount = wethAmount.mulDivDown(_execute.providerPercentage[i], BASIS_POINTS);

            WETH.transfer(providerAddress, providerAmount);
            // Each provider can have different strikes format, on dopex we pass as the $ value, with 8 decimals
            _execute.providers[i].purchase(_execute.params[i]);

            bytes32 optionHash = keccak256(
                abi.encode(
                    _execute.params[i]._epoch, _execute.params[i]._option.type_, _execute.params[i]._option.strike
                )
            );

            lpSpend[optionHash] =
                lpSpend[optionHash] + uint256(_toSpend).mulDivDown(_execute.providerPercentage[i], BASIS_POINTS);

            unchecked {
                ++i;
            }
        }

        // Add used bull providers
        bullProviders[_execute.epoch] = _execute.providers;
        executedStrategy[_execute.epoch][IRouter.OptionStrategy.BULL] = true;

        emit BullStrategy(_execute.epoch, _toSpend, wethAmount, _execute.providers, _execute.providerPercentage);
    }

    /**
     * @notice In case we decide not to buy options in current epoch for the given strategy, adjust acocuntability and send LP tokens to be auto-compounded
     * @param _strategyType Bull or Bear strategy.
     * @param _epoch Current epoch
     * @dev Only operator or keeper can call this function
     */
    function startCrabStrategy(IRouter.OptionStrategy _strategyType, uint16 _epoch) external onlyOperatorOrKeeper {
        Budget storage _budget = budget[_epoch];

        ICompoundStrategy compoundStrategy_ = compoundStrategy;

        // Original amount that was going to be directed to buy options
        uint256 toBuyOptions;

        // Get budget that was deposited
        if (_strategyType == IRouter.OptionStrategy.BULL) {
            toBuyOptions = _budget.bullDeposits;

            // Set to 0 since we are no longer spending the previous amount
            _budget.bullDeposits = 0;

            // Reduce from total deposits
            _budget.totalDeposits -= uint128(toBuyOptions);
        } else {
            toBuyOptions = _budget.bearDeposits;

            // Set to 0 since we are no longer spending the previous amount
            _budget.bearDeposits = 0;

            // Reduce from total deposits
            _budget.totalDeposits -= uint128(toBuyOptions);
        }

        // Send back the premium that would be used
        lpToken.safeTransfer(address(compoundStrategy_), toBuyOptions);

        // Send back the LP to CompoundStrategy and stake
        // No need to update debt since it was not increased
        compoundStrategy_.deposit(toBuyOptions, _strategyType, false);
        executedStrategy[_epoch][_strategyType] = true;

        emit DebtUpdated(_strategyType, borrowedLP[_strategyType], 0);
        borrowedLP[_strategyType] = 0;
        emit MigrateToCrabStrategy(_strategyType, uint128(toBuyOptions));
    }

    /**
     * @notice Execute bear strategy.
     * @param _toSpend Total amount of assets to expend in the execution
     * @param _execute Params to execute the strategy with providers
     * @param _swapInfo Info to do the swap
     */
    function executeBearStrategy(uint128 _toSpend, ExecuteStrategy calldata _execute, ISwap.SwapInfo calldata _swapInfo)
        external
        onlyOperatorOrKeeper
    {
        lpToken.safeTransfer(address(pairAdapter), _toSpend);

        // Break LP
        uint256 wethAmount = pairAdapter.breakLP(_toSpend, _swapInfo);

        uint256 length = _execute.providers.length;

        if (length != _execute.params.length || length != _execute.providerPercentage.length) {
            revert LengthMismatch();
        }

        for (uint256 i; i < length;) {
            address providerAddress = address(_execute.providers[i]);

            if (!validProvider[providerAddress]) {
                revert InvalidProvider();
            }

            if (_execute.params[i]._option.type_ != IRouter.OptionStrategy.BEAR) {
                revert InvalidOptionType();
            }

            uint256 providerAmount = wethAmount.mulDivDown(_execute.providerPercentage[i], BASIS_POINTS);

            WETH.transfer(providerAddress, providerAmount);

            // Each provider can have different strikes format, on dopex we pass as the $ value, with 8 decimals
            _execute.providers[i].purchase(_execute.params[i]);

            bytes32 optionHash = keccak256(
                abi.encode(
                    _execute.params[i]._epoch, _execute.params[i]._option.type_, _execute.params[i]._option.strike
                )
            );

            lpSpend[optionHash] =
                lpSpend[optionHash] + uint256(_toSpend).mulDivDown(_execute.providerPercentage[i], BASIS_POINTS);

            unchecked {
                ++i;
            }
        }

        // Add used bear providers
        bearProviders[_execute.epoch] = _execute.providers;
        executedStrategy[_execute.epoch][IRouter.OptionStrategy.BEAR] = true;

        emit BearStrategy(_execute.epoch, _toSpend, wethAmount, _execute.providers, _execute.providerPercentage);
    }

    /**
     * @notice Collect Option Rewards.
     * @param _collect Params need to collect rewards
     */
    function collectRewards(CollectRewards calldata _collect) external onlyOperatorOrKeeper {
        Option[] memory _options = options[_collect.epoch][_collect.provider][_collect.type_];

        uint256 length = _options.length;

        // Iterate through providers used this epoch and settle options if pnl > 0
        for (uint256 i; i < length;) {
            if (!validProvider[_collect.provider]) {
                revert InvalidProvider();
            }

            if (_collect.type_ != _options[i].type_) {
                revert InvalidOptionType();
            }

            // Store rewards in WETH
            IOption(_collect.provider).settle(IOption.OptionParams(_collect.epoch, _options[i], _collect.optionData[i]));

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Realize Option Rewards.
     * @param _epoch system epoch
     * @param _type Bull or Bear strategy.
     * @param _swapInfo Swap data
     */
    function realizeRewards(uint16 _epoch, IRouter.OptionStrategy _type, ISwap.SwapInfo calldata _swapInfo)
        external
        onlyOperatorOrKeeper
        returns (uint256)
    {
        uint256 wethCollected = wethFromOp[_type];

        emit DebtUpdated(_type, borrowedLP[_type], 0);
        borrowedLP[_type] = 0;

        emit CollectRewardsEpochEnd(_type, wethCollected);

        if (wethCollected > 0) {
            // If we had a non zero PNL, send to the pair adapter in order to build the LP
            WETH.transfer(address(pairAdapter), wethCollected);

            // Effectively build LP and store amount received
            uint256 lpRewards = pairAdapter.buildLP(wethCollected, _swapInfo);

            // Store received LP according to the epoch and strategy
            rewards[_epoch][_type] += lpRewards;

            Budget storage _budget = budget[_epoch];

            // Increase current epochs rewards
            if (_type == IRouter.OptionStrategy.BULL) {
                _budget.bullEarned = _budget.bullEarned + uint128(lpRewards);
            } else {
                _budget.bearEarned = _budget.bearEarned + uint128(lpRewards);
            }

            _budget.totalEarned = _budget.totalEarned + uint128(lpRewards);

            // Send profits to CompoundStrategy and stake it
            lpToken.transfer(address(compoundStrategy), lpRewards);
            compoundStrategy.deposit(lpRewards, _type, false);

            wethFromOp[_type] = 0;

            return lpRewards;
        } else {
            return 0;
        }
    }

    /**
     * @notice Update Option WETH Rewards
     * @param _type Bull/Bear
     * @param _wethAmount Amount of WETH rewards
     */
    function afterSettleOptions(IRouter.OptionStrategy _type, uint256 _wethAmount) external onlyOperator {
        wethFromOp[_type] = wethFromOp[_type] + _wethAmount;
    }

    /**
     * @notice Update Borrowed LP.
     * @param _type Bull/Bear
     * @param _collateralAmount Amount of LP that is going to be used
     */
    function afterMiddleEpochOptionsBuy(IRouter.OptionStrategy _type, uint256 _collateralAmount)
        external
        onlyOperator
    {
        // Increase debt (LP used to buy options)
        borrowedLP[_type] = borrowedLP[_type] + _collateralAmount;

        emit DebtUpdated(_type, borrowedLP[_type] - _collateralAmount, borrowedLP[_type]);
    }

    /**
     * @notice Add Option data.
     * @param _epoch System epoch
     * @param _type Type of Strategy (BULL/BEAR)
     * @param _option Option data
     */
    function addBoughtStrikes(uint16 _epoch, IRouter.OptionStrategy _type, Option calldata _option)
        external
        onlyOperator
    {
        Option[] storage _options = options[_epoch][msg.sender][_type];
        uint256 _optionIndex = optionIndex[_option.strike];

        if (_optionIndex == 0) {
            _options.push(_option);
            optionIndex[_option.strike] = _options.length;
        } else {
            _optionIndex = _optionIndex - 1;
            _options[_optionIndex].amount = _options[_optionIndex].amount + _option.amount;
            _options[_optionIndex].cost = _options[_optionIndex].cost + _option.cost;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets Strike array containing data needed about bought strikes to perform mid epoch ingress
     * @param _epoch System epoch
     * @param _provider Option provider
     * @param _type Option Strategy type (BULL/BEAR)
     * @return Options bought and relevant information about them.
     */
    function getOptions(uint16 _epoch, address _provider, IRouter.OptionStrategy _type)
        external
        view
        returns (Option[] memory)
    {
        return options[_epoch][_provider][_type];
    }

    /**
     * @notice Gets PNL quoted in LP token for all open options positions
     * @param _epoch System epoch
     * @param _type Bull/Bear
     * @return PNL quoted in LP tokens
     */
    function optionPosition(uint16 _epoch, IRouter.OptionStrategy _type) external view returns (uint256) {
        uint256 totalPosition;
        uint256 _borrowedLP;
        IOption[] memory _providers;

        // Get providers according to the strategy we are checking
        if (_type == IRouter.OptionStrategy.BULL) {
            _providers = bullProviders[_epoch];
        } else {
            _providers = bearProviders[_epoch];
        }
        uint256 length = _providers.length;

        for (uint256 i; i < length;) {
            // Gets what our option position is worth
            // position() returns ETH value
            totalPosition = totalPosition + _providers[i].position(address(this), address(compoundStrategy), _type);

            unchecked {
                ++i;
            }
        }

        _borrowedLP = borrowedLP[_type];

        uint256 positionInLp;

        // If we made money on options, convert to LP
        if (totalPosition > 0) {
            positionInLp = pairAdapter.ETHtoLP(totalPosition);
        }

        // After converting options PNL to LP, check if its bigger than what was spent buying them
        if (positionInLp > _borrowedLP) {
            return positionInLp - _borrowedLP;
        }

        // If it reaches here it means we have no profit
        return 0;
    }

    function compareStrikes(uint256 _costPaid, uint256 _currentCost, uint256 _baseAmount)
        external
        view
        returns (uint256 toBuyOptions, uint256 toFarm, bool isOverpaying)
    {
        return _compareStrikes(_costPaid, _currentCost, _baseAmount);
    }

    // Calculates the % of the difference between price paid for options and current price. Returns an array with the % that matches the indexes of the strikes.
    function deltaPrice(
        uint16 _epoch,
        // Users normal LP spent would be equivalent to the option risk. but since its a mid epoch deposit, it can be higher in order to offset options price appreciation
        // This the LP amount adjusted to the epochs risk profile.
        // To be calculated we get the user total LP amount, calculate option risk threshold, with this number we use the percentageOverTotalCollateral to get amount for each strike
        uint256 _userAmountOfLp,
        IRouter.OptionStrategy _strategy,
        bytes calldata _optionOrder,
        address _provider
    ) external view returns (OptionOverpayAndData memory) {
        Deltainfo memory info;

        info.options = options[_epoch][_provider][_strategy];
        (info.strike, info.amount, info.cost, info.collateralPercentage, info.optionData) =
            abi.decode(_optionOrder, (uint32, uint256, uint256, uint256, bytes));

        info.optionIndex = optionIndex[info.strike] - 1;

        if (info.strike != info.options[info.optionIndex].strike) {
            revert InvalidStrike();
        }

        info.budget = budget[_epoch];

        // Since we store the collateral spend of each option, we need to convert the user collateral amount destined to each option
        // Based in Epochs risk
        // This is the "baseAmount"

        info.spend = lpSpend[keccak256(
            abi.encode(_epoch, info.options[info.optionIndex].type_, info.options[info.optionIndex].strike)
        )];

        if (_strategy == IRouter.OptionStrategy.BULL) {
            info.currentAmountOfLP = _userAmountOfLp.mulDivDown(info.spend, info.budget.bullDeposits);
        } else {
            info.currentAmountOfLP = _userAmountOfLp.mulDivDown(info.spend, info.budget.bearDeposits);
        }

        // Compare strikes and calculate amounts to buy options and to farm
        (info.toBuyOptions, info.toFarm, info.isOverpaying) = _compareStrikes(
            info.options[info.optionIndex].cost.mulDivDown(BASIS_POINTS, info.options[info.optionIndex].amount),
            info.cost.mulDivDown(BASIS_POINTS, info.amount),
            info.currentAmountOfLP
        );

        // Return amount of collateral we need to use in each strike
        return OptionOverpayAndData(
            info.strike,
            info.amount,
            info.cost,
            info.optionData,
            info.collateralPercentage,
            info.toBuyOptions,
            info.toFarm,
            info.isOverpaying
        );
    }

    function getBullProviders(uint16 epoch) external view returns (IOption[] memory) {
        return bullProviders[epoch];
    }

    function getBearProviders(uint16 epoch) external view returns (IOption[] memory) {
        return bearProviders[epoch];
    }

    function getBudget(uint16 _epoch) external view returns (Budget memory) {
        return budget[_epoch];
    }

    /* -------------------------------------------------------------------------- */
    /*                                     PRIVATE                                */
    /* -------------------------------------------------------------------------- */

    // @notice Returns percentage increase or decrease of option price now comparing with the price on strategy execution
    function _calculatePercentageDifference(uint256 _priceBefore, uint256 _priceNow) private pure returns (uint256) {
        // Calculate the absolute difference between the two numbers
        uint256 diff = (_priceBefore > _priceNow) ? _priceBefore - _priceNow : _priceNow - _priceBefore;

        // Calculate the percentage using 1e12 as 100%
        return (diff * BASIS_POINTS) / _priceBefore;
    }

    /**
     * @notice Calculates how user's LP are going to be spread across options/farm in order to maintain the correct system proportions
     * @param _costPaid How much was paid for one option of the given strike
     * @param _currentCost How much this option is now worth
     * @param _baseAmount Calculated by getting the percentageOverTotatalCollateral
     * @return toBuyOptions How much of users deposited LP is going to be used to purchase options
     * @return toFarm How much of users deposited LP is going to be sent to the farm
     * @return isOverpaying If its true, it means options are now more expensive than at first epoch buy at strategy execution
     */
    function _compareStrikes(uint256 _costPaid, uint256 _currentCost, uint256 _baseAmount)
        private
        view
        returns (uint256 toBuyOptions, uint256 toFarm, bool isOverpaying)
    {
        uint256 differencePercentage = _calculatePercentageDifference(_costPaid, _currentCost);

        if (_currentCost > _costPaid) {
            // If options are now more expensive, we will use a bigger amount of the user's LP
            toBuyOptions = _baseAmount.mulDivUp((BASIS_POINTS + differencePercentage), BASIS_POINTS);
            isOverpaying = true;
            toFarm = 0;
        } else {
            // If options are now cheaper, we will use a smaller amount of the user's LP
            toBuyOptions = _baseAmount.mulDivUp((BASIS_POINTS - differencePercentage), BASIS_POINTS);

            toFarm = _baseAmount - toBuyOptions;
            isOverpaying = false;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function initApproves(address[] calldata _target, address[] calldata _token) external onlyGovernor {
        uint256 length = _target.length;

        if (length != _token.length) {
            revert LengthMismatch();
        }

        for (uint256 i; i < length;) {
            IERC20(_token[i]).approve(_target[i], type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    function addProvider(address _provider) public onlyGovernor {
        if (_provider == address(0)) {
            revert ZeroAddress();
        }

        validProvider[_provider] = true;

        emit AddOptionProvider(_provider);

        WETH.approve(_provider, type(uint256).max);
    }

    function batchAddProviders(address[] calldata _providers) external {
        uint256 length = _providers.length;

        for (uint256 i; i < length;) {
            addProvider(_providers[i]);

            unchecked {
                ++i;
            }
        }
    }

    function removeProvider(address _provider) public onlyGovernor {
        if (_provider == address(0)) {
            revert ZeroAddress();
        }

        validProvider[_provider] = false;

        emit RemoveOptionProvider(_provider);

        WETH.approve(_provider, 0);
    }

    function batchRemoveProviders(address[] calldata _providers) external {
        uint256 length = _providers.length;

        for (uint256 i; i < length;) {
            removeProvider(_providers[i]);

            unchecked {
                ++i;
            }
        }
    }

    function setCompoundStrategy(address _compoundStrategy) external onlyGovernor {
        if (_compoundStrategy == address(0)) {
            revert ZeroAddress();
        }

        emit UpdateCompoundStrategy(address(compoundStrategy), _compoundStrategy);

        compoundStrategy = ICompoundStrategy(_compoundStrategy);
    }

    function updatePairAdapter(address _pairAdapter) external onlyGovernor {
        if (_pairAdapter == address(0)) {
            revert ZeroAddress();
        }

        emit UpdatePairAdapter(address(pairAdapter), _pairAdapter);

        pairAdapter = ILP(_pairAdapter);
    }

    function updateSwapper(address _swapper) external onlyGovernor {
        if (_swapper == address(0)) {
            revert ZeroAddress();
        }

        emit UpdateSwapper(address(swapper), _swapper);

        swapper = ISwap(_swapper);
    }

    function setDefaultProviders(address _bullProvider, address _bearProvider) external onlyGovernor {
        if (_bullProvider == address(0) || _bearProvider == address(0)) {
            revert ZeroAddress();
        }
        defaultAdapter[IRouter.OptionStrategy.BULL] = IOption(_bullProvider);
        defaultAdapter[IRouter.OptionStrategy.BEAR] = IOption(_bearProvider);
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyGovernor {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Deposit(uint256 indexed epoch, uint256 lpAmount, uint256 bullAmount, uint256 bearAmount);
    event BullStrategy(
        uint16 indexed epoch, uint128 toSpend, uint256 wethAmount, IOption[] providers, uint256[] amount
    );
    event DebtUpdated(IRouter.OptionStrategy indexed _strategy, uint256 oldDebt, uint256 currentDebt);
    event BearStrategy(
        uint16 indexed epoch, uint128 toSpend, uint256 wethAmount, IOption[] providers, uint256[] amount
    );
    event MigrateToCrabStrategy(IRouter.OptionStrategy indexed _from, uint128 _amount);
    event CollectRewardsEpochEnd(IRouter.OptionStrategy indexed strategyType, uint256 wethColleccted);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);
    event UpdateDefaultDopexProviders(address callsSsov, address putsSsov);
    event UpdateSwapper(address oldSwapper, address newSwapper);
    event UpdatePairAdapter(address oldPairAdapter, address newPairAdapter);
    event UpdateCompoundStrategy(address oldCompoundStrategy, address newCompoundStrategy);
    event RemoveOptionProvider(address removedOptionProvider);
    event AddOptionProvider(address newOptionProvider);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error ZeroAddress();
    error InvalidProvider();
    error InvalidBuilder();
    error InvalidStrike();
    error InvalidOptionType();
    error LengthMismatch();
    error InvalidCollateralUsage();
    error FailSendETH();
}

