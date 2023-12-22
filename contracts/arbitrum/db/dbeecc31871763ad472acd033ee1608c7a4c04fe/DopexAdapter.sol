// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

// Abstract Classes
import {UpgradeableOperableKeepable} from "./UpgradeableOperableKeepable.sol";
// Interfaces
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {IOption} from "./IOption.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IRouter} from "./IRouter.sol";
import {ISSOV, IERC20} from "./ISSOV.sol";
import {ISSOVViewer} from "./ISSOVViewer.sol";
import {ISwap} from "./ISwap.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IVault} from "./IVault.sol";
//Libraries
import {Curve2PoolAdapter} from "./Curve2PoolAdapter.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {BalancerWstethAdapter} from "./BalancerWstethAdapter.sol";
import {AssetsPricing} from "./AssetsPricing.sol";

contract DopexAdapter is IOption, UpgradeableOperableKeepable {
    using FixedPointMathLib for uint256;
    using Curve2PoolAdapter for IStableSwap;
    using BalancerWstethAdapter for IVault;

    // Info needed to perform a swap
    struct SwapData {
        // Swapper used
        ISwap swapper;
        // Encoded data we are passing to the swap
        bytes data;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // @notice Represents 100% in our internal math.
    uint256 private constant BASIS_POINTS = 1e12;

    // @notice Used to calculate amounts on 18 decimals tokens
    uint256 private constant PRECISION = 1e18;

    // @notice USDC uses 6 decimals instead of "standard" 18
    uint256 private constant USDC_DECIMALS = 1e6;

    // @notice Used to find amount of available liquidity on dopex ssovs
    uint256 private constant DOPEX_BASIS = 1e8;

    // @notice Slippage to set in the swaps in order to remove risk of failing
    uint256 public slippage;

    // @notice Tokens used in the underlying logic
    IERC20 private constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 private constant wstETH = IERC20(0x5979D7b546E38E414F7E9822514be443A4800529);
    IERC20 private constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // @notice DopEx contract that objectively buys/settles options
    ISSOV public ssov;

    // @notice SSOV's collateral token. Calls -> wstETH / Puts -> 2CRV
    IERC20 public collateralToken;

    // @notice Can either be CALLS or PUTS. We have one DopEx adapter for either option
    OPTION_TYPE public optionType;

    // @notice System epoch (same as the one in CompoundStrategy) => SSOV's epoch
    mapping(uint256 => uint256) public epochs;

    // @notice DopEx viewer to fetch some info.
    ISSOVViewer public constant viewer = ISSOVViewer(0x9abE93F7A70998f1836C2Ee0E21988Ca87072001);

    // @notice Curve 2CRV (USDC-USDT)
    IStableSwap private constant CRV = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    // @notice Balancer Vault responsible for the swaps and pools
    IVault private constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // @notice Sushi contract that routes the swaps
    address private constant SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    // @notice Sushi WETH_USDC pool
    address private constant WETH_USDC = 0x905dfCD5649217c42684f23958568e533C711Aa3;

    // @notice The OptionStrategy contract that manages purchasing/settling options
    IOptionStrategy private optionStrategy;

    // @notice Compounding Strategy: where we will handle the LPs and distribute to strategies.
    ICompoundStrategy private compoundStrategy;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes the transparent proxy of the DopExAdapter
     * @param _type Represent if its CALLS/PUTS adapter
     * @param _ssov DopEx SSOV for the given _type
     * @param _slippage Default slippage to prevent swaps fails
     * @param _optionStrategy Option Strategy that manages the purchases/settles
     * @param _compoundStrategy Compound Strategy that manages the LPs and auto compound them
     */
    function initializeOptionAdapter(
        OPTION_TYPE _type,
        ISSOV _ssov,
        uint256 _slippage,
        IOptionStrategy _optionStrategy,
        ICompoundStrategy _compoundStrategy
    ) external initializer {
        __Governable_init(msg.sender);

        if (address(_ssov) == address(0) || address(_optionStrategy) == address(0)) {
            revert ZeroAddress();
        }

        if (_slippage > BASIS_POINTS) {
            revert OutOfRange();
        }

        // Store ssov in storage
        ssov = _ssov;

        optionStrategy = _optionStrategy;
        // Collateral token of given ssov
        collateralToken = _ssov.collateralToken();

        // Call or Put
        optionType = _type;

        // Internal Slippage
        slippage = _slippage;

        compoundStrategy = _compoundStrategy;
    }

    /* -------------------------------------------------------------------------- */
    /*                           ONLY OPERATOR AND KEEPER                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Buy options.
     * @param params Parameter needed to buy options.
     */
    function purchase(ExecuteParams calldata params) public onlyOperatorOrKeeper {
        // Load desired SSOV from mapping.
        ISSOV _ssov = ssov;

        // Load the collateral token of the SSOV
        IERC20 _collateralToken = collateralToken;

        address thisAddress = address(this);

        // Swaps received WETH to options collateral token
        // wstETH for CALLS and 2crv for puts
        _swapToCollateral(WETH.balanceOf(thisAddress), address(_collateralToken), thisAddress);

        // Gets total collateral we have
        uint256 totalCollateral = _collateralToken.balanceOf(thisAddress);

        if (totalCollateral == 0) {
            revert NotEnoughCollateral();
        }

        // Approve for spending on DopEx
        _collateralToken.approve(address(_ssov), totalCollateral);

        // Store current SSOV epoch
        uint256 ssovEpoch = _ssov.currentEpoch();

        epochs[params.currentEpoch] = ssovEpoch;

        // Buy options
        _executeOptionsPurchase(
            _ssov,
            params.currentEpoch,
            totalCollateral,
            params._collateralEachStrike,
            params._expiry,
            params._strikes,
            thisAddress
        );

        // Emit event showing the prices of the strikes we bought and other relevant info
        emit SSOVPurchase(
            _ssov.currentEpoch(),
            params._strikes,
            params._collateralEachStrike,
            totalCollateral,
            address(_collateralToken)
        );
    }

    /**
     * @notice Exercise ITM options.
     * @param params Parameter needed to settle options.
     */
    function settle(SettleParams calldata params) public onlyOperatorOrKeeper returns (uint256) {
        // Load ssov
        ISSOV _ssov = ssov;

        // Get current Epoch
        ISSOV.EpochData memory epochData = _ssov.getEpochData(params.optionEpoch);

        // These are the tokens receipts received when buying options
        address[] memory strikeTokens = viewer.getEpochStrikeTokens(params.optionEpoch, _ssov);

        address thisAddress = address(this);

        for (uint256 i = 0; i < strikeTokens.length;) {
            // TODO: Check if instantiating locally will reduce gas costs
            uint256 strike = params.strikesToSettle[i];

            // Get the receipt token of the desired strike
            IERC20 strikeToken = IERC20(strikeTokens[i]);

            // Get how many options we bought at the strike, since options were sent to strategy we check its balance
            uint256 strikeTokenBalance = strikeToken.balanceOf(address(this));

            // Calcualate if the option is profitable (ITM)
            uint256 strikePnl = _ssov.calculatePnl(
                epochData.settlementPrice, strike, strikeTokenBalance, epochData.settlementCollateralExchangeRate
            );

            // Check if the strike was profitable and if we have this strike options
            if (strikeTokenBalance > 0 && strikePnl > 0) {
                // If profitable, approve and settle the option.
                strikeToken.approve(address(_ssov), strikeTokenBalance);
                _ssov.settle(i, strikeTokenBalance, params.optionEpoch, thisAddress);
            }

            unchecked {
                ++i;
            }
        }

        // Get received tokens after settling
        uint256 rewards = collateralToken.balanceOf(thisAddress);

        // If options ended ITM we will receive > 0
        if (rewards > 0) {
            // Swap wstETH or 2CRV to WETH
            address collateralAddress = address(collateralToken);

            _swapToWeth(rewards, collateralAddress);

            // Received amount after converting collateral to WETH
            uint256 wethAmount = WETH.balanceOf(thisAddress);

            // Transfer to Option Strategy
            WETH.transfer(msg.sender, wethAmount);

            return wethAmount;
        } else {
            return 0;
        }
    }

    /**
     * @notice Buy options in mid epoch.
     * @param _strike $ Value of the strike in 8 decimals.
     * @param _wethAmount Amount used to buy options.
     */
    function executeSingleOptionPurchase(uint256 _strike, uint256 _wethAmount)
        external
        onlyOperator
        returns (uint256)
    {
        ISSOV _ssov = ssov;

        IERC20 _collateralToken = collateralToken;

        address collateralAddress = address(_collateralToken);

        // Swap WETH received to collateral token
        _swapToCollateral(_wethAmount, collateralAddress, address(this));

        // Collateral that will be used to buy options
        uint256 collateral = _collateralToken.balanceOf(address(this));

        // Store current SSOV epoch
        uint256 _currentEpoch = _ssov.currentEpoch();

        // Returns how many optiosn we can buy with a given amount of collateral
        (uint256 optionsAmount,) =
            estimateOptionsPerToken(collateral, _strike, _ssov.getEpochData(_currentEpoch).expiry);

        // Cant buy 0 options
        if (optionsAmount == 0) {
            revert ZeroAmount();
        }

        collateralToken.approve(address(_ssov), collateral);

        // Purchase options and get costs
        (uint256 _premium, uint256 _fee) = _ssov.purchase(_getStrikeIndex(_ssov, _strike), optionsAmount, address(this));

        emit SSOVSinglePurchase(_currentEpoch, collateral, optionsAmount, _premium + _fee);

        return _premium + _fee;
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    // Get how much premium we are paying in total
    // Get the premium of each strike and sum, so we can store after epoch start and compare with other deposits
    function getTotalPremium(uint256[] calldata _strikes, uint256 _expiry)
        private
        view
        returns (uint256 _totalPremium)
    {
        uint256 precision = 10000e18;
        uint256 length = _strikes.length;

        for (uint256 i; i < length;) {
            // Get premium for the given strike, quoted in the underlying token
            _totalPremium += ssov.calculatePremium(_strikes[i], precision, _expiry);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Gets how many options we can get from an amount of tokens.
     * @param _tokenAmount Amount of options that can be bought, according to collateral and liquidity
     * @param _strike $ value in 8 decimals
     * @param _expiry When the option expire
     */
    function estimateOptionsPerToken(uint256 _tokenAmount, uint256 _strike, uint256 _expiry)
        public
        view
        returns (uint256, uint256)
    {
        ISSOV _option = ssov;

        // Get the strikes total options available
        uint256 availableAtDesiredStrike = getAvailableOptions(_strike);

        // The amount of tokens used to buy an amount of options is
        // the premium + purchase fee.
        // We calculate those values using `precision` as the amount.
        // Knowing how many tokens that cost we can estimate how many
        // Options we can buy using `_tokenAmount`
        uint256 precision = 10000e18;

        // Get premium, quoted in underlying token
        uint256 premiumPerOption = _option.calculatePremium(_strike, precision, _expiry);

        // Get premium for one option
        uint256 premiumSingleOption = _option.calculatePremium(_strike, PRECISION, _expiry);

        // Get Dopex purchase retention, quoted in underlying token
        uint256 feePerOption = _option.calculatePurchaseFees(_strike, precision);

        // Get Dopex purchase retention for one option
        uint256 feeSingleOption = _option.calculatePurchaseFees(_strike, PRECISION);

        // Return amount of options that can be bought
        uint256 amountThatCanBeBought = (_tokenAmount * precision) / (premiumPerOption + feePerOption);

        // If our simulation is bigger than total options available, we return the maximum we can buy (total options available)
        return (
            amountThatCanBeBought > availableAtDesiredStrike ? availableAtDesiredStrike : amountThatCanBeBought,
            premiumSingleOption + feeSingleOption
        );
    }

    // Gets option type and strike value in USD (8 decimals), returns liquidity in collateral token. Calls: wsteth / Puts: 2crv
    function getAvailableOptions(uint256 _strike) public view returns (uint256 availableAtDesiredStrike) {
        ISSOV _ssov = ssov;

        // Get SSOVs current epoch
        uint256 currentEpoch = _ssov.currentEpoch();

        // We subtract total amount of collateral for the amount of collateral bought
        availableAtDesiredStrike = _ssov.getEpochStrikeData(currentEpoch, _strike).totalCollateral
            - _ssov.getEpochStrikeData(currentEpoch, _strike).activeCollateral;

        // If its not a PUT ssov, we apply the collateralExchangeRate in order to get the final options amount at the desired strike
        if (!_ssov.isPut()) {
            availableAtDesiredStrike =
                (availableAtDesiredStrike * DOPEX_BASIS) / _ssov.getEpochData(currentEpoch).collateralExchangeRate;
        }
    }

    // Function to get the price (in collateral token) for the given strike.
    // @param _strike quoted in USD, with 8 decimals. 1e18 = 1 option
    function getOptionPrice(uint256 _strike) public view returns (uint256) {
        // Get SSOV for given input (calls/puts)
        ISSOV _ssov = ssov;

        // Get premium, quoted in underlying token
        uint256 premiumPerOption =
            _ssov.calculatePremium(_strike, PRECISION, _ssov.getEpochData(_ssov.currentEpoch()).expiry);

        // Get Dopex purchase retention, quoted in underlying token
        uint256 feePerOption = _ssov.calculatePurchaseFees(_strike, PRECISION);

        return premiumPerOption + feePerOption;
    }

    // Function to get the price (in collateral token) for all the epochs strikes.
    // @param _strike quoted in USD, with 8 decimals. 1e18 = 1 option
    function geAllStrikestPrices() public view returns (uint256[] memory) {
        // Get SSOV for given input (calls/puts)
        ISSOV _ssov = ssov;

        // Get current strike's strikes
        uint256[] memory currentStrikes = getCurrentStrikes();

        // Amount of strikes
        uint256 length = currentStrikes.length;

        // Output array
        uint256[] memory currentPrices = new uint256[](length);

        for (uint256 i; i < length;) {
            // Get premium, quoted in underlying token
            uint256 premiumPerOption =
                _ssov.calculatePremium(currentStrikes[i], PRECISION, _ssov.getEpochData(_ssov.currentEpoch()).expiry);

            // Get Dopex purchase retention, quoted in underlying token
            uint256 feePerOption = _ssov.calculatePurchaseFees(currentStrikes[i], PRECISION);

            // Get price in underlying token
            currentPrices[i] = premiumPerOption + feePerOption;

            unchecked {
                ++i;
            }
        }

        return currentPrices;
    }

    // In mid epoch deposits, we need to simulate how many options we can buy with the given LP and see if we have enough liquidity
    // This function given an amount of LP, gives the amount of collateral token we are receiving
    // We can use `estimateOptionsPerToken` to convert the receivable amount of collateral token to options.
    // @param _amount amount of lp tokens
    function lpToCollateral(address _lp, uint256 _amount) external view returns (uint256) {
        ISSOV _ssov = ssov;
        uint256 _amountOfEther;
        IUniswapV2Pair pair = IUniswapV2Pair(_lp);

        // Calls -> wstETH / Puts -> 2crv
        // First, lets get the notional value of `_amount`
        // Very precise but not 100%
        (uint256 token0Amount, uint256 token1Amount) = AssetsPricing.breakFromLiquidityAmount(_lp, _amount);

        // Amount of collateral
        uint256 collateral;

        uint256 wethAmount;

        // Convert received tokens from LP to WETH.
        // This function gets maxAmountOut and accounts for slippage + fees
        // We dont support LPs that doesnt have WETH in its composition (for now)
        if (pair.token0() == address(WETH)) {
            wethAmount += token0Amount + AssetsPricing.getAmountOut(_lp, token1Amount, pair.token1(), address(WETH));
        } else if (pair.token1() == address(WETH)) {
            wethAmount += token1Amount + AssetsPricing.getAmountOut(_lp, token0Amount, pair.token0(), address(WETH));
        } else {
            revert NoSupport();
        }

        // Uses 2crv
        if (_ssov.isPut()) {
            // Value in USDC that is later converted to 2CRV
            // AssetsPricing.ethPriceInUsdc() returns 6 decimals
            uint256 ethPriceInUsdc = AssetsPricing.getAmountOut(WETH_USDC, wethAmount, address(WETH), address(USDC));

            collateral = AssetsPricing.get2CrvAmountFromDeposit(ethPriceInUsdc);
        } else {
            // Calls use wstETH
            // Get ratio (18 decimals)
            uint256 ratio = AssetsPricing.wstEthRatio();

            // Calculate eth amount * wstEth oracle ratio and then "remove" decimals from oracle
            // Amount of ether = 18 decimals / Ratio oracle = 18 decimals
            collateral = (_amountOfEther * PRECISION) / ratio;
        }

        // We got previously the amount of collateral token converting the ETH part of the LP
        // Since the ETH part should have the same USD value of the other part, we just do the number we got * 2
        return collateral;
    }

    function amountOfOptions(uint256 _epoch, uint256 _strikeIndex) external view returns (uint256) {
        uint256 epoch = epochs[_epoch];
        ISSOV _ssov = ssov;
        ISSOV.EpochData memory epochData = _ssov.getEpochData(epoch);

        return IERC20(_ssov.getEpochStrikeData(epoch, epochData.strikes[_strikeIndex]).strikeToken).balanceOf(
            address(this)
        );
    }

    /**
     * @notice Gets PNL and convert to WETH if > 0
     */
    function position() external view returns (uint256) {
        uint256 pnl_ = _pnl();

        if (pnl_ > 0) {
            address collateralAddress = address(collateralToken);

            uint256 wethAmount;

            if (collateralAddress == address(CRV)) {
                // 18 decimals
                uint256 usdcAmount = CRV.calc_withdraw_one_coin(pnl_, 0);
                // 8 decimals
                uint256 usdcRatio = AssetsPricing.usdcPriceInUsd(USDC_DECIMALS);
                // 8 decimals
                uint256 ethRatio = AssetsPricing.ethPriceInUsd(PRECISION);

                wethAmount = usdcAmount.mulDivDown(usdcRatio * BASIS_POINTS, ethRatio);
            } else {
                uint256 ratio = AssetsPricing.wstEthRatio();
                wethAmount = pnl_.mulDivDown(ratio, PRECISION);
            }

            return wethAmount;
        }

        return 0;
    }

    // Simulate outcome of the bought options if we were exercising now
    function pnl() external view returns (uint256 pnl_) {
        return _pnl();
    }

    function getCollateralToken() external view returns (address) {
        return address(collateralToken);
    }

    function strategy() external view override returns (IRouter.OptionStrategy _strategy) {
        if (optionType == OPTION_TYPE.CALLS) {
            return IRouter.OptionStrategy.BULL;
        } else {
            return IRouter.OptionStrategy.BEAR;
        }
    }

    /**
     * @notice Get current SSOV epoch expiry
     */
    function getExpiry() external view returns (uint256) {
        ISSOV _ssov = ssov;

        return _ssov.getEpochData(_ssov.currentEpoch()).expiry;
    }

    /**
     * @notice Get current epoch's strikes
     */
    function getCurrentStrikes() public view returns (uint256[] memory strikes) {
        ISSOV _ssov = ssov;

        return _ssov.getEpochData(_ssov.currentEpoch()).strikes;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function updateSlippage(uint256 _slippage) external onlyGovernor {
        // Some checks
        if (_slippage > BASIS_POINTS) {
            revert OutOfRange();
        }

        slippage = _slippage;
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
    /*                                     PRIVATE                                */
    /* -------------------------------------------------------------------------- */

    function _executeOptionsPurchase(
        ISSOV _ssov,
        uint256 _epoch,
        uint256 _totalCollateral,
        uint256[] calldata _collateralEachStrike,
        uint256 _expiry,
        uint256[] calldata _strikes,
        address _thisAddress
    ) private {
        for (uint256 i; i < _strikes.length; ++i) {
            // If its 0 it means we are not buying any option in this strike
            if (_collateralEachStrike[i] == 0) continue;

            // Copy to memory to avoid Stack Too Deep
            uint256[] memory collateralEachStrike = _collateralEachStrike;

            // Simulate how many options will be bought with the desidered collateral %
            // strikesToBuy needs to be in $ value. ie: $2100
            // IMPORTANT: _strikes[i] and _percentageEachStrike need to match DopEx strikes!!!

            uint256 collateralAmount = _totalCollateral.mulDivDown(_collateralEachStrike[i], BASIS_POINTS);
            (uint256 optionsAmount,) = estimateOptionsPerToken(collateralAmount, _strikes[i], _expiry);

            // Cant purchase 0 options
            if (optionsAmount == 0) revert ZeroAmount();

            // Buys options and sends to receiver
            (uint256 premium, uint256 totalFee) = _ssov.purchase(i, optionsAmount, _thisAddress);

            // Add the bought strike data to the storage of Option Strategy in order to handle mid epoch deposits
            IOptionStrategy(msg.sender).addBoughtStrikes(
                _epoch,
                IOption(_thisAddress),
                IOptionStrategy.Strike({
                    price: _strikes[i],
                    costIndividual: (premium + totalFee).mulDivDown(PRECISION, optionsAmount),
                    costTotal: premium + totalFee,
                    percentageOverTotalCollateral: collateralEachStrike[i]
                })
            );
        }
    }

    // On calls swap wETH to wstETH / on puts swap to 2crv and return amount received of collateral token
    function _swapToCollateral(uint256 _wethAmount, address _collateralToken, address _thisAddress)
        private
        returns (uint256)
    {
        uint256 slippage_ = slippage;
        uint256 minAmountOut;

        if (_collateralToken == address(wstETH)) {
            uint256 ratio = AssetsPricing.wstEthRatio();

            minAmountOut = _wethAmount.mulDivDown(PRECISION, ratio).mulDivDown(slippage_, BASIS_POINTS);

            IERC20(_collateralToken).approve(address(BALANCER_VAULT), _wethAmount);

            return
                BALANCER_VAULT.swapWethToWstEth(_thisAddress, _thisAddress, _wethAmount, minAmountOut, block.timestamp);
        }

        // Get the USDC value of _wethAmount
        uint256 minStableAmount = AssetsPricing.ethPriceInUsdc(_wethAmount).mulDivDown(slippage_, BASIS_POINTS);

        // Simulate depositing USDC and minting 2crv, applying slippage_ in the final amount
        minAmountOut = AssetsPricing.get2CrvAmountFromDeposit(minStableAmount).mulDivDown(slippage_, BASIS_POINTS);

        WETH.approve(SUSHI_ROUTER, _wethAmount);

        return
            CRV.swapTokenFor2Crv(address(WETH), _wethAmount, address(USDC), minStableAmount, minAmountOut, _thisAddress);
    }

    function _swapToWeth(uint256 _collateralAmount, address _collateralToken) private returns (uint256) {
        uint256 slippage_ = slippage;
        uint256 minAmountOut;

        // Calls scenario
        if (_collateralToken == address(wstETH)) {
            uint256 ratio = AssetsPricing.wstEthRatio();

            // Get min amount out in WETH by converting WSTETH to WETH
            // Apply slippage to final result
            minAmountOut = _collateralAmount.mulDivDown(ratio, PRECISION).mulDivDown(slippage_, BASIS_POINTS);

            IERC20(_collateralToken).approve(address(BALANCER_VAULT), _collateralAmount);

            // Swap WSTETH -> WETH
            return BALANCER_VAULT.swapWstEthToWeth(
                address(this), address(this), _collateralAmount, minAmountOut, block.timestamp
            );
        }

        // Puts scenario
        // Simulate withdrawing 2CRV -> USDC
        // Returns 6 decimals
        uint256 amountOut = AssetsPricing.getUsdcAmountFromWithdraw(_collateralAmount);

        if (amountOut > 1e6) {
            uint256 ethPrice = AssetsPricing.ethPriceInUsd(PRECISION);
            uint256 usdcPrice = AssetsPricing.usdcPriceInUsd(USDC_DECIMALS);

            // Apply slippage to amount of USDC we get from 2CRV
            uint256 minStableAmount = amountOut.mulDivDown(slippage_, BASIS_POINTS);

            // WETH minAmountOut
            minAmountOut =
                minStableAmount.mulDivDown(usdcPrice * BASIS_POINTS, ethPrice).mulDivDown(slippage_, BASIS_POINTS);

            IERC20(_collateralToken).approve(SUSHI_ROUTER, _collateralAmount);

            return CRV.swap2CrvForToken(
                address(WETH), _collateralAmount, address(USDC), minStableAmount, minAmountOut, address(this)
            );
        }

        return 0;
    }

    /**
     * @notice Given the notional value of a strike, return its index
     */
    function _getStrikeIndex(ISSOV _ssov, uint256 _strike) private view returns (uint256) {
        uint256[] memory strikes = _ssov.getEpochData(_ssov.currentEpoch()).strikes;

        for (uint256 i; i < strikes.length; i++) {
            if (strikes[i] == _strike) return i;
        }

        revert StrikeNotFound(_strike);
    }

    /**
     * @notice return current option pnl
     * @return pnl_ if > 0, the amount of profit we will have, quoted in options collateral token
     */
    function _pnl() private view returns (uint256 pnl_) {
        // Get SSOV for calls/puts
        ISSOV ssov_ = ssov;

        uint256 ssovEpoch = ssov_.currentEpoch();
        address thisAddress = address(this);

        // Load strikes from current epoch for the given SSOV
        ISSOV.EpochData memory epochData = ssov_.getEpochData(ssovEpoch);
        uint256[] memory strikes = epochData.strikes;

        uint256 length = strikes.length;

        // We need to take into account the paid cost of the option
        IOptionStrategy.Strike[] memory boughtStrikes =
            IOptionStrategy(optionStrategy).getBoughtStrikes(compoundStrategy.currentEpoch(), IOption(thisAddress));

        // Check PNL checking individually PNL on each strike we bought
        for (uint256 i; i < length;) {
            // We get the amount of options we have by checking the balanceOf optionStrategy of the receipt token for the given strike
            uint256 options = IERC20(ssov_.getEpochStrikeData(ssovEpoch, strikes[i]).strikeToken).balanceOf(thisAddress);

            // If we didnt buy any of this strikes' options, continue to the next strike
            if (options > 0) {
                // Puts do not need the field `collateralExchangeRate` so we cant set to 0. If its a CALL, we get from DoPex
                uint256 collateralExchangeRate =
                    optionType == IOption.OPTION_TYPE.PUTS ? 0 : epochData.collateralExchangeRate;

                // Calculate PNL given current underlying token price, strike value in $ (8 decimals) and amount of options we bought.
                pnl_ += ssov_.calculatePnl(ssov_.getUnderlyingPrice(), strikes[i], options, collateralExchangeRate);

                // Amount of collateral paid to buy options in the given strike (premium + fees)
                uint256 totalCostCurrentStrike = _getCostPaid(boughtStrikes, strikes[i]);

                // If pnl > premium + fees
                if (pnl_ > totalCostCurrentStrike) {
                    pnl_ = pnl_ - totalCostCurrentStrike;

                    if (pnl_ > 0) {
                        // Settlement fee is around 0.1% of PNL.
                        unchecked {
                            pnl_ -= ssov_.calculateSettlementFees(pnl_);
                        }
                    }
                } else {
                    pnl_ = 0;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get total cost for one of the purchased strikes
     * @param boughtStrikes Array containing relevant information about bougthStrikes
     * @param _strike Strike we are checking costs
     * @return Returns total costs quoted in options collateral token
     */
    function _getCostPaid(IOptionStrategy.Strike[] memory boughtStrikes, uint256 _strike)
        private
        pure
        returns (uint256)
    {
        for (uint256 i; i < boughtStrikes.length; i++) {
            if (boughtStrikes[i].price == _strike) return boughtStrikes[i].costTotal;
        }

        revert StrikeNotFound(_strike);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * Emitted when new Deposit to SSOV is made
     * @param _epoch SSOV epoch (indexed)
     * @param _strikeIndex SSOV strike index
     * @param _amount deposited Collateral Token amount
     * @param _tokenId token ID of the deposit
     */
    event SSOVDeposit(uint256 indexed _epoch, uint256 _strikeIndex, uint256 _amount, uint256 _tokenId);

    event SSOVPurchase(
        uint256 indexed _epoch, uint256[] strikes, uint256[] _percentageEachStrike, uint256 _amount, address _token
    );

    event SSOVSinglePurchase(uint256 indexed _epoch, uint256 _amount, uint256 _optionAmount, uint256 _cost);

    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error OutOfRange();
    error NotEnoughCollateral();
    error ZeroAmount();
    error FailSendETH();
    error StrikeNotFound(uint256 strikeNotionalValue);
    error NoSupport();
    error ZeroAddress();
}

