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

    // @notice Epoch -> Options Provider (Call/Put) -> {Strike settlement price, option cost}
    // if 0 - means we didnt buy any of this strike
    mapping(uint256 => mapping(IOption => Strike[])) public boughtStrikes;

    // @notice Check if the options provider is valid
    mapping(address => bool) public validProvider;

    // @notice Epoch providers
    mapping(uint256 => IOption[]) public bullProviders;
    mapping(uint256 => IOption[]) public bearProviders;

    // @notice Check if OptionStrategy (responsible for the options purchase logic) has been executed
    mapping(uint256 => mapping(IRouter.OptionStrategy => bool)) public executedStrategy;

    // @notice Epoch -> Budget (accoutability of assets distribution across Bull/Bear strategies)
    mapping(uint256 => Budget) public budget;

    // @notice Amount of LP tokens borrowed from strategy to be converted to options
    mapping(IRouter.OptionStrategy => uint256) public borrowedLP;

    // @notice Store collected "yield" for each strategy (Bull/Bear)
    mapping(uint256 => mapping(IOption.OPTION_TYPE => uint256)) public rewards;

    // @notice Get dopex adapter to be used in mid epoch deposits
    mapping(IOption.OPTION_TYPE => IOption) public dopexAdapter;

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
    function deposit(uint256 _epoch, uint256 _amount, uint256 _bullAmount, uint256 _bearAmount) external onlyOperator {
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

        emit Deposit(_epoch, _amount, amountBull, amountBear);
    }

    /**
     * @notice Performs an options purchase for user deposit when the strategies have already been executed
     * @param _epoch System epoch
     * @param _type Bull/Bear
     * @param _provider Options provider that is going to be used to buy
     * @param _collateralAmount Amount of LP that is going to be used
     * @param _strike Strike that is going to be bought
     */
    function middleEpochOptionsBuy(
        uint256 _epoch,
        IRouter.OptionStrategy _type,
        IOption _provider,
        uint256 _collateralAmount,
        uint256 _strike
    ) external onlyOperator returns (uint256) {
        uint128 collateralAmount_ = uint128(_collateralAmount);

        // Update budget to add more money spent in options
        Budget storage _budget = budget[_epoch];

        if (_type == IRouter.OptionStrategy.BULL) {
            _budget.bullDeposits = _budget.bullDeposits + collateralAmount_;
        } else {
            _budget.bearEarned = _budget.bearDeposits + collateralAmount_;
        }

        _budget.totalDeposits = _budget.totalDeposits + collateralAmount_;

        // Increase debt (LP used to buy options)
        borrowedLP[_type] = borrowedLP[_type] + collateralAmount_;

        // Transfer LP to pairAdapter to perform the LP breaking and swap
        lpToken.transfer(address(pairAdapter), _collateralAmount);

        // Receive WETH from the break and swap process
        uint256 wethAmount = pairAdapter.performBreakAndSwap(_collateralAmount, swapper);

        // After receiving WETH, send ETH to options provider to perform the options purchase
        WETH.transfer(address(_provider), wethAmount);

        // Returns purchasing costs
        return _provider.executeSingleOptionPurchase(_strike, wethAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY KEEPER                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Execute bull strategy.
     * @param _epoch Sytem epoch
     * @param _toSpend Total amount of assets (LP) to spend in the execution
     * @param _execute Params to execute the strategy with providers
     */
    function executeBullStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute)
        external
        onlyOperatorOrKeeper
    {
        // Send LP tokens to the pair adapter to handle the LP break/build
        lpToken.safeTransfer(address(pairAdapter), _toSpend);

        ILP.LpInfo memory lpInfo = ILP.LpInfo({swapper: swapper, externalData: ""});

        // Break LP to be used to buy options
        uint256 wethAmount = pairAdapter.breakLP(_toSpend, lpInfo);

        uint256 length = _execute.providers.length;

        if (length != _execute.providerPercentage.length || length != _execute.expiry.length) {
            revert LengthMismatch();
        }

        // To perform the options purchases, we need to have the needed collateral available here, otherwise reverts
        for (uint256 i; i < length;) {
            address providerAddress = address(_execute.providers[i]);

            if (!validProvider[providerAddress]) {
                revert InvalidProvider();
            }

            WETH.transfer(providerAddress, wethAmount.mulDivDown(_execute.providerPercentage[i], BASIS_POINTS));
            // Each provider can have different strikes format, on dopex we pass as the $ value, with 8 decimals
            _execute.providers[i].purchase(
                IOption.ExecuteParams(
                    _epoch,
                    _execute.strikes[i],
                    _execute.collateralEachStrike[i],
                    _execute.expiry[i],
                    _execute.externalData[i]
                )
            );

            unchecked {
                ++i;
            }
        }

        // Add used bull providers
        bullProviders[_epoch] = _execute.providers;
        executedStrategy[_epoch][IRouter.OptionStrategy.BULL] = true;

        emit BullStrategy();
    }

    /**
     * @notice In case we decide not to buy options in current epoch for the given strategy, adjust acocuntability and send LP tokens to be auto-compounded
     * @param _strategyType Bull or Bear strategy.
     * @param _epoch Current epoch
     * @dev Only operator or keeper can call this function
     */
    function startCrabStrategy(IRouter.OptionStrategy _strategyType, uint256 _epoch) external onlyOperatorOrKeeper {
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
        borrowedLP[_strategyType] = 0;

        emit MigrateToCrabStrategy(_strategyType, uint128(toBuyOptions));
    }

    /**
     * @notice Execute bear strategy.
     * @param _epoch Sytem epoch
     * @param _toSpend Total amount of assets to expend in the execution
     * @param _execute Params to execute the strategy with providers
     */
    function executeBearStrategy(uint256 _epoch, uint128 _toSpend, ExecuteStrategy calldata _execute)
        external
        onlyOperatorOrKeeper
    {
        lpToken.safeTransfer(address(pairAdapter), _toSpend);

        ILP.LpInfo memory lpInfo = ILP.LpInfo({swapper: swapper, externalData: ""});

        // Break LP
        uint256 wethAmount = pairAdapter.breakLP(_toSpend, lpInfo);

        uint256 length = _execute.providers.length;

        if (length != _execute.providerPercentage.length || length != _execute.expiry.length) {
            revert LengthMismatch();
        }

        for (uint256 i; i < length;) {
            address providerAddress = address(_execute.providers[i]);

            if (!validProvider[providerAddress]) {
                revert InvalidProvider();
            }

            if (_execute.collateralEachStrike[i].length != _execute.strikes[i].length) revert LengthMismatch();

            WETH.transfer(providerAddress, wethAmount.mulDivDown(_execute.providerPercentage[i], BASIS_POINTS));

            // Each provider can have different strikes format, on dopex we pass as the $ value, with 8 decimals
            _execute.providers[i].purchase(
                IOption.ExecuteParams(
                    _epoch,
                    _execute.strikes[i],
                    _execute.collateralEachStrike[i],
                    _execute.expiry[i],
                    _execute.externalData[i]
                )
            );

            unchecked {
                ++i;
            }
        }

        // Add used bear providers
        bearProviders[_epoch] = _execute.providers;
        executedStrategy[_epoch][IRouter.OptionStrategy.BEAR] = true;

        emit BearStrategy();
    }

    /**
     * @notice Collect Option Rewards.
     * @param _type Type of strategy
     * @param _collect Params need to collect rewards
     * @param _externalData In case its needed for the Pair Adapter
     */

    function collectRewards(IOption.OPTION_TYPE _type, CollectRewards calldata _collect, bytes memory _externalData)
        external
        onlyOperatorOrKeeper
        returns (uint256)
    {
        uint256 length = _collect.providers.length;

        uint256 wethCollected;

        // Iterate through providers used this epoch and settle options if pnl > 0
        for (uint256 i; i < length;) {
            address providerAddress = address(_collect.providers[i]);
            if (!validProvider[providerAddress]) {
                revert InvalidProvider();
            }

            if (_type != IOption(_collect.providers[i]).optionType()) {
                revert InvalidType();
            }

            // Store rewards in WETH
            wethCollected = wethCollected
                + _collect.providers[i].settle(
                    IOption.SettleParams(
                        _collect.currentEpoch,
                        IOption(_collect.providers[i]).epochs(_collect.currentEpoch),
                        _collect.strikes[i],
                        _collect.externalData[i]
                    )
                );

            unchecked {
                ++i;
            }
        }

        if (wethCollected > 0) {
            // If we had a non zero PNL, send to the pair adapter in order to build the LP
            WETH.transfer(address(pairAdapter), wethCollected);

            // Struct containing information to build the LP
            ILP.LpInfo memory lpInfo = ILP.LpInfo({swapper: swapper, externalData: _externalData});

            // Effectively build LP and store amount received
            uint256 lpRewards = pairAdapter.buildLP(wethCollected, lpInfo);

            // Store received LP according to the epoch and strategy
            rewards[_collect.currentEpoch][_type] += lpRewards;

            IRouter.OptionStrategy _vaultType =
                _type == IOption.OPTION_TYPE.CALLS ? IRouter.OptionStrategy.BULL : IRouter.OptionStrategy.BEAR;

            Budget storage _budget = budget[_collect.currentEpoch];

            // Increase current epochs rewards
            if (_type == IOption.OPTION_TYPE.CALLS) {
                _budget.bullEarned = _budget.bullEarned + uint128(lpRewards);
            } else {
                _budget.bearEarned = _budget.bearEarned + uint128(lpRewards);
            }

            _budget.totalEarned = _budget.totalEarned + uint128(lpRewards);

            // Send profits to CompoundStrategy and stake it
            lpToken.transfer(address(compoundStrategy), lpRewards);
            compoundStrategy.deposit(lpRewards, _vaultType, false);

            borrowedLP[_vaultType] = 0;

            return lpRewards;
        } else {
            return 0;
        }
    }

    function middleEpochOptionsBuy(IOption _provider, uint256 _collateralAmount, uint256 _strike)
        external
        onlyOperator
        returns (uint256)
    {
        lpToken.transfer(address(pairAdapter), _collateralAmount);

        // Receive WETH from this
        uint256 wethAmount = pairAdapter.performBreakAndSwap(_collateralAmount, swapper);

        // After receiving weth, perform purchases
        WETH.transfer(address(_provider), wethAmount);

        // returns purchasing costs
        return _provider.executeSingleOptionPurchase(_strike, wethAmount);
    }

    function addBoughtStrikes(uint256 _epoch, IOption _provider, Strike memory _data) external onlyOperator {
        Strike[] storage current = boughtStrikes[_epoch][_provider];
        current.push(_data);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets Strike array containing data needed about bought strikes to perform mid epoch ingress
     * @param _epoch System epoch
     * @param _provider Option provider
     * @return Strikes bought and relevant information about them
     */
    function getBoughtStrikes(uint256 _epoch, IOption _provider) external view returns (Strike[] memory) {
        return boughtStrikes[_epoch][_provider];
    }

    /**
     * @notice Gets PNL quoted in LP token for all open options positions
     * @param _epoch System epoch
     * @param _type Bull/Bear
     * @return PNL quoted in LP tokens
     */
    function optionPosition(uint256 _epoch, IRouter.OptionStrategy _type) external view returns (uint256) {
        uint256 totalPosition;
        uint256 _borrowedLP;

        // Get providers according to the strategy we are checking
        if (_type == IRouter.OptionStrategy.BULL) {
            IOption[] memory _providers = bullProviders[_epoch];
            uint256 length = _providers.length;

            for (uint256 i; i < length;) {
                // Gets what our option position is worth
                // position() returns ETH value
                totalPosition = totalPosition + _providers[i].position();

                unchecked {
                    ++i;
                }
            }

            _borrowedLP = borrowedLP[IRouter.OptionStrategy.BULL];
        } else {
            IOption[] memory _providers = bearProviders[_epoch];
            uint256 length = _providers.length;
            for (uint256 j; j < length;) {
                // Gets what our option position is worth
                // position() returns ETH value
                totalPosition = totalPosition + _providers[j].position();

                unchecked {
                    ++j;
                }
            }

            _borrowedLP = borrowedLP[IRouter.OptionStrategy.BEAR];
        }

        // If we are in profit in oour options purchase, convert profits to LP
        if (totalPosition > _borrowedLP) {
            return pairAdapter.ETHtoLP(totalPosition) - _borrowedLP;
        }

        // If it reaches here it means we have no profit
        return 0;
    }

    function compareStrikes(uint256 _costPaid, uint256 _currentCost, uint256 _baseAmount)
        external
        pure
        returns (uint256 toBuyOptions, uint256 toFarm, bool isOverpaying)
    {
        return _compareStrikes(_costPaid, _currentCost, _baseAmount);
    }

    // Calculates the % of the difference between price paid for options and current price. Returns an array with the % that matches the indexes of the strikes.
    function deltaPrice(
        uint256 _epoch,
        // Users normal LP spent would be equivalent to the option risk. but since its a mid epoch deposit, it can be higher in order to offset options price appreciation
        // This the LP amount adjusted to the epochs risk profile.
        // To be calculated we get the user total LP amount, calculate option risk threshold, with this number we use the percentageOverTotalCollateral to get amount for each strike
        uint256 userAmountOfLp,
        IOption _provider
    ) external view returns (DifferenceAndOverpaying[] memory) {
        // Get what prices we have paid on each options strike when bootstrappig.
        // 0 means we didnt buy any of the given strike
        Strike[] memory _boughtStrikes = boughtStrikes[_epoch][_provider];

        DifferenceAndOverpaying[] memory amountCollateralEachStrike = new DifferenceAndOverpaying[](
                _boughtStrikes.length
            );

        for (uint256 i; i < _boughtStrikes.length;) {
            // Get current bought strike
            Strike memory current = _boughtStrikes[i];

            // Since we store the collateral each strike, we need to convert the user collateral amount destined to options to each strike
            // Based in Epochs risk
            // This is the "baseAmount"
            uint256 currentAmountOfLP = (current.percentageOverTotalCollateral * userAmountOfLp) / BASIS_POINTS;

            // Get price paid in strike (always in collateral token)
            uint256 costPaid = current.costIndividual;

            // Epoch strike price (eg: 1800e8)
            uint256 strike = current.price;

            // Get current price
            uint256 currentCost = _provider.getOptionPrice(strike);

            // Compare strikes and calculate amounts to buy options and to farm
            (uint256 toBuyOptions, uint256 toFarm, bool isOverpaying) =
                _compareStrikes(costPaid, currentCost, currentAmountOfLP);

            amountCollateralEachStrike[i] =
                DifferenceAndOverpaying(strike, currentCost, toBuyOptions, toFarm, isOverpaying);

            unchecked {
                ++i;
            }
        }

        // Return amount of collateral we need to use in each strike
        return amountCollateralEachStrike;
    }

    function getBullProviders(uint256 epoch) external view returns (IOption[] memory) {
        return bullProviders[epoch];
    }

    function getBearProviders(uint256 epoch) external view returns (IOption[] memory) {
        return bearProviders[epoch];
    }

    function getBudget(uint256 _epoch) external view returns (Budget memory) {
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
        pure
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

        compoundStrategy = ICompoundStrategy(_compoundStrategy);
    }

    function updatePairAdapter(address _pairAdapter) external onlyGovernor {
        if (_pairAdapter == address(0)) {
            revert ZeroAddress();
        }

        pairAdapter = ILP(_pairAdapter);
    }

    function updateSwapper(address _swapper) external onlyGovernor {
        if (_swapper == address(0)) {
            revert ZeroAddress();
        }

        swapper = ISwap(_swapper);
    }

    function setDefaultProviders(address _bullProvider, address _bearProvider) external onlyGovernor {
        if (_bullProvider == address(0) || _bearProvider == address(0)) {
            revert ZeroAddress();
        }

        dopexAdapter[IOption.OPTION_TYPE.CALLS] = IOption(_bullProvider);
        dopexAdapter[IOption.OPTION_TYPE.PUTS] = IOption(_bullProvider);
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
    event BullStrategy();
    event BearStrategy();
    event MigrateToCrabStrategy(IRouter.OptionStrategy indexed _from, uint128 _amount);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error ZeroAddress();
    error InvalidProvider();
    error InvalidBuilder();
    error InvalidType();
    error LengthMismatch();
    error InvalidCollateralUsage();
    error FailSendETH();
}

