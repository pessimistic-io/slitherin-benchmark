//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeERC20Upgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";

import "./IERC20Upgradeable.sol";

import "./AggregatorV2V3Interface.sol";

import "./OwnableUpgradeable.sol";

import "./IUniswapV2Router02.sol";

import "./AddressUpgradeable.sol";

import "./IParallaxStrategy.sol";
import "./IParallax.sol";
import "./ISushiSwapMiniChefV2.sol";
import "./IWethMintable.sol";

import "./TokensRescuer.sol";

error OnlyValidSlippage();
error OnlyParallax();
error OnlyCorrectPath();
error OnlyCorrectArrayLength();
error OnlyWhitelistedToken();
error OnlyValidOutputAmount();
error OnlyCorrectPathLength();

/**
 * @title A smart-contract that implements Sushi WETH-USDC LP
 *        Sushi farm earning strategy.
 */
contract SushiFarmUsdcWethStrategyUpgradeable is
    IParallaxStrategy,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TokensRescuer
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct InitParams {
        address _PARALLAX;
        address _SUSHI_SWAP_FARM;
        uint256 _SUSHI_SWAP_PID;
        address _WETH;
        address _USDC;
        address _SUSHI;
        address _SUSHI_SWAP_ROUTER;
        address _USDC_WETH_POOL;
        address _SUSHI_USD_ORACLE;
        address _WETH_USD_ORACLE;
        uint256 _EXPIRE_TIME;
        uint256 maxSlippage;
        uint256 initialCompoundMinAmount;
    }

    struct InternalDepositParams {
        uint256 wethAmount;
        uint256 usdcAmount;
        uint256 lpsAmountOutMin;
    }

    struct InternalWithdrawParams {
        uint256 amount;
        uint256 actualWithdraw;
        uint256 wethAmountOutMin;
        uint256 usdcAmountOutMin;
    }

    address public constant STRATEGY_AUTHOR = address(0);

    address public PARALLAX;

    address public SUSHI_SWAP_FARM;
    uint256 public SUSHI_SWAP_PID;

    address public WETH;
    address public USDC;
    address public SUSHI;

    address public SUSHI_SWAP_ROUTER;
    address public USDC_WETH_POOL;

    AggregatorV2V3Interface public SUSHI_USD_ORACLE;
    AggregatorV2V3Interface public WETH_USD_ORACLE;

    uint256 public EXPIRE_TIME;

    uint256 public maxSlippage;

    uint256 public accumulatedFees;

    uint256 public compoundMinAmount;

    // The maximum withdrawal commission. On this strategy can't be more than
    // 10000 = 100%
    uint256 public constant MAX_WITHDRAW_FEE = 10000;

    // The maximum uptime of oracle data
    uint256 public constant STALE_PRICE_DELAY = 24 hours;

    modifier onlyParallax() {
        _onlyParallax();
        _;
    }

    modifier onlyCorrectPathLength(address[] memory path) {
        _onlyCorrectPathLength(path);
        _;
    }

    modifier onlyCorrectPath(
        address tokenIn,
        address tokenOut,
        address[] memory path
    ) {
        _onlyCorrectPath(tokenIn, tokenOut, path);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    fallback() external payable {}

    /// @inheritdoc IParallaxStrategy
    /// @notice Unsupported function in this strategy
    function claim(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external onlyParallax {}

    /**
     * @dev Initializes the contract
     * @param initParams Contains the following variables:
     *                   PARALLAX - address of the main contract that controls
     *                              all strategies in the system.
     *                   SUSHI_SWAP_FARM - address of the Sushi farm staking
     *                                 smart-contract.
     *                   SUSHI_SWAP_PID - id of strategy on Sushi farm
     *                   SUSHI - address of SUSHI token.
     *                   WETH - address of WETH token.
     *                   USDC - address of USDC token.
     *                   SUSHI_SWAP_ROUTER - address of the SushiSwap's Router
     *                                       smart-contract used in the strategy
     *                                       for exchanges.
     *                   USDC_WETH_POOL - address of Sushi's USDC/WETH pool
     *                   WETH_USD_ORACLE - address of WETH/USD chainLink oracle.
     *                   SUSHI_USD_ORACLE - SUSHI/USD chainLink oracle address.
     *                   EXPIRE_TIME - number (in seconds) during which
     *                                 all exchange transactions in this
     *                                 strategy are valid. If time elapsed,
     *                                 exchange and transaction will fail.
     *                   initialCompoundMinAmount - value in reward token
     *                                              after which compound must be
     *                                              executed.
     */
    function __SushiFarmStrategy_init(
        InitParams memory initParams
    ) external initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __SushiFarmStrategy_init_unchained(initParams);
    }

    /**
     * @notice Sets a new max slippage for SPELL-MIM swaps during compound.
     *         Can only be called by the Parallax contact (via Timelock).
     * @dev 10.00% is the max possible slippage.
     * @param newMaxSlippage Maximum deviation during swap from the oracle
     *                       rate. 100 = 1.00%, 500 = 5.00%
     */
    function setMaxSlippage(uint256 newMaxSlippage) external onlyParallax {
        if (newMaxSlippage > 1000) {
            revert OnlyValidSlippage();
        }

        maxSlippage = newMaxSlippage;
    }

    /**
     * @notice Sets a value (in SUSHI token) after which compound must
     *         be executed.The compound operation is performed during every
     *         deposit and withdrawal. And sometimes there may not be enough
     *         reward tokens to complete all the exchanges and liquidity.
     *         additions. As a result, deposit and withdrawal transactions
     *         may fail. To avoid such a problem, this value is provided.
     *         And if the number of rewards is even less than it, the compound
     *         does not occur. As soon as there are more of them, a compound
     *         immediately occurs in time of first deposit or withdrawal.
     *         Can only be called by the Parallax contact.
     * @param newCompoundMinAmount A value in SUSHI token after which compound
     *                             must be executed.
     */
    function setCompoundMinAmount(
        uint256 newCompoundMinAmount
    ) external onlyParallax {
        compoundMinAmount = newCompoundMinAmount;
    }

    /**
     * @notice deposits Sushi's USDC/WETH LPs into the vault
     *         deposits these LPs into the Sushi's's staking smart-contract.
     *         LP tokens that are depositing must be approved to this contract.
     *         Executes compound before depositing.
     *         Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens for deposit
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               holder - holder of position.
     *               positionId - id of the position.
     *               data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositLPs(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        if (params.amounts[0] > 0) {
            IERC20Upgradeable(USDC_WETH_POOL).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            // Deposit (stake) Sushi's WETH/USDC LP tokens
            // in the Sushi farm staking pool
            _sushiFarmDeposit(params.amounts[0]);
        }

        return params.amounts[0];
    }

    /// @inheritdoc IParallaxStrategy
    function depositTokens(
        DepositParams memory
    ) external view onlyParallax returns (uint256) {
        revert();
    }

    /**
     * @notice accepts ETH token.
     *      Swaps half of it for USDC and half for WETH tokens
     *      Provides USDC and USDT tokens to the Sushi's WETH/USDC liquidity
     *      pool.
     *      Deposits WETH/USDC LPs into the Sushi's's
     *      staking smart-contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 2 elements:
     *                 0 - minimum amount of output USDC tokens
     *                 during swap of ETH tokens to USDC tokens on SushiSwap.
     *                 1 - minimum amount of output USDC/WETH LP tokens
     *                 during add liquidity to Sushi's USDC/WETH
     *                 liquidity pool.
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of ETH tokens to USDC tokens
     *                 (e.g.: [WETH, USDC], or [WETH, MIM, USDC]).
     *                 The first element must be WETH, the last one USDC.
     *                positionId - id of the position.
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               holder - holder of position.
     *               data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositAndSwapNativeToken(
        DepositParams memory params
    ) external payable nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.paths.length, 1);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 2);

        if (msg.value > 0) {
            // Swap native tokens for USDC in equal part
            uint256 half = msg.value / 2;

            uint256 balanceWethBefore = IERC20Upgradeable(WETH).balanceOf(
                address(this)
            );
            IWethMintable(WETH).deposit{ value: half }();
            uint256 receivedWeth = IERC20Upgradeable(WETH).balanceOf(
                address(this)
            ) - balanceWethBefore;

            uint256 receivedUsdc = _swapETHForTokens(
                USDC,
                msg.value - half,
                params.amountsOutMin[0],
                params.paths[0]
            );

            // Deposit
            uint256 deposited = _deposit(
                InternalDepositParams({
                    wethAmount: receivedWeth,
                    usdcAmount: receivedUsdc,
                    lpsAmountOutMin: params.amountsOutMin[1]
                })
            );

            return deposited;
        }

        return 0;
    }

    /**
     * @notice accepts ERC20 token.
     *      Swaps half of it for USDC and half for WETH tokens
     *      Provides USDC and USDT tokens to the Sushi's WETH/USDC liquidity
     *      pool.
     *      Deposits WETH/USDC LPs into the Sushi's's
     *      staking smart-contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 3 elements:
     *                 0 - minimum amount of output WETH tokens
     *                 during swap of ERC20 tokens to WETH tokens on SushiSwap.
     *                 1 - minimum amount of output USDC tokens
     *                 during swap of ERC20 tokens to USDC tokens on SushiSwap.
     *                 2 - minimum amount of output USDC/WETH LP tokens
     *                 during add liquidity to Sushi's USDC/WETH
     *                 liquidity pool.
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 2 elements:
     *                 0 - route for swap of ERC20 tokens to WETH tokens
     *                 (e.g.: [ERC20, WETH], or [ERC20, USDC, WETH]).
     *                 The first element must be ERC20, the last one WETH.
     *                 1 - route for swap of ERC20 tokens to USDC tokens
     *                 (e.g.: [ERC20, USDC], or [ERC20, MIM, USDC]).
     *                 The first element must be ERC20, the last one USDC.
     *                positionId - id of the position.
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               holder - holder of position.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - address of the ERC20 token.
     * @return amount of deposited tokens
     */
    function depositAndSwapERC20Token(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.data.length, 1);
        _onlyCorrectArrayLength(params.paths.length, 2);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 3);

        address token = address(uint160(bytes20(params.data[0])));
        _onlyWhitelistedToken(token);

        if (params.amounts[0] > 0) {
            // Transfer whitelisted ERC20 tokens from a user to this contract
            IERC20Upgradeable(token).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            // Swap ERC20 tokens for WETH, USDC in equal parts
            uint256 half = params.amounts[0] / 2;

            uint256 receivedWeth;
            if (token == WETH) {
                receivedWeth = half;
            } else {
                receivedWeth = _swapTokensForTokens(
                    token,
                    WETH,
                    half,
                    params.amountsOutMin[0],
                    params.paths[0]
                );
            }

            uint256 receivedUsdc;
            if (token == USDC) {
                receivedUsdc = half;
            } else {
                receivedUsdc = _swapTokensForTokens(
                    token,
                    USDC,
                    half,
                    params.amountsOutMin[1],
                    params.paths[1]
                );
            }

            // Deposit
            uint256 deposited = _deposit(
                InternalDepositParams({
                    wethAmount: receivedWeth,
                    usdcAmount: receivedUsdc,
                    lpsAmountOutMin: params.amountsOutMin[2]
                })
            );

            return deposited;
        }

        return 0;
    }

    /**
     * @notice withdraws needed amount of staked Sushi's USDC/WETH LPs
     *      from the Sushi's staking smart-contract.
     *      Sends to the user his USDC/WETH LP tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     *  @param params parameters for deposit.
     *                amount - amount of LP tokens to withdraw
     *                receiver - adress of recipient
     *                  to whom the assets will be sent
     *                holder - holder of position.
     *                earned - lp tokens earned in proportion to the amount of
     *                  withdrawal
     *                positionId - id of the position.
     *                data - additional data for strategy.
     */
    function withdrawLPs(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        if (params.amount > 0) {
            // Withdraw (unstake) Sushi's WETH/USDC LP tokens from the
            // Sushi's staking pool
            _sushiFarmWithdraw(params.amount);

            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(USDC_WETH_POOL).safeTransfer(
                params.receiver,
                actualWithdraw
            );

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked Sushi's USDC/WETH LPs
     *      from the Sushi's staking smart-contract.
     *      Then removes the liquidity from the
     *      Sushi's USDC/WETH liquidity pool.
     *      Sends to the user his WETH and USDC tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges, withdrawals
     *                 or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 4 elements:
     *                 0 - minimum amount of output WETH tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *                 1 - minimum amount of output USDC tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawTokens(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 2);

        if (params.amount > 0) {
            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );
            // Withdraw
            (uint256 wethLiquidity, uint256 usdcLiquidity) = _withdraw(
                InternalWithdrawParams({
                    amount: params.amount,
                    actualWithdraw: actualWithdraw,
                    wethAmountOutMin: params.amountsOutMin[0],
                    usdcAmountOutMin: params.amountsOutMin[1]
                })
            );

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(WETH).safeTransfer(
                params.receiver,
                wethLiquidity
            );
            IERC20Upgradeable(USDC).safeTransfer(
                params.receiver,
                usdcLiquidity
            );

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked Sushi's USDC/WETH LPs
     *      from the Sushi's staking smart-contract.
     *      Then removes the liquidity from the
     *      Sushi's USDC/WETH liquidity pool.
     *      Exchanges all received WETH and USDC tokens for ETH token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 4 elements:
     *                 0 - minimum amount of output WETH tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *                 1 - minimum amount of output USDC tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *                 2 - minimum amount of output WETH tokens during
     *                 swap of USDC tokens to WETH tokens on SushiSwap.
     *                 3 - minimum amount of output sum of WETH tokens
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of USDC tokens to WETH
     *                 (e.g.: [USDC, WETH], or [USDC, MIM, WETH]).
     *                 The first element must be USDC, the last one WETH.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawAndSwapForNativeToken(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.paths.length, 1);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 4);

        if (params.amount > 0) {
            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );
            // Withdraw
            (uint256 wethLiquidity, uint256 usdcLiquidity) = _withdraw(
                InternalWithdrawParams({
                    amount: params.amount,
                    actualWithdraw: actualWithdraw,
                    wethAmountOutMin: params.amountsOutMin[0],
                    usdcAmountOutMin: params.amountsOutMin[1]
                })
            );

            // Swap USDC, USDT, and MIM tokens for native tokens
            IWethMintable(WETH).withdraw(wethLiquidity);

            uint256 receivedETH = _swapTokensForETH(
                USDC,
                usdcLiquidity,
                params.amountsOutMin[2],
                params.paths[0]
            ) + wethLiquidity;

            if (receivedETH < params.amountsOutMin[3]) {
                revert OnlyValidOutputAmount();
            }

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            AddressUpgradeable.sendValue(payable(params.receiver), receivedETH);

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked Sushi's USDC/WETH LPs
     *      from the Sushi's staking smart-contract.
     *      Then removes the liquidity from the
     *      Sushi's USDC/WETH liquidity pool.
     *      Exchanges all received WETH and USDC tokens for ETH token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 5 elements:
     *                 0 - minimum amount of output WETH tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *                 1 - minimum amount of output USDC tokens during
     *                 remove liquidity from Sushi's USDC/WETH liquidity pool.
     *                 2 - minimum amount of output ERC20 tokens during
     *                 swap of WETH tokens to ERC20 tokens on SushiSwap.
     *                 3 - minimum amount of output ERC20 tokens during
     *                 swap of USDC tokens to ERC20 tokens on SushiSwap.
     *                 4 - minimum amount of output sum of ERC20 tokens
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of WETH tokens to ERC20 tokens
     *                 (e.g.: [USDC, ERC20], or [USDC, MIM, ERC20]).
     *                 The first element must be WETH, the last one ERC20.
     *                 1 - route for swap of USDC tokens to ERC20 tokens.
     *                 (e.g.: [USDC, ERC20], or [USDC, MIM, ERC20]).
     *                 The first element must be USDC, the last one ERC20.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - address of the ERC20 token.
     */
    function withdrawAndSwapForERC20Token(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.data.length, 1);
        _onlyCorrectArrayLength(params.paths.length, 2);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 5);

        address token = address(uint160(bytes20(params.data[0])));
        _onlyWhitelistedToken(token);

        if (params.amount > 0) {
            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );
            // Withdraw
            (uint256 wethLiquidity, uint256 usdcLiquidity) = _withdraw(
                InternalWithdrawParams({
                    amount: params.amount,
                    actualWithdraw: actualWithdraw,
                    wethAmountOutMin: params.amountsOutMin[0],
                    usdcAmountOutMin: params.amountsOutMin[1]
                })
            );

            // Swap WETH and USDC tokens for ERC20 tokens
            uint256 receivedERC20;

            if (token == WETH) {
                receivedERC20 += wethLiquidity;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    WETH,
                    token,
                    wethLiquidity,
                    params.amountsOutMin[2],
                    params.paths[0]
                );
            }

            if (token == USDC) {
                receivedERC20 += usdcLiquidity;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    USDC,
                    token,
                    usdcLiquidity,
                    params.amountsOutMin[3],
                    params.paths[1]
                );
            }

            if (receivedERC20 < params.amountsOutMin[4]) {
                revert OnlyValidOutputAmount();
            }

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(token).safeTransfer(
                params.receiver,
                receivedERC20
            );

            _takeFee(withdrawalFee);
        }
    }

    /// @inheritdoc IParallaxStrategy
    function compound(
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(amountsOutMin.length, 3);

        return _compound(amountsOutMin, toRevertIfFail);
    }

    /// @inheritdoc ITokensRescuer
    function rescueNativeToken(
        uint256 amount,
        address receiver
    ) external onlyParallax {
        _rescueNativeToken(amount, receiver);
    }

    /// @inheritdoc ITokensRescuer
    function rescueERC20Token(
        address token,
        uint256 amount,
        address receiver
    ) external onlyParallax {
        _rescueERC20Token(token, amount, receiver);
    }

    /// @inheritdoc IParallaxStrategy
    function getMaxFee() external pure returns (uint256) {
        return MAX_WITHDRAW_FEE;
    }

    /**
     * @notice Unchained initializer for this contract.
     * @param initParams An initial parameters.
     */
    function __SushiFarmStrategy_init_unchained(
        InitParams memory initParams
    ) internal onlyInitializing {
        PARALLAX = initParams._PARALLAX;
        WETH = initParams._WETH;
        USDC = initParams._USDC;
        SUSHI = initParams._SUSHI;
        SUSHI_SWAP_PID = initParams._SUSHI_SWAP_PID;
        SUSHI_SWAP_FARM = initParams._SUSHI_SWAP_FARM;
        SUSHI_SWAP_ROUTER = initParams._SUSHI_SWAP_ROUTER;
        USDC_WETH_POOL = initParams._USDC_WETH_POOL;
        SUSHI_USD_ORACLE = AggregatorV2V3Interface(
            initParams._SUSHI_USD_ORACLE
        );
        WETH_USD_ORACLE = AggregatorV2V3Interface(initParams._WETH_USD_ORACLE);
        EXPIRE_TIME = initParams._EXPIRE_TIME;
        maxSlippage = initParams.maxSlippage;
        compoundMinAmount = initParams.initialCompoundMinAmount;
    }

    /**
     * @notice Adds a liquidity to Sushi's liquidity pools and deposits tokens
     *         (LPs) into Sushi's farm.
     * @param params A deposit parameters.
     * @return An amount of Sushi's LP tokens after deposit.
     */
    function _deposit(
        InternalDepositParams memory params
    ) private returns (uint256) {
        // Add liquidity to the Sushi's WETH/USDC pool

        uint256 receivedWethUsdcLPs = _sushiAddLiquidity(
            SUSHI_SWAP_ROUTER,
            WETH,
            params.wethAmount,
            USDC,
            params.usdcAmount,
            params.lpsAmountOutMin
        );

        // Deposit (stake) Sushi's WETH/USDC LP tokens in the Sushi's farm
        // staking pool
        _sushiFarmDeposit(receivedWethUsdcLPs);

        return receivedWethUsdcLPs;
    }

    /**
     * @notice Withdraws tokens (LPs) from Sushi's farm and removes a
     *         liquidity from Sushi's liquidity pools.
     * @param params A withdrawal parameters.
     * @return A tuple with received WETH and USDC amounts.
     */
    function _withdraw(
        InternalWithdrawParams memory params
    ) private returns (uint256, uint256) {
        // Withdraw (unstake) Sushi's WETH/USDC LP tokens from the
        // Sushi's staking pool
        _sushiFarmWithdraw(params.amount);

        // Remove liquidity from the Sushi's WETH/USDC liquidity pool
        uint256[2] memory wethUsdcLiquidity = _sushiRemoveLiquidity(
            SUSHI_SWAP_ROUTER,
            params.actualWithdraw,
            params.wethAmountOutMin,
            params.usdcAmountOutMin
        );

        return (wethUsdcLiquidity[0], wethUsdcLiquidity[1]);
    }

    /**
     * @notice Harvests SUSHI tokens from Sushi's farm and swaps them for
     *         SUSHI tokens.
     * @return receivedWeth An amount of WETH tokens received after SUSHI tokens
     *                     exchange.
     */
    function _harvest(
        bool toRevertIfFail
    ) private returns (uint256 receivedWeth) {
        //Harvest rewards from the Sushi's (in SUSHI tokens)
        ISushiSwapMiniChefV2(SUSHI_SWAP_FARM).harvest(
            SUSHI_SWAP_PID,
            address(this)
        );

        uint256 sushiBalance = IERC20Upgradeable(SUSHI).balanceOf(
            address(this)
        );

        (uint256 wethUsdRate, , bool wethUsdFlag) = _getPrice(WETH_USD_ORACLE);
        (uint256 sushiUsdRate, , bool sushiUsdFlag) = _getPrice(
            SUSHI_USD_ORACLE
        );

        if (wethUsdFlag && sushiUsdFlag) {
            // Swap Sushi farm rewards (SUSHI tokens) for WETH tokens
            if (sushiBalance >= compoundMinAmount) {
                address[] memory path = _toDynamicArray([SUSHI, WETH]);
                uint256 amountOut = _getAmountOut(sushiBalance, path);
                uint256 amountOutChainlink = (sushiUsdRate * sushiBalance) /
                    wethUsdRate;

                bool priceIsCorrect = amountOut >=
                    (amountOutChainlink * (10000 - maxSlippage)) / 10000;

                if (priceIsCorrect) {
                    receivedWeth = _swapTokensForTokens(
                        SUSHI,
                        WETH,
                        sushiBalance,
                        amountOut,
                        path
                    );
                } else if (toRevertIfFail) {
                    revert OnlyValidOutputAmount();
                }
            }
        }
    }

    /**
     * @notice Compounds earned SUSHI tokens to earn more rewards.
     * @param amountsOutMin An array with minimum receivable amounts during
     *                      swaps and liquidity addings.
     * @return An amount of newly deposited (compounded) tokens (LPs).
     */
    function _compound(
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) private returns (uint256) {
        // Harvest SUSHI tokens and swap them to WETH tokens
        uint256 receivedWeth = _harvest(toRevertIfFail);

        if (receivedWeth > 0) {
            uint256 balanceUsdc = IERC20Upgradeable(USDC).balanceOf(
                address(this)
            );
            if (balanceUsdc != 0) {
                _swapTokensForTokens(
                    USDC,
                    WETH,
                    balanceUsdc,
                    amountsOutMin[0],
                    _toDynamicArray([USDC, WETH])
                );
            }

            uint256 halfBalanceWeth = IERC20Upgradeable(WETH).balanceOf(
                address(this)
            ) / 2;

            // Swap half of WETH tokens for USDC
            uint256 receivedUsdc = _swapTokensForTokens(
                WETH,
                USDC,
                halfBalanceWeth,
                amountsOutMin[1],
                _toDynamicArray([WETH, USDC])
            );

            // Reinvest swapped tokens (earned rewards)
            return
                _deposit(
                    InternalDepositParams({
                        wethAmount: halfBalanceWeth,
                        usdcAmount: receivedUsdc,
                        lpsAmountOutMin: amountsOutMin[2]
                    })
                );
        }

        return 0;
    }

    /**
     * @notice Deposits an amount of tokens (LPs) to Sushi's farm.
     * @param amount An amount of tokens (LPs) to deposit.
     */
    function _sushiFarmDeposit(uint256 amount) private {
        IERC20Upgradeable(USDC_WETH_POOL).approve(SUSHI_SWAP_FARM, amount);

        ISushiSwapMiniChefV2(SUSHI_SWAP_FARM).deposit(
            SUSHI_SWAP_PID,
            amount,
            address(this)
        );
    }

    /**
     * @notice Withdraws an amount of tokens (LPs) from Sushi's farm.
     * @param amount An amount of tokens (LPs) to withdraw.
     */
    function _sushiFarmWithdraw(uint256 amount) private {
        ISushiSwapMiniChefV2(SUSHI_SWAP_FARM).withdraw(
            SUSHI_SWAP_PID,
            amount,
            address(this)
        );
    }

    /**
     * @notice Adds a liquidity in `tokenA` and `tokenB` to a Sushi's `pool`.
     * @param pool A Sushi's pool address for liquidity adding.
     * @param tokenA An address of token A.
     * @param amountA An amount of token A.
     * @param tokenB An address of token B.
     * @param amountB An amount of token B.
     * @return An amount of LP tokens after liquidity adding.
     */
    function _sushiAddLiquidity(
        address pool,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        uint256 amountOutMin
    ) private returns (uint256) {
        IERC20Upgradeable(tokenA).approve(pool, amountA);
        IERC20Upgradeable(tokenB).approve(pool, amountB);

        (, , uint256 liquidity) = IUniswapV2Router02(pool).addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            address(this),
            _getDeadline()
        );

        require(
            liquidity >= amountOutMin,
            "SushiFarmStrategy: insufficient output lp amount"
        );

        return liquidity;
    }

    /**
     * @notice Removes an `amount` of liquidity from a Sushi's `pool`.
     * @param pool A Sushi's pool address for liquidity removing.
     * @param amount An amount of LP tokens to remove from a liquidity pool.
     * @param minAmountOutA A minimum receivable A token amount after a removing
     *                      of liquidity.
     * @param minAmountOutB A minimum receivable B token amount after a removing
     *                      of liquidity.
     * @return An array with token A and token B amounts that were removed from
     *         a Sushi's liquidity pool.
     */
    function _sushiRemoveLiquidity(
        address pool,
        uint256 amount,
        uint256 minAmountOutA,
        uint256 minAmountOutB
    ) private returns (uint256[2] memory) {
        IERC20Upgradeable(USDC_WETH_POOL).approve(pool, amount);

        (uint256 amountA, uint256 amountB) = IUniswapV2Router02(pool)
            .removeLiquidity(
                WETH,
                USDC,
                amount,
                minAmountOutA,
                minAmountOutB,
                address(this),
                _getDeadline()
            );

        return [amountA, amountB];
    }

    /**
     * @notice Returns a price of a token in a specified oracle.
     * @param oracle An address of an oracle which will return a price of asset.
     * @return A tuple with a price of token, token decimals and a flag that
     *         indicates if data is actual (fresh) or not.
     */
    function _getPrice(
        AggregatorV2V3Interface oracle
    ) private view returns (uint256, uint8, bool) {
        (
            uint80 roundID,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();
        bool dataIsActual = answeredInRound >= roundID &&
            answer > 0 &&
            block.timestamp <= updatedAt + STALE_PRICE_DELAY;
        uint8 decimals = oracle.decimals();

        return (uint256(answer), decimals, dataIsActual);
    }

    /**
     * @notice Swaps ETH for `tokenOut` on SushiSwap using provided `path`.
     * @param tokenOut An address of output token.
     * @param amountIn An amount of ETH tokens to exchange.
     * @param amountOutMin A minimum receivable amount after an exchange.
     * @param path A path that will be used for an exchange.
     * @return An amount of output tokens after an exchange.
     */
    function _swapETHForTokens(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    )
        private
        onlyCorrectPathLength(path)
        onlyCorrectPath(WETH, tokenOut, path)
        returns (uint256)
    {
        uint256[] memory amounts = IUniswapV2Router02(SUSHI_SWAP_ROUTER)
            .swapExactETHForTokens{ value: amountIn }(
            amountOutMin,
            path,
            address(this),
            _getDeadline()
        );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Swaps `tokenIn` for ETH on SushiSwap using provided `path`.
     * @param tokenIn An address of input token.
     * @param amountIn An amount of tokens to exchange.
     * @param amountOutMin A minimum receivable amount after an exchange.
     * @param path A path that will be used for an exchange.
     * @return An amount of output ETH tokens after an exchange.
     */
    function _swapTokensForETH(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    )
        private
        onlyCorrectPathLength(path)
        onlyCorrectPath(tokenIn, WETH, path)
        returns (uint256)
    {
        IERC20Upgradeable(tokenIn).safeIncreaseAllowance(
            SUSHI_SWAP_ROUTER,
            amountIn
        );

        uint256[] memory amounts = IUniswapV2Router02(SUSHI_SWAP_ROUTER)
            .swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                address(this),
                _getDeadline()
            );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Swaps `tokenIn` for `tokenOut` on SushiSwap using provided `path`.
     * @param tokenIn An address of input token.
     * @param tokenOut An address of output token.
     * @param amountIn An amount of tokens to exchange.
     * @param amountOutMin A minimum receivable amount after an exchange.
     * @param path A path that will be used for an exchange.
     * @return An amount of output tokens after an exchange.
     */
    function _swapTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    )
        private
        onlyCorrectPathLength(path)
        onlyCorrectPath(tokenIn, tokenOut, path)
        returns (uint256)
    {
        IERC20Upgradeable(tokenIn).safeIncreaseAllowance(
            SUSHI_SWAP_ROUTER,
            amountIn
        );

        uint256[] memory amounts = IUniswapV2Router02(SUSHI_SWAP_ROUTER)
            .swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                _getDeadline()
            );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice A function that takes a specified fee.
     * @dev This is a private function to deduct fees.
     * @param withdrawalFee The amount of the fee to be taken
     */
    function _takeFee(uint256 withdrawalFee) private {
        if (withdrawalFee > 0) {
            accumulatedFees += withdrawalFee;

            IERC20Upgradeable(USDC_WETH_POOL).safeTransfer(
                IParallax(PARALLAX).feesReceiver(),
                withdrawalFee
            );
        }
    }

    /**
     * @notice Returns an amount of output tokens after the exchange of
     *         `amountIn` on SushiSwap using provided `path`.
     * @param amountIn An amount of tokens to exchange.
     * @param path A path that will be used for an exchange.
     * @return An amount of output tokens after an exchange of `amountIn` on
     *         SushiSwap using provided `path`.
     */
    function _getAmountOut(
        uint256 amountIn,
        address[] memory path
    ) private view onlyCorrectPathLength(path) returns (uint256) {
        uint256[] memory amounts = IUniswapV2Router02(SUSHI_SWAP_ROUTER)
            .getAmountsOut(amountIn, path);

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Calculates an actual withdraw and withdrawal fee amounts.
     *         Withdrawal fee is charged only from earned tokens (LPs).
     * @param withdrawalAmount An amount of tokens (LPs) to withdraw.
     * @param earnedAmount An amount of earned tokens (LPs) in withdrawal amount.
     * @return actualWithdraw An amount of tokens (LPs) that will be withdrawn
     *                        actually.
     * @return withdrawalFee A fee that will be charged from an earned tokens
     *                       (LPs) amount.
     */
    function _calculateActualWithdrawAndWithdrawalFee(
        uint256 withdrawalAmount,
        uint256 earnedAmount
    ) private view returns (uint256 actualWithdraw, uint256 withdrawalFee) {
        uint256 actualEarned = (earnedAmount *
            (10000 - IParallax(PARALLAX).getFee(address(this)))) / 10000;

        withdrawalFee = earnedAmount - actualEarned;
        actualWithdraw = withdrawalAmount - withdrawalFee;
    }

    /**
     * @notice Returns a deadline timestamp for SushiSwap's exchanges.
     * @return A deadline timestamp for SushiSwap's exchanges
     */
    function _getDeadline() private view returns (uint256) {
        return block.timestamp + EXPIRE_TIME;
    }

    /**
     * @notice Checks if provided token address is whitelisted. Fails otherwise.
     * @param token A token address to check.
     */
    function _onlyWhitelistedToken(address token) private view {
        if (!IParallax(PARALLAX).tokensWhitelist(address(this), token)) {
            revert OnlyWhitelistedToken();
        }
    }

    /**
     * @notice Checks if `msg.sender` is equal to the Parallax contract address.
     *         Fails otherwise.
     */
    function _onlyParallax() private view {
        if (_msgSender() != PARALLAX) {
            revert OnlyParallax();
        }
    }

    /**
     * @notice Checks if path length is greater or equal to 2. Fails otherwise.
     * @param path A path which length to check.
     */
    function _onlyCorrectPathLength(address[] memory path) private pure {
        if (path.length < 2) {
            revert OnlyCorrectPathLength();
        }
    }

    /**
     * @notice Checks if provided path is proper. Fails otherwise.
     * @dev Proper means that the first element of the `path` is equal to the
     *      `tokenIn` and the last element of the `path` is equal to `tokenOut`.
     * @param tokenIn An address of input token.
     * @param tokenOut An address of output token.
     * @param path A path to check.
     */
    function _onlyCorrectPath(
        address tokenIn,
        address tokenOut,
        address[] memory path
    ) private pure {
        if (tokenIn != path[0] || tokenOut != path[path.length - 1]) {
            revert OnlyCorrectPath();
        }
    }

    /**
     * @notice Checks array length.
     * @param actualLength An actual length of array.
     * @param expectedlength An expected length of array.
     */
    function _onlyCorrectArrayLength(
        uint256 actualLength,
        uint256 expectedlength
    ) private pure {
        if (actualLength != expectedlength) {
            revert OnlyCorrectArrayLength();
        }
    }

    /**
     * @notice Converts an array from 2 elements to dynamyc array.
     * @param input An array from 2 elements to convert to dynamic array.
     * @return A newly created dynamic array.
     */
    function _toDynamicArray(
        address[2] memory input
    ) private pure returns (address[] memory) {
        address[] memory output = new address[](2);

        for (uint256 i = 0; i < input.length; ++i) {
            output[i] = input[i];
        }

        return output;
    }
}

