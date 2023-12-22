// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "./console.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IQuoterV2} from "./IQuoterV2.sol";
import {TransferHelper} from "./TransferHelper.sol";
import {IERC20} from "./contracts_IERC20.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {SafeMath} from "./SafeMath.sol";
import {INotionalERC20} from "./INotionalERC20.sol";
import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {IGuild} from "./IGuild.sol";
import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {ITazzHelper} from "./ITazzHelper.sol";
import {IUniswapQuoterV3} from "./IUniswapQuoterV3.sol";
import {X96Math} from "./X96Math.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DebtMath} from "./DebtMath.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";

/**
 * @title TazzHelper
 * @author Tazz Labs
 */
contract TazzHelper is ITazzHelper {
    using SafeMath for uint256;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using CollateralConfiguration for DataTypes.CollateralConfigurationMap;

    uint256 internal constant QUOTE_TIME_BUFFER = 900; //15min buffer for QuoteWithdraw + QuoteBorrow estimtates

    ISwapRouter public immutable uniswapRouter;
    IUniswapQuoterV3 public immutable uniswapQuoter;

    constructor(address _swapRouterAddress, address _quoterAddress) {
        uniswapRouter = ISwapRouter(_swapRouterAddress);
        uniswapQuoter = IUniswapQuoterV3(_quoterAddress);
    }

    /// @inheritdoc ITazzHelper
    function swapZTokenForExactMoney(
        address _guildAddress,
        uint256 _moneyOut,
        uint256 _zTokenInMax,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_
        )
    {
        return
            _swapZTokenForMoney(
                true,
                _guildAddress,
                _zTokenInMax,
                _moneyOut,
                msg.sender,
                _deadline,
                _sqrtPriceLimitX96
            );
    }

    /// @inheritdoc ITazzHelper
    function swapExactZTokenForMoney(
        address _guildAddress,
        uint256 _zTokenIn,
        uint256 _moneyOutMin,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_
        )
    {
        return
            _swapZTokenForMoney(
                false,
                _guildAddress,
                _zTokenIn,
                _moneyOutMin,
                msg.sender,
                _deadline,
                _sqrtPriceLimitX96
            );
    }

    /// @inheritdoc ITazzHelper
    function swapMoneyForExactZToken(
        address _guildAddress,
        uint256 _ztokenOut,
        uint256 _moneyInMax,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurneInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_
        )
    {
        return
            _swapMoneyForZToken(
                false,
                _guildAddress,
                _moneyInMax,
                _ztokenOut,
                msg.sender,
                _deadline,
                _sqrtPriceLimitX96
            );
    }

    /// @inheritdoc ITazzHelper
    function swapExactMoneyForZToken(
        address _guildAddress,
        uint256 _moneyIn,
        uint256 _zTokenOutMin,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_
        )
    {
        return
            _swapMoneyForZToken(
                true,
                _guildAddress,
                _moneyIn,
                _zTokenOutMin,
                msg.sender,
                _deadline,
                _sqrtPriceLimitX96
            );
    }

    /// @inheritdoc ITazzHelper
    /// @dev Not to be run on-chain
    function quoteSwapZTokenForExactMoney(
        address _guildAddress,
        uint256 _moneyOutTarget,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        return _quoteSwapZTokenForMoney(true, _guildAddress, 0, _moneyOutTarget, _sqrtPriceLimitX96);
    }

    /// @inheritdoc ITazzHelper
    /// @dev Not to be run on-chain
    function quoteSwapExactZTokenForMoney(
        address _guildAddress,
        uint256 _zTokenInTarget,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        return _quoteSwapZTokenForMoney(false, _guildAddress, _zTokenInTarget, 0, _sqrtPriceLimitX96);
    }

    /// @inheritdoc ITazzHelper
    /// @dev Not to be run on-chain
    function quoteSwapMoneyForExactZToken(
        address _guildAddress,
        uint256 _zTokenOutTarget,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        return _quoteSwapMoneyForZToken(false, _guildAddress, 0, _zTokenOutTarget, _sqrtPriceLimitX96);
    }

    /// @inheritdoc ITazzHelper
    /// @dev Not to be run on-chain
    function quoteSwapExactMoneyForZToken(
        address _guildAddress,
        uint256 _moneyInTarget,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        return _quoteSwapMoneyForZToken(true, _guildAddress, _moneyInTarget, 0, _sqrtPriceLimitX96);
    }

    /// @inheritdoc ITazzHelper
    /// @dev Not to be run on-chain
    function quoteUserAccountData(address _guildAddress, address user)
        external
        returns (IGuild.userAccountDataStruc memory userAccountData)
    {
        IGuild _guild = IGuild(_guildAddress);

        //Update states (including APY, notionals)
        _guild.refinance();

        //return user data
        return _guild.getUserAccountData(user);
    }

    /// @inheritdoc ITazzHelper
    function quoteDexLiquidty(address guild) external view returns (uint256 moneyAmount, uint256 zTokenAmount) {
        return _quoteDexLiquidty(guild);
    }

    /// @inheritdoc ITazzHelper
    function quoteDeposit(
        address guild,
        address asset,
        uint256 amount
    ) external view returns (uint256 maxDepositAmount_) {
        maxDepositAmount_ = IERC20(asset).balanceOf(msg.sender);
        IGuild(guild).validateDeposit(asset, amount, msg.sender);
    }

    /// @inheritdoc ITazzHelper
    function quoteWithdraw(
        address guild,
        address asset,
        uint256 amount
    ) external returns (uint256 currentCollateralInVault) {
        //Run guild validations (except HF validation)
        IGuild(guild).validateWithdraw(asset, amount, msg.sender);

        //validate this amount can be withdrawn (from a health factor perspective)
        uint256 maxCollateralWithdraw = _quoteMaxWithdaw(guild, asset, msg.sender);
        require(amount <= maxCollateralWithdraw, Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD);

        currentCollateralInVault = IGuild(guild).getCollateralBalanceOf(msg.sender, asset);
    }

    struct quoteMaxSwapZTokenForMoneyLocalVars {
        address zToken;
        address money;
        uint24 dexFee;
        uint256 walletZTokens;
        uint256 availableZTokenBorrows;
    }

    /// @inheritdoc ITazzHelper
    function quoteMaxSwapZTokenForMoney(
        address guild,
        address user,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 maxFullZTokenIn,
            uint256 maxFullMoneyOut,
            uint256 maxLimitZTokenIn,
            uint256 maxLimitMoneyOut
        )
    {
        IGuild _guild = IGuild(guild);
        quoteMaxSwapZTokenForMoneyLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.money = address(_perpetualDebt.money);
        vars.dexFee = _perpetualDebt.dexOracle.dex.fee;

        _guild.refinance();

        //Initialize return defaults
        maxFullZTokenIn = 0;
        maxFullMoneyOut = 0;
        maxLimitZTokenIn = 0;
        maxLimitMoneyOut = 0;

        //get Max that can be borrowed
        IGuild.userAccountDataStruc memory userAccountData = _guild.getUserAccountData(user);

        //apply a time buffer (to ensure quote is valid for QUOTE_TIME_BUFFER seconds)
        vars.availableZTokenBorrows = userAccountData.availableBorrowsInZTokens.rayDiv(_quoteBufferFactor(guild));

        //get users zToken wallet amount
        vars.walletZTokens = _guild.getAsset().balanceOf(user);

        maxLimitZTokenIn = vars.walletZTokens;
        maxFullZTokenIn = vars.walletZTokens + vars.availableZTokenBorrows;

        //Calculate Full quote
        if (maxFullZTokenIn > 0) {
            (maxFullZTokenIn, maxFullMoneyOut, , ) = uniswapQuoter.quoteExactInputSingle(
                IUniswapQuoterV3.QuoteExactInputSingleParams({
                    tokenIn: vars.zToken,
                    tokenOut: vars.money,
                    amountIn: maxFullZTokenIn,
                    fee: vars.dexFee,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            );
        }

        //Calculate Limit quote
        if (maxLimitZTokenIn > 0) {
            (maxLimitZTokenIn, maxLimitMoneyOut, , ) = uniswapQuoter.quoteExactInputSingle(
                IUniswapQuoterV3.QuoteExactInputSingleParams({
                    tokenIn: vars.zToken,
                    tokenOut: vars.money,
                    amountIn: maxLimitZTokenIn,
                    fee: vars.dexFee,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            );
        }

        return (maxFullZTokenIn, maxFullMoneyOut, maxLimitZTokenIn, maxLimitMoneyOut);
    }

    struct quoteMaxSwapMoneyForZTokenLocalVars {
        address zToken;
        address dToken;
        address money;
        uint24 dexFee;
    }

    /// @inheritdoc ITazzHelper
    function quoteMaxSwapMoneyForZToken(
        address guild,
        address user,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 maxFullMoneyIn,
            uint256 maxFullZTokenOut,
            uint256 maxLimitMoneyIn,
            uint256 maxLimitZTokenOut
        )
    {
        IGuild _guild = IGuild(guild);
        quoteMaxSwapMoneyForZTokenLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.dToken = address(_perpetualDebt.dToken);
        vars.money = address(_perpetualDebt.money);
        vars.dexFee = _perpetualDebt.dexOracle.dex.fee;

        //Initialize return defaults
        maxFullMoneyIn = 0;
        maxFullZTokenOut = 0;
        maxLimitMoneyIn = 0;
        maxLimitZTokenOut = 0;

        //get user money in wallet
        maxFullMoneyIn = _guild.getMoney().balanceOf(user);

        if (maxFullMoneyIn > 0) {
            (maxFullMoneyIn, maxFullZTokenOut, , ) = uniswapQuoter.quoteExactInputSingle(
                IUniswapQuoterV3.QuoteExactInputSingleParams({
                    tokenIn: vars.money,
                    tokenOut: vars.zToken,
                    amountIn: maxFullMoneyIn,
                    fee: vars.dexFee,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            );
        }

        //Update states (including APY, notionals)
        _guild.refinance();

        //get zTokens needed to cancel debt
        IGuild.userAccountDataStruc memory userAccountData = _guild.getUserAccountData(user);

        if (maxFullZTokenOut <= userAccountData.zTokensToRepayDebt) {
            //not enough money in wallet to fully cancel debt (or limited by pricelimit), so Limit amount = Full amount
            maxLimitMoneyIn = maxFullMoneyIn;
            maxLimitZTokenOut = maxFullZTokenOut;
        } else {
            //calculate money needed to fully cancel debt
            if (userAccountData.zTokensToRepayDebt > 0) {
                (maxLimitMoneyIn, maxLimitZTokenOut, , ) = uniswapQuoter.quoteExactOutputSingle(
                    IUniswapQuoterV3.QuoteExactOutputSingleParams({
                        tokenIn: vars.money,
                        tokenOut: vars.zToken,
                        amount: userAccountData.zTokensToRepayDebt,
                        fee: vars.dexFee,
                        sqrtPriceLimitX96: sqrtPriceLimitX96
                    })
                );
            }
        }

        return (maxFullMoneyIn, maxFullZTokenOut, maxLimitMoneyIn, maxLimitZTokenOut);
    }

    /// @inheritdoc ITazzHelper
    function quoteMaxDeposit(
        address guild,
        address asset,
        address user
    ) external view returns (uint256 maxCollateralDeposit) {
        maxCollateralDeposit = IERC20(asset).balanceOf(user);

        //Check collateral caps, and impose if necessary
        DataTypes.CollateralConfigurationMap memory collateralConfig = IGuild(guild).getCollateralConfiguration(asset);
        (uint256 maxCollateralAmount, uint256 maxUserCollateralAmount) = collateralConfig.getCaps();
        uint256 collateralUnits = 10**collateralConfig.getDecimals();
        if (maxCollateralAmount > 0) {
            //@dev supplyCap encoded with 0 decimal places (e.g, 1 -> 1 token in collateral's own unit)
            maxCollateralAmount = maxCollateralAmount * collateralUnits;
            uint256 guildCollateralBalance = IGuild(guild).getCollateralTotalBalance(asset);
            uint256 maxCollateralAllowed = (maxCollateralAmount > guildCollateralBalance)
                ? maxCollateralAmount - guildCollateralBalance
                : 0;

            if (maxCollateralDeposit > maxCollateralAllowed) maxCollateralDeposit = maxCollateralAllowed;
        }
        if (maxUserCollateralAmount > 0) {
            //@dev userSupplyCap encoded with 2 decimal places (e.g, 100 -> 1 token in collateral's own unit)
            maxUserCollateralAmount = (maxUserCollateralAmount * collateralUnits) / 100;
            uint256 userCollateralBalance = IGuild(guild).getCollateralBalanceOf(user, asset);
            uint256 maxUserCollateralAllowed = (maxUserCollateralAmount > userCollateralBalance)
                ? maxUserCollateralAmount - userCollateralBalance
                : 0;

            if (maxCollateralDeposit > maxUserCollateralAllowed) maxCollateralDeposit = maxUserCollateralAllowed;
        }
        return maxCollateralDeposit;
    }

    /// @inheritdoc ITazzHelper
    function quoteMaxWithdaw(
        address guild,
        address asset,
        address user
    ) external returns (uint256 maxCollateralWithdraw) {
        return _quoteMaxWithdaw(guild, asset, user);
    }

    /// @inheritdoc ITazzHelper
    function quoteCurrentSqrtPriceX96(address _guildAddress) external view returns (uint160 sqrtPriceX96_) {
        IGuild _guild = IGuild(_guildAddress);
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        (sqrtPriceX96_, , , , , , ) = IUniswapV3PoolState(_perpetualDebt.dexOracle.dex.poolAddress).slot0();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////

    struct swapMoneyForZTokenLocalVars {
        address zToken;
        address dToken;
        address money;
        uint24 fee;
        uint256 amountOutMinimum;
        uint256 zTokensUsedToRepayDebt;
        uint256 debtNotionalToBurn;
        uint256 debtNotionalToBurnInBaseCurrency;
        uint256 zTokenToTransfer;
        uint256 finalMoneyIn;
        uint256 finalZTokenOut;
    }

    function _swapMoneyForZToken(
        bool _exactMoney,
        address _guildAddress,
        uint256 _moneyInTarget,
        uint256 _zTokenOutTarget,
        address _onBehalfOf,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        internal
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_
        )
    {
        // Fetch perpetual debt objects from guild
        IGuild _guild = IGuild(_guildAddress);
        swapMoneyForZTokenLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.dToken = address(_perpetualDebt.dToken);
        vars.money = address(_perpetualDebt.money);
        vars.fee = _perpetualDebt.dexOracle.dex.fee;

        // Refinance debt to update nFactor
        _guild.refinance();

        // Transfer user money into Helper
        TransferHelper.safeTransferFrom(vars.money, _onBehalfOf, address(this), _moneyInTarget);

        // Allow Uniswap pool to transfer money
        TransferHelper.safeApprove(vars.money, address(uniswapRouter), _moneyInTarget);

        if (_exactMoney) {
            //EXACT money in
            vars.finalMoneyIn = _moneyInTarget;

            //swap as per request
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: vars.money,
                tokenOut: vars.zToken,
                fee: vars.fee,
                recipient: address(this),
                deadline: _deadline,
                amountIn: vars.finalMoneyIn,
                amountOutMinimum: _zTokenOutTarget,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            //swap
            vars.finalZTokenOut = uniswapRouter.exactInputSingle(params);
        } else {
            //EXACT ZTokens out
            vars.finalZTokenOut = _zTokenOutTarget;

            // Swap money for zTokens
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: vars.money,
                tokenOut: vars.zToken,
                fee: vars.fee,
                recipient: address(this),
                deadline: _deadline,
                amountOut: vars.finalZTokenOut,
                amountInMaximum: _moneyInTarget,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            // The call to `exactOutputSingle` executes the swap.
            vars.finalMoneyIn = uniswapRouter.exactOutputSingle(params);

            //transfer any money dust back to user (clear this contract)
            if (_moneyInTarget > vars.finalMoneyIn) {
                TransferHelper.safeTransfer(vars.money, _onBehalfOf, _moneyInTarget - vars.finalMoneyIn);
            }
        }

        // Calculate current user debt being repayed (in zToken terms)
        IGuild.userAccountDataStruc memory userAccountData = _guild.getUserAccountData(_onBehalfOf);

        //repay debt, if any
        if (userAccountData.zTokensToRepayDebt > 0) {
            vars.zTokensUsedToRepayDebt = (userAccountData.zTokensToRepayDebt < vars.finalZTokenOut)
                ? userAccountData.zTokensToRepayDebt
                : vars.finalZTokenOut;
            vars.debtNotionalToBurn = IAssetToken(vars.zToken).baseToNotional(vars.zTokensUsedToRepayDebt);
            _guild.repay(vars.zTokensUsedToRepayDebt, _onBehalfOf);
        }

        //transfer remaining zToken to user (clear this contract)
        //This should be equivalent to any remaining zToken in TazzHelper contract.
        vars.zTokenToTransfer = vars.finalZTokenOut - vars.zTokensUsedToRepayDebt;
        if (vars.zTokenToTransfer > 0) TransferHelper.safeTransfer(vars.zToken, _onBehalfOf, vars.zTokenToTransfer);

        // convert Notional to currency units
        uint256 moneyDecimals = IERC20Detailed(vars.money).decimals();
        uint256 debtDecimals = IERC20Detailed(vars.dToken).decimals();
        vars.debtNotionalToBurnInBaseCurrency = (debtDecimals > moneyDecimals)
            ? vars.debtNotionalToBurn.div(10**(debtDecimals - moneyDecimals))
            : vars.debtNotionalToBurn.mul(10**(moneyDecimals - debtDecimals));

        // Emit event
        emit SwapAndBurn(_onBehalfOf, vars.debtNotionalToBurnInBaseCurrency, vars.finalMoneyIn, vars.finalZTokenOut);

        return (vars.debtNotionalToBurnInBaseCurrency, vars.finalMoneyIn, vars.finalZTokenOut);
    }

    struct swapZTokenForMoneyLocalVars {
        address zToken;
        address dToken;
        address money;
        uint24 fee;
        uint256 walletZTokenAmount;
        uint256 finalZTokenIn;
        uint256 finalMoneyOut;
        uint256 zTokensToBorrow;
        uint256 zTokensToRepay;
    }

    function _swapZTokenForMoney(
        bool _exactMoney,
        address _guildAddress,
        uint256 _zTokenInTarget,
        uint256 _moneyOutTarget,
        address _onBehalfOf,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        internal
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_
        )
    {
        // Fetch perpetual debt objects from guild
        IGuild _guild = IGuild(_guildAddress);
        swapZTokenForMoneyLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.dToken = address(_perpetualDebt.dToken);
        vars.money = address(_perpetualDebt.money);
        vars.fee = _perpetualDebt.dexOracle.dex.fee;

        // Refinance debt to update nFactor
        _guild.refinance();

        // Check how many zTokens user has
        vars.walletZTokenAmount = IAssetToken(vars.zToken).balanceOf(_onBehalfOf);

        //If user needs more zTokens for swap, try and borrow the missing amount
        if (_zTokenInTarget > vars.walletZTokenAmount) {
            unchecked {
                vars.zTokensToBorrow = _zTokenInTarget - vars.walletZTokenAmount;
            }

            // Mint debt (fails if user does not have enough collateral)
            _guild.borrow(vars.zTokensToBorrow, _onBehalfOf);

            // Transfer wallet amount into TazzHelper
            if (vars.walletZTokenAmount > 0) {
                TransferHelper.safeTransferFrom(vars.zToken, _onBehalfOf, address(this), vars.walletZTokenAmount);
            }
        } else {
            // Transfer user asset into Tazz Helper
            TransferHelper.safeTransferFrom(vars.zToken, _onBehalfOf, address(this), _zTokenInTarget);
        }

        // Allow Uniswap pool to transfer zTokens
        TransferHelper.safeApprove(vars.zToken, address(uniswapRouter), _zTokenInTarget);

        if (_exactMoney) {
            // EXACT money out
            vars.finalMoneyOut = _moneyOutTarget;

            // Swap zTokens for money
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: vars.zToken,
                tokenOut: vars.money,
                fee: vars.fee,
                recipient: _onBehalfOf,
                deadline: _deadline,
                amountOut: vars.finalMoneyOut,
                amountInMaximum: _zTokenInTarget,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            // The call to `exactOutputSingle` executes the swap.
            vars.finalZTokenIn = uniswapRouter.exactOutputSingle(params);

            // Remove Uniswap pool's zToken transfer allowance
            if (vars.finalZTokenIn < _zTokenInTarget) {
                TransferHelper.safeApprove(vars.zToken, address(uniswapRouter), 0);
            }

            // If zTokens were borrowed, but not all were used, then burn excess debt
            if ((vars.zTokensToBorrow > 0) && (vars.finalZTokenIn < _zTokenInTarget)) {
                //@dev zTokens currently held in TazzHelper
                unchecked {vars.zTokensToRepay = _zTokenInTarget - vars.finalZTokenIn;} //prettier-ignore
                if (vars.zTokensToRepay > vars.zTokensToBorrow) {
                    vars.zTokensToRepay = vars.zTokensToBorrow; //don't try and repay more than was borrowed
                }
                unchecked {vars.zTokensToBorrow -= vars.zTokensToRepay;} //prettier-ignore
                _guild.repay(vars.zTokensToRepay, _onBehalfOf);
            }
        } else {
            //EXACT zTokens in
            vars.finalZTokenIn = _zTokenInTarget;

            //swap as per request
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: vars.zToken,
                tokenOut: vars.money,
                fee: vars.fee,
                recipient: _onBehalfOf,
                deadline: _deadline,
                amountIn: vars.finalZTokenIn,
                amountOutMinimum: _moneyOutTarget,
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

            //swap
            vars.finalMoneyOut = uniswapRouter.exactInputSingle(params);
        }

        // calculate Notional minted in base currency units
        uint256 moneyDecimals = IERC20Detailed(vars.money).decimals();
        uint256 debtDecimals = IERC20Detailed(vars.dToken).decimals();
        debtNotionalMintedInBaseCurrency_ = INotionalERC20(vars.zToken).baseToNotional(vars.zTokensToBorrow);
        debtNotionalMintedInBaseCurrency_ = (debtDecimals > moneyDecimals)
            ? debtNotionalMintedInBaseCurrency_.div(10**(debtDecimals - moneyDecimals))
            : debtNotionalMintedInBaseCurrency_.mul(10**(moneyDecimals - debtDecimals));

        zTokenIn_ = vars.finalZTokenIn;
        moneyOut_ = vars.finalMoneyOut;

        // Emit event
        emit MintAndSwap(_onBehalfOf, debtNotionalMintedInBaseCurrency_, zTokenIn_, moneyOut_);

        return (debtNotionalMintedInBaseCurrency_, zTokenIn_, moneyOut_);
    }

    struct quoteSwapZTokenForMoneyLocalVars {
        address zToken;
        address dToken;
        address money;
        address dexPool;
        uint24 fee;
        uint256 currentWalletZToken;
        uint256 zTokensMinted;
        uint256 amountZTokenMinted;
        uint256 amountNotionalMinted;
        uint256 amountNotionalValidation;
        uint160 sqrtPriceX96before;
        uint160 sqrtPriceX96After;
    }

    function _quoteSwapZTokenForMoney(
        bool _exactMoney,
        address _guildAddress,
        uint256 _zTokenInTarget,
        uint256 _moneyOutTarget,
        uint160 _sqrtPriceLimitX96
    )
        internal
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        // Fetch perpetual debt objects from guild
        IGuild _guild = IGuild(_guildAddress);
        quoteSwapZTokenForMoneyLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.dToken = address(_perpetualDebt.dToken);
        vars.money = address(_perpetualDebt.money);
        vars.fee = _perpetualDebt.dexOracle.dex.fee;
        vars.dexPool = _perpetualDebt.dexOracle.dex.poolAddress;

        _guild.refinance();

        (vars.sqrtPriceX96before, , , , , , ) = IUniswapV3PoolState(vars.dexPool).slot0();
        zTokenPriceBeforeSwap_ = X96Math.getPriceFromSqrtX96(vars.money, vars.zToken, vars.sqrtPriceX96before);

        //get uniswap quote (how many zTokens needed)
        if (_exactMoney) {
            (zTokenIn_, moneyOut_, vars.sqrtPriceX96After, gasEstimate_) = uniswapQuoter.quoteExactOutputSingle(
                IUniswapQuoterV3.QuoteExactOutputSingleParams({
                    tokenIn: vars.zToken,
                    tokenOut: vars.money,
                    amount: _moneyOutTarget,
                    fee: vars.fee,
                    sqrtPriceLimitX96: _sqrtPriceLimitX96
                })
            );
        } else {
            (zTokenIn_, moneyOut_, vars.sqrtPriceX96After, gasEstimate_) = uniswapQuoter.quoteExactInputSingle(
                IUniswapQuoterV3.QuoteExactInputSingleParams({
                    tokenIn: vars.zToken,
                    tokenOut: vars.money,
                    amountIn: _zTokenInTarget,
                    fee: vars.fee,
                    sqrtPriceLimitX96: _sqrtPriceLimitX96
                })
            );
        }

        zTokenPriceAfterSwap_ = X96Math.getPriceFromSqrtX96(vars.money, vars.zToken, vars.sqrtPriceX96After);

        //calculate how much debt would need to be minted for this swap
        vars.currentWalletZToken = _guild.getAsset().balanceOf(msg.sender);
        vars.amountZTokenMinted = (zTokenIn_ > vars.currentWalletZToken) ? zTokenIn_ - vars.currentWalletZToken : 0;

        // validate user can mint this amount of debt
        if (vars.amountZTokenMinted > 0) {
            //apply a time buffer (to ensure quote is valid for QUOTE_TIME_BUFFER seconds)
            vars.amountZTokenMinted = vars.amountZTokenMinted.rayMul(_quoteBufferFactor(_guildAddress));
            vars.amountNotionalMinted = _guild.getAsset().baseToNotional(vars.amountZTokenMinted);
            _guild.validateBorrow(vars.amountZTokenMinted, msg.sender);
        }

        // convert to base currency units
        uint256 moneyDecimals = IERC20Detailed(vars.money).decimals();
        uint256 debtDecimals = IERC20Detailed(vars.dToken).decimals();
        debtNotionalMintedInBaseCurrency_ = (debtDecimals > moneyDecimals)
            ? vars.amountNotionalMinted.div(10**(debtDecimals - moneyDecimals))
            : vars.amountNotionalMinted.mul(10**(moneyDecimals - debtDecimals));

        //Add cte gas estimate from non-Uniswap contract portion
        gasEstimate_ += 415000;

        return (
            debtNotionalMintedInBaseCurrency_,
            zTokenIn_,
            moneyOut_,
            zTokenPriceBeforeSwap_,
            zTokenPriceAfterSwap_,
            gasEstimate_
        );
    }

    struct quoteSwapMoneyForZTokensLocalVars {
        address zToken;
        address dToken;
        address money;
        address dexPool;
        uint24 fee;
        uint160 sqrtPriceX96before;
        uint160 sqrtPriceX96After;
        uint256 debtNotionalBurned;
        uint256 zTokenToBurn;
    }

    function _quoteSwapMoneyForZToken(
        bool _exactMoney,
        address _guildAddress,
        uint256 _moneyInTarget,
        uint256 _zTokenOutTarget,
        uint160 _sqrtPriceLimitX96
    )
        internal
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_,
            uint256 zTokenPriceBeforeSwap_,
            uint256 zTokenPriceAfterSwap_,
            uint256 gasEstimate_
        )
    {
        // Fetch perpetual debt objects from guild
        IGuild _guild = IGuild(_guildAddress);
        quoteSwapMoneyForZTokensLocalVars memory vars;

        // Get perpetual debt data
        DataTypes.PerpetualDebtData memory _perpetualDebt = _guild.getPerpetualDebt();
        vars.zToken = address(_perpetualDebt.zToken);
        vars.dToken = address(_perpetualDebt.dToken);
        vars.money = address(_perpetualDebt.money);
        vars.fee = _perpetualDebt.dexOracle.dex.fee;
        vars.dexPool = _perpetualDebt.dexOracle.dex.poolAddress;

        _guild.refinance();

        (vars.sqrtPriceX96before, , , , , , ) = IUniswapV3PoolState(vars.dexPool).slot0();
        zTokenPriceBeforeSwap_ = X96Math.getPriceFromSqrtX96(vars.money, vars.zToken, vars.sqrtPriceX96before);

        //get uniswap quote (how much money needed)
        if (_exactMoney) {
            (moneyIn_, zTokenOut_, vars.sqrtPriceX96After, gasEstimate_) = uniswapQuoter.quoteExactInputSingle(
                IUniswapQuoterV3.QuoteExactInputSingleParams({
                    tokenIn: vars.money,
                    tokenOut: vars.zToken,
                    amountIn: _moneyInTarget,
                    fee: vars.fee,
                    sqrtPriceLimitX96: _sqrtPriceLimitX96
                })
            );
        } else {
            (moneyIn_, zTokenOut_, vars.sqrtPriceX96After, gasEstimate_) = uniswapQuoter.quoteExactOutputSingle(
                IUniswapQuoterV3.QuoteExactOutputSingleParams({
                    tokenIn: vars.money,
                    tokenOut: vars.zToken,
                    amount: _zTokenOutTarget,
                    fee: vars.fee,
                    sqrtPriceLimitX96: _sqrtPriceLimitX96
                })
            );
        }

        zTokenPriceAfterSwap_ = X96Math.getPriceFromSqrtX96(vars.money, vars.zToken, vars.sqrtPriceX96After);

        //calculate how much debt can be burned after this swap
        IGuild.userAccountDataStruc memory userAccountData = _guild.getUserAccountData(msg.sender);
        vars.zTokenToBurn = (zTokenOut_ > userAccountData.zTokensToRepayDebt)
            ? userAccountData.zTokensToRepayDebt
            : zTokenOut_;
        vars.debtNotionalBurned = _guild.getAsset().baseToNotional(vars.zTokenToBurn);

        //Validate repay
        if (vars.debtNotionalBurned > 0) _guild.validateRepay(vars.zTokenToBurn, msg.sender);

        // convert to base currency units
        uint256 moneyDecimals = IERC20Detailed(vars.money).decimals();
        uint256 debtDecimals = IERC20Detailed(vars.dToken).decimals();
        debtNotionalBurnedInBaseCurrency_ = (debtDecimals > moneyDecimals)
            ? vars.debtNotionalBurned.div(10**(debtDecimals - moneyDecimals))
            : vars.debtNotionalBurned.mul(10**(moneyDecimals - debtDecimals));

        //Add cte gas estimate from non-Uniswap contract portion
        gasEstimate_ += 200000;

        return (
            debtNotionalBurnedInBaseCurrency_,
            moneyIn_,
            zTokenOut_,
            zTokenPriceBeforeSwap_,
            zTokenPriceAfterSwap_,
            gasEstimate_
        );
    }

    function _quoteDexLiquidty(address guild) internal view returns (uint256 moneyAmount, uint256 zTokenAmount) {
        //get guild DEX address
        DataTypes.PerpetualDebtData memory _perpetualDebt = IGuild(guild).getPerpetualDebt();
        address dexPoolAddress = _perpetualDebt.dexOracle.dex.poolAddress;
        bool moneyIsToken0 = _perpetualDebt.dexOracle.dex.moneyIsToken0;

        //get money
        IERC20 moneyToken = IGuild(guild).getMoney();

        //get zToken
        IAssetToken zToken = IGuild(guild).getAsset();

        // get money amount in external Dex Pool
        moneyAmount = moneyToken.balanceOf(dexPoolAddress);

        // get zToken amount in external Dex Pool
        zTokenAmount = zToken.balanceOf(dexPoolAddress);

        // Correct for LP fees
        (uint128 token0amount, uint128 token1amount) = IUniswapV3PoolState(dexPoolAddress).protocolFees();
        moneyAmount -= moneyIsToken0 ? uint256(token0amount) : uint256(token1amount);
        zTokenAmount -= moneyIsToken0 ? uint256(token1amount) : uint256(token0amount);

        return (moneyAmount, zTokenAmount);
    }

    function _quoteMaxWithdaw(
        address guild,
        address asset,
        address user
    ) internal returns (uint256 maxCollateralWithdraw) {
        IGuild _guild = IGuild(guild);

        _guild.refinance();

        //get user info
        IGuild.userAccountDataStruc memory userAccountData = _guild.getUserAccountData(user);

        //calculate how much collateral value user can withdraw
        //apply a time buffer (to ensure quote is valid for QUOTE_TIME_BUFFER seconds)
        uint256 totalCollateralNeededInBaseCurrency = (userAccountData.ltv > 0)
            ? userAccountData.totalDebtNotionalInBaseCurrency.percentDiv(userAccountData.ltv).rayMul(
                _quoteBufferFactor(guild)
            )
            : 0; //needed for underwritting purposes....
        uint256 availableCollateralWithdrawalsInBaseCurrency = (userAccountData.totalCollateralInBaseCurrency >
            totalCollateralNeededInBaseCurrency)
            ? userAccountData.totalCollateralInBaseCurrency - totalCollateralNeededInBaseCurrency
            : 0;

        //get collateral price in money units
        uint256 assetPrice = IPriceOracleGetter(IGuildAddressesProvider(_guild.ADDRESSES_PROVIDER()).getPriceOracle())
            .getAssetPrice(asset);

        //convert available collatearl withdrawal to its own decimal unit
        uint256 collateralUnits = 10**IERC20Detailed(asset).decimals();
        uint256 availableCollateralWithdrawals = availableCollateralWithdrawalsInBaseCurrency.mul(collateralUnits).div(
            assetPrice
        );

        //get how much collateral user has in guild
        maxCollateralWithdraw = _guild.getCollateralBalanceOf(user, asset);

        //return lower of both
        if (maxCollateralWithdraw > availableCollateralWithdrawals)
            maxCollateralWithdraw = availableCollateralWithdrawals;

        return maxCollateralWithdraw;
    }

    function _quoteBufferFactor(address guild) internal view returns (uint256 bufferFactor) {
        IGuild _guild = IGuild(guild);

        uint256 notionalPrice = IGuild(guild).getDebtNotionalPrice(_guild.ADDRESSES_PROVIDER().getPriceOracle());
        uint256 perpDebtBeta = IGuild(guild).getPerpetualDebt().beta;

        //Get estimated rate per second (in RAY)
        int256 logRate = DebtMath.calculateApproxRate(perpDebtBeta, notionalPrice);
        //Get estimated factor
        bufferFactor = DebtMath.calculateApproxNotionalUpdate(logRate, QUOTE_TIME_BUFFER);
    }
}

