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

import "./ISorbettiere.sol";
import "./ICurve.sol";

import "./TokensRescuer.sol";

error OnlyValidSlippage();
error OnlyParallax();
error OnlyCorrectPath();
error OnlyWhitelistedToken();
error OnlyValidOutputAmount();
error OnlyCorrectPathLength();
error OnlyCorrectArrayLength();

/**
 * @title A smart-contract that implements Curve's USDC-USDT/MIM LP
 *        Sorbettiere earning strategy.
 */
contract CurveMIM3CRVSorbettiereStrategyUpgradeable is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TokensRescuer,
    IParallaxStrategy
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct InternalDepositParams {
        uint256 usdcAmount;
        uint256 usdtAmount;
        uint256 mimAmount;
        uint256 usdcUsdtLPsAmountOutMin;
        uint256 mimUsdcUsdtLPsAmountOutMin;
    }

    struct InternalWithdrawParams {
        uint256 amount;
        uint256 actualWithdraw;
        uint256 mimAmountOutMin;
        uint256 usdcUsdtLPsAmountOutMin;
        uint256 usdcAmountOutMin;
        uint256 usdtAmountOutMin;
    }

    struct InitParams {
        address _PARALLAX;
        address _SORBETTIERE;
        address _SPELL;
        address _WETH;
        address _USDC;
        address _USDT;
        address _MIM;
        address _SUSHI_SWAP_ROUTER;
        address _USDC_USDT_POOL;
        address _MIM_USDC_USDT_LP_POOL;
        address _MIM_USD_ORACLE;
        address _SPELL_USD_ORACLE;
        uint256 _EXPIRE_TIME;
        uint256 maxSlippage;
        uint256 initialCompoundMinAmount;
    }

    address public constant STRATEGY_AUTHOR = address(0);

    address public PARALLAX;

    address public SORBETTIERE;
    address public SPELL;

    address public WETH;
    address public USDC;
    address public USDT;
    address public MIM;

    address public SUSHI_SWAP_ROUTER;

    address public USDC_USDT_POOL;
    address public MIM_USDC_USDT_LP_POOL;

    AggregatorV2V3Interface public MIM_USD_ORACLE;
    AggregatorV2V3Interface public SPELL_USD_ORACLE;

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

    /**
     * @dev Initializes the contract
     * @param initParams Contains the following variables:
     *                   PARALLAX - address of the main contract that controls
     *                              all strategies in the system.
     *                   SORBETTIERE - address of the Sorbettiere's staking
     *                                 smart-contract.
     *                   SPELL - address of SPELL token.
     *                   WETH - address of WETH token.
     *                   MIM - address of MIM token.
     *                   USDC - address of USDC token.
     *                   USDT - address of USDT token.
     *                   SUSHI_SWAP_ROUTER - address of the SushiSwap's Router
     *                                       smart-contract used in the strategy
     *                                       for exchanges.
     *                   USDC_USDT_POOL - address of Curve's USDC/USDT pool
     *                                    (2CRV, Curve.fi USDC/USDT) used.
     *                   MIM_USDC_USDT_LP_POOL - address of Curve's
     *                                           MIM/USDC-USDT LP pool
     *                                           (MIM3CRV-f, Curve.fi Factory
     *                                           USD Metapool: MIM).
     *                   MIM_USD_ORACLE - address of MIM/USD chainLink oracle.
     *                   SPELL_USD_ORACLE - SPELL/USD chainLink oracle address.
     *                   EXPIRE_TIME - number (in seconds) during which
     *                                 all exchange transactions in this
     *                                 strategy are valid. If time elapsed,
     *                                 exchange and transaction will fail.
     *                   initialCompoundMinAmount - value in reward token
     *                                              after which compound must be
     *                                              executed.
     */
    function __CurveMIM3CRVSorbettiereStrategy_init(
        InitParams memory initParams
    ) external initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __CurveMIM3CRVSorbettiereStrategy_init_unchained(initParams);
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
     * @notice Sets a value (in SPELL token) after which compound must
     *         be executed.The compound operation is performed during every
     *         deposit and withdrawal. And sometimes there may not be enough
     *         reward tokens to complete all the exchanges and liquidity.
     *         additions. As a result, deposit and withdrawal transactions
     *         may fail. To avoid such a problem, this value is provided.
     *         And if the number of rewards is even less than it, the compound
     *         does not occur. As soon as there are more of them, a compound
     *         immediately occurs in time of first deposit or withdrawal.
     *         Can only be called by the Parallax contact.
     * @param newCompoundMinAmount A value in SPELL token after which compound
     *                             must be executed.
     */
    function setCompoundMinAmount(
        uint256 newCompoundMinAmount
    ) external onlyParallax {
        compoundMinAmount = newCompoundMinAmount;
    }

    /**
     * @notice deposits Curve's MIM/USDC-USDT LPs into the vault
     *         deposits these LPs into the Sorbettiere's staking smart-contract.
     *         LP tokens that are depositing must be approved to this contract.
     *         Executes compound before depositing.
     *         Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens for deposit
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               positionId - id of the position.
     *               data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositLPs(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        if (params.amounts[0] > 0) {
            IERC20Upgradeable(MIM_USDC_USDT_LP_POOL).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            // Deposit (stake) Curve's MIM/USDC-USDT LP tokens
            // in the Sorbettiere staking pool
            _sorbettiereDeposit(params.amounts[0]);
        }

        return params.amounts[0];
    }

    /**
     *  @notice accepts USDC, USDT, and MIM tokens in equal parts.
     *       Provides USDC and USDT tokens
     *       to the Curve's USDC/USDT liquidity pool.
     *       Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *       and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *       Deposits MIM/USDC-USDT LPs into the Sorbettiere's staking
     *       smart-contract. USDC, USDT, and MIM tokens that are depositing
     *       must be approved to this contract.
     *       Executes compound before depositing.
     *       Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - must be set in USDC/USDT tokens (with 6 decimals).
     *                 MIM token will be charged the same as USDC and USDT
     *                 but with 18 decimal places
     *                 (18-6=12 additional zeros will be added).
     *                amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 2 elements:
     *                 0 - minimum amount of output USDC/USDT LP tokens
     *                 during add liquidity to Curve's USDC/USDT liquidity pool.
     *                 1 - minimum amount of output MIM/USDC-USDT LP tokens
     *                 during add liquidity to Curve's
     *                 MIM/USDC-USDT liquidity pool.
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               positionId - id of the position.
     *               data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositTokens(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 2);

        if (
            params.amounts[0] > 0 ||
            params.amounts[1] > 0 ||
            params.amounts[2] > 0
        ) {
            // Transfer equal amounts of USDC, USDT, and MIM tokens
            // from a user to this contract

            IERC20Upgradeable(USDC).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );
            IERC20Upgradeable(USDT).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[1]
            );
            IERC20Upgradeable(MIM).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[2]
            );

            // Deposit
            uint256 deposited = _deposit(
                InternalDepositParams({
                    usdcAmount: params.amounts[0],
                    usdtAmount: params.amounts[1],
                    mimAmount: params.amounts[2],
                    usdcUsdtLPsAmountOutMin: params.amountsOutMin[0],
                    mimUsdcUsdtLPsAmountOutMin: params.amountsOutMin[1]
                })
            );

            return deposited;
        }

        return 0;
    }

    /**
     * @notice accepts ETH token.
     *      Swaps third of it for USDC, third for USDT, and third for MIM tokens
     *      Provides USDC and USDT tokens to the
     *      Curve's USDC/USDT liquidity pool.
     *      Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *      and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *      Deposits MIM/USDC-USDT LPs into the Sorbettiere's
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
     *                 it must contain 5 elements:
     *                 0 - minimum amount of output USDC tokens
     *                 during swap of ETH tokens to USDC tokens on SushiSwap.
     *                 1 - minimum amount of output USDT tokens
     *                 during swap of ETH tokens to USDT tokens on SushiSwap.
     *                 2 - minimum amount of output MIM tokens
     *                 during swap of ETH tokens to MIM tokens on SushiSwap.
     *                 3 - minimum amount of output USDC/USDT LP tokens
     *                 during add liquidity to Curve's USDC/USDT liquidity pool.
     *                 4 - minimum amount of output MIM/USDC-USDT LP tokens
     *                 during add liquidity to Curve's MIM/USDC-USDT
     *                 liquidity pool.
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 3 elements:
     *                 0 - route for swap of ETH tokens to USDC tokens
     *                 (e.g.: [WETH, USDC], or [WETH, MIM, USDC]).
     *                 The first element must be WETH, the last one USDC.
     *                 1 - route for swap of ETH tokens to USDT tokens
     *                 (e.g.: [WETH, USDT], or [WETH, MIM, USDT]).
     *                 The first element must be WETH, the last one USDT.
     *                 2 - route for swap of ETH tokens to MIM tokens
     *                 (e.g.: [WETH, MIM], or [WETH, USDC, MIM]).
     *                 The first element must be WETH, the last one MIM.
     *                positionId - id of the position.
     *                data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositAndSwapNativeToken(
        DepositParams memory params
    ) external payable nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 5);
        _onlyCorrectArrayLength(params.paths.length, 3);

        if (msg.value > 0) {
            // Swap native tokens for USDC, USDT, and MIM tokens in equal parts
            uint256 third = msg.value / 3;
            uint256 receivedUsdc = _swapETHForTokens(
                USDC,
                third,
                params.amountsOutMin[0],
                params.paths[0]
            );
            uint256 receivedUsdt = _swapETHForTokens(
                USDT,
                third,
                params.amountsOutMin[1],
                params.paths[1]
            );
            uint256 receivedMim = _swapETHForTokens(
                MIM,
                msg.value - 2 * third,
                params.amountsOutMin[2],
                params.paths[2]
            );

            // Deposit
            uint256 deposited = _deposit(
                InternalDepositParams({
                    usdcAmount: receivedUsdc,
                    usdtAmount: receivedUsdt,
                    mimAmount: receivedMim,
                    usdcUsdtLPsAmountOutMin: params.amountsOutMin[3],
                    mimUsdcUsdtLPsAmountOutMin: params.amountsOutMin[4]
                })
            );

            return deposited;
        }

        return 0;
    }

    /**
     * @notice accepts any whitelisted ERC-20 token.
     *      Swaps third of it for USDC, third for USDT, and third for MIM tokens
     *      Provides USDC and USDT tokens
     *      to the Curve's USDC/USDT liquidity pool.
     *      Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *      and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *      After that deposits MIM/USDC-USDT LPs
     *      into the Sorbettiere's staking smart-contract.
     *      ERC-20 token that is depositing must be approved to this contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of erc20 tokens for swap and deposit
     *               token - address of erc20 token
     *               amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 5 elements:
     *                 0 - minimum amount of output USDC tokens
     *                 during swap of ETH tokens to USDC tokens on SushiSwap.
     *                 1 - minimum amount of output USDT tokens
     *                 during swap of ETH tokens to USDT tokens on SushiSwap.
     *                 2 - minimum amount of output MIM tokens
     *                 during swap of ETH tokens to MIM tokens on SushiSwap.
     *                 3 - minimum amount of output USDC/USDT LP tokens
     *                 during add liquidity to Curve's USDC/USDT liquidity pool.
     *                 4 - minimum amount of output MIM/USDC-USDT LP tokens
     *                 during add liquidity to Curve's MIM/USDC-USDT
     *                 liquidity pool.
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 3 elements:
     *                 0 - route for swap of ETH tokens to USDC tokens
     *                 (e.g.: [WETH, USDC], or [WETH, MIM, USDC]).
     *                 The first element must be WETH, the last one USDC.
     *                 1 - route for swap of ETH tokens to USDT tokens
     *                 (e.g.: [WETH, USDT], or [WETH, MIM, USDT]).
     *                 The first element must be WETH, the last one USDT.
     *                 2 - route for swap of ETH tokens to MIM tokens
     *                 (e.g.: [WETH, MIM], or [WETH, USDC, MIM]).
     *                 The first element must be WETH, the last one MIM.
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               positionId - id of the position.
     *               data - additional data for strategy.
     * @return amount of deposited tokens
     */
    function depositAndSwapERC20Token(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 5);
        _onlyCorrectArrayLength(params.paths.length, 3);
        _onlyCorrectArrayLength(params.data.length, 1);

        address token = address(uint160(bytes20(params.data[0])));
        _onlyWhitelistedToken(token);

        if (params.amounts[0] > 0) {
            // Transfer whitelisted ERC20 tokens from a user to this contract
            IERC20Upgradeable(token).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            // Swap ERC20 tokens for USDC, USDT, and MIM tokens in equal parts
            uint256 third = params.amounts[0] / 3;

            uint256 receivedUsdc;
            if (token == USDC) {
                receivedUsdc = third;
            } else {
                receivedUsdc = _swapTokensForTokens(
                    token,
                    USDC,
                    third,
                    params.amountsOutMin[0],
                    params.paths[0]
                );
            }

            uint256 receivedUsdt;
            if (token == USDT) {
                receivedUsdt = third;
            } else {
                receivedUsdt = _swapTokensForTokens(
                    token,
                    USDT,
                    third,
                    params.amountsOutMin[1],
                    params.paths[1]
                );
            }

            uint256 receivedMim;
            if (token == MIM) {
                receivedMim = third;
            } else {
                receivedMim = _swapTokensForTokens(
                    token,
                    MIM,
                    third,
                    params.amountsOutMin[2],
                    params.paths[2]
                );
            }

            // Deposit
            uint256 deposited = _deposit(
                InternalDepositParams({
                    usdcAmount: receivedUsdc,
                    usdtAmount: receivedUsdt,
                    mimAmount: receivedMim,
                    usdcUsdtLPsAmountOutMin: params.amountsOutMin[3],
                    mimUsdcUsdtLPsAmountOutMin: params.amountsOutMin[4]
                })
            );

            return deposited;
        }

        return 0;
    }

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Sends to the user his MIM/USDC-USDT LP tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     *  @param params parameters for deposit.
     *                amount - amount of LP tokens to withdraw
     *                receiver - adress of recipient
     *                  to whom the assets will be sent
     *                earned - lp tokens earned in proportion to the amount of
     *                  withdrawal
     *                positionId - id of the position.
     *                data - additional data for strategy.
     */
    function withdrawLPs(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        if (params.amount > 0) {
            // Withdraw (unstake) Curve's MIM/USDC-USDT LP tokens from the
            // Sorbettiere staking pool
            _sorbettiereWithdraw(params.amount);

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
            IERC20Upgradeable(MIM_USDC_USDT_LP_POOL).safeTransfer(
                params.receiver,
                actualWithdraw
            );

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Then removes the liquidity from the
     *      Curve's MIM/USDC-USDT liquidity pool.
     *      Using received USDC/USDT LPs removes the liquidity
     *      form the Curve's USDC/USDT liquidity pool.
     *      Sends to the user his USDC, USDT, and MIM tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges, withdrawals
     *                 or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 4 elements:
     *                 0 - minimum amount of output MIM tokens during
     *                 remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 1 - minimum amount of output USDC/USDT LP tokens during
     *                 remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 2 - minimum amount of output USDC tokens during removing liquidity
     *                 from Curve's USDC/USDT liquidity pool.
     *                 3 - minimum amount of output USDT tokens during
     *                 remove liquidity from Curve's USDC/USDT liquidity pool.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawTokens(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
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
            (
                uint256 usdcLiquidity,
                uint256 usdtLiquidity,
                uint256 mimLiquidity
            ) = _withdraw(
                    InternalWithdrawParams({
                        amount: params.amount,
                        actualWithdraw: actualWithdraw,
                        mimAmountOutMin: params.amountsOutMin[0],
                        usdcUsdtLPsAmountOutMin: params.amountsOutMin[1],
                        usdcAmountOutMin: params.amountsOutMin[2],
                        usdtAmountOutMin: params.amountsOutMin[3]
                    })
                );

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(USDC).safeTransfer(
                params.receiver,
                usdcLiquidity
            );
            IERC20Upgradeable(USDT).safeTransfer(
                params.receiver,
                usdtLiquidity
            );
            IERC20Upgradeable(MIM).safeTransfer(params.receiver, mimLiquidity);

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Then removes the liquidity from the
     *      Curve's MIM/USDC-USDT liquidity pool.
     *      Using received USDC/USDT LPs removes the liquidity
     *      form the Curve's USDC/USDT liquidity pool.
     *      Exchanges all received USDC, USDT, and MIM tokens for ETH token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 4 elements:
     *                 0 - minimum amount of output MIM tokens during
     *                 remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 1 - minimum amount of output USDC/USDT LP tokens during
     *                 remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 2 - minimum amount of output USDC tokens during
     *                 remove liquidity from Curve's USDC/USDT liquidity pool.
     *                 3 - minimum amount of output USDT tokens during
     *                 remove liquidity from Curve's USDC/USDT liquidity pool.
     *                 4 - minimum amount of output ETH tokens during
     *                 swap of USDC tokens to ETH tokens on SushiSwap.
     *                 5 - minimum amount of output ETH tokens during
     *                 swap of USDT tokens to ETH tokens on SushiSwap.
     *                 6 - minimum amount of output ETH tokens during
     *                 swap of MIM tokens to ETH tokens on SushiSwap.
     *               paths - paths that will be used during swaps.
     *                 For this strategy and this method
     *                 it must contain 3 elements:
     *                 0 - route for swap of USDC tokens to ETH tokens
     *                 (e.g.: [USDC, WETH], or [USDC, MIM, WETH]).
     *                 The first element must be USDC, the last one WETH.
     *                 1 - route for swap of USDT tokens to ETH tokens
     *                 (e.g.: [USDT, WETH], or [USDT, MIM, WETH]).
     *                 The first element must be USDT, the last one WETH.
     *                 2 - route for swap of MIM tokens to ETH tokens
     *                 (e.g.: [MIM, WETH], or [MIM, USDC, WETH]).
     *                 The first element must be MIM, the last one WETH.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawAndSwapForNativeToken(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 7);
        _onlyCorrectArrayLength(params.paths.length, 3);

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
            (
                uint256 usdcLiquidity,
                uint256 usdtLiquidity,
                uint256 mimLiquidity
            ) = _withdraw(
                    InternalWithdrawParams({
                        amount: params.amount,
                        actualWithdraw: actualWithdraw,
                        mimAmountOutMin: params.amountsOutMin[0],
                        usdcUsdtLPsAmountOutMin: params.amountsOutMin[1],
                        usdcAmountOutMin: params.amountsOutMin[2],
                        usdtAmountOutMin: params.amountsOutMin[3]
                    })
                );

            // Swap USDC, USDT, and MIM tokens for native tokens
            uint256 receivedETH = _swapTokensForETH(
                USDC,
                usdcLiquidity,
                params.amountsOutMin[4],
                params.paths[0]
            );

            receivedETH += _swapTokensForETH(
                USDT,
                usdtLiquidity,
                params.amountsOutMin[5],
                params.paths[1]
            );
            receivedETH += _swapTokensForETH(
                MIM,
                mimLiquidity,
                params.amountsOutMin[6],
                params.paths[2]
            );

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            AddressUpgradeable.sendValue(payable(params.receiver), receivedETH);

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws the needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract. Then removes the
     *      liquidity from the Curve's MIM/USDC-USDT liquidity pool. Using
     *      received USDC/USDT LPs removes the liquidity from the Curve's
     *      USDC/USDT liquidity pool. Exchanges all received USDC, USDT, and
     *      MIM tokens for chosen by the user whitelisted ERC-20 token. Sends
     *      to the user his token and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 7 elements:
     *                 0 - minimum amount of output MIM tokens during removing
     *                 liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 1 - minimum amount of output USDC/USDT LP tokens during
     *                 removing liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *                 2 - minimum amount of output USDC tokens during removing
     *                 liquidity from Curve's USDC/USDT liquidity pool.
     *                 3 - minimum amount of output USDT tokens during removing
     *                 liquidity from Curve's USDC/USDT liquidity pool.
     *                 4 - minimum amount of output user's ERC-20 tokens during
     *                 the swap of USDC tokens to user's ERC-20 tokens on SushiSwap.
     *                 5 - minimum amount of output user's ERC-20 tokens during
     *                 the swap of USDT tokens to user's ERC-20 tokens on SushiSwap.
     *                 6 - minimum amount of output user's ERC-20 tokens during
     *                 the swap of MIM tokens to user's ERC-20 tokens on SushiSwap.
     *               earned - lp tokens earned in proportion to the amount of
     *                 withdrawal
     *               token - address of chosen ERC20 token
     *               paths - paths that will be used during swaps.
     *                 0 - route for the swap of USDC tokens to the user's ERC-20
     *                 tokens (e.g.: [USDC, ERC-20], or [USDC, MIM, ERC-20]).
     *                 The first element must be USDC, and the last one user's
     *                 ERC-20.
     *                 1 - route for the swap of USDT tokens to the user's ERC-20
     *                 tokens (e.g.: [USDT, ERC-20], or [USDT, MIM, ERC-20]).
     *                 The first element must be USDT, and the last one user's
     *                 ERC-20.
     *                 2 - route for the swap of MIM tokens to the user's ERC-20
     *                 tokens (e.g.: [MIM, ERC-20], or [MIM, USDC, ERC-20]).
     *                 The first element must be MIM, and the last one user's
     *                 ERC-20.
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawAndSwapForERC20Token(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.amountsOutMin.length, 7);
        _onlyCorrectArrayLength(params.paths.length, 3);
        _onlyCorrectArrayLength(params.data.length, 1);

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
            (
                uint256 usdcLiquidity,
                uint256 usdtLiquidity,
                uint256 mimLiquidity
            ) = _withdraw(
                    InternalWithdrawParams({
                        amount: params.amount,
                        actualWithdraw: actualWithdraw,
                        mimAmountOutMin: params.amountsOutMin[0],
                        usdcUsdtLPsAmountOutMin: params.amountsOutMin[1],
                        usdcAmountOutMin: params.amountsOutMin[2],
                        usdtAmountOutMin: params.amountsOutMin[3]
                    })
                );

            // Swap USDC, USDT, and MIM tokens for ERC20 tokens
            uint256 receivedERC20;

            if (token == USDC) {
                receivedERC20 += usdcLiquidity;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    USDC,
                    token,
                    usdcLiquidity,
                    params.amountsOutMin[4],
                    params.paths[0]
                );
            }

            if (token == USDT) {
                receivedERC20 += usdtLiquidity;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    USDT,
                    token,
                    usdtLiquidity,
                    params.amountsOutMin[5],
                    params.paths[1]
                );
            }

            if (token == MIM) {
                receivedERC20 += mimLiquidity;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    MIM,
                    token,
                    mimLiquidity,
                    params.amountsOutMin[6],
                    params.paths[2]
                );
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

    /**
     * @notice claims all rewards
     *      from the Sorbettiere's staking smart-contract (in SPELL token).
     *      Then exchanges them for USDC, USDT, and MIM tokens in equal parts.
     *      Adds exchanged tokens to the Curve's liquidity pools
     *      and deposits received LP tokens to increase future rewards.
     *      Can only be called by the Parallax contact.
     * @param amountsOutMin an array of minimum values
     *                      that will be received during exchanges,
     *                      withdrawals or deposits of liquidity, etc.
     *                      All values can be 0 that means
     *                      that you agreed with any output value.
     *                      For this strategy and this method
     *                      it must contain 4 elements:
     *                      0 - minimum amount of output USDC tokens during
     *                      swap of MIM tokens to USDC tokens on SushiSwap.
     *                      1 - minimum amount of output USDT tokens during
     *                      swap of MIM tokens to USDT tokens on SushiSwap.
     *                      2 - minimum amount of output USDC/USDT LP tokens
     *                      during add liquidity to
     *                      Curve's USDC/USDT liquidity pool.
     *                      3 - minimum amount of output MIM/USDC-USDT LP tokens
     *                      during add liquidity to
     *                      Curve's MIM/USDC-USDT liquidity pool.
     * @return received LP tokens from MimUsdcUsdt pool
     */
    function compound(
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(amountsOutMin.length, 4);

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

    /// @inheritdoc IParallaxStrategy
    /// @notice Unsupported function in this strategy
    function transferPositionFrom(
        address from,
        address to,
        uint256 tokenId
    ) external onlyParallax {}

    /// @inheritdoc IParallaxStrategy
    /// @notice Unsupported function in this strategy
    function claim(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external onlyParallax {}

    /**
     * @notice Unchained initializer for this contract.
     * @param initParams An initial parameters.
     */
    function __CurveMIM3CRVSorbettiereStrategy_init_unchained(
        InitParams memory initParams
    ) internal onlyInitializing {
        PARALLAX = initParams._PARALLAX;
        SORBETTIERE = initParams._SORBETTIERE;
        SPELL = initParams._SPELL;
        WETH = initParams._WETH;
        MIM = initParams._MIM;
        USDC = initParams._USDC;
        USDT = initParams._USDT;
        SUSHI_SWAP_ROUTER = initParams._SUSHI_SWAP_ROUTER;
        USDC_USDT_POOL = initParams._USDC_USDT_POOL;
        MIM_USDC_USDT_LP_POOL = initParams._MIM_USDC_USDT_LP_POOL;
        MIM_USD_ORACLE = AggregatorV2V3Interface(initParams._MIM_USD_ORACLE);
        SPELL_USD_ORACLE = AggregatorV2V3Interface(
            initParams._SPELL_USD_ORACLE
        );
        EXPIRE_TIME = initParams._EXPIRE_TIME;
        maxSlippage = initParams.maxSlippage;
        compoundMinAmount = initParams.initialCompoundMinAmount;
    }

    /**
     * @notice Adds a liquidity to Curve's liquidity pools and deposits tokens
     *         (LPs) into Abracadabra's farm.
     * @param params A deposit parameters.
     * @return An amount of Curve's LP tokens after deposit.
     */
    function _deposit(
        InternalDepositParams memory params
    ) private returns (uint256) {
        // Add liquidity to the Curve's USDC/USDT and MIM/USDC-USDT liquidity
        // pools
        uint256 receivedUsdcUsdtLPs = _curveAddLiquidity(
            USDC_USDT_POOL,
            USDC,
            params.usdcAmount,
            USDT,
            params.usdtAmount,
            params.usdcUsdtLPsAmountOutMin
        );
        uint256 receivedMimUsdcUsdtLPs = _curveAddLiquidity(
            MIM_USDC_USDT_LP_POOL,
            MIM,
            params.mimAmount,
            USDC_USDT_POOL,
            receivedUsdcUsdtLPs,
            params.mimUsdcUsdtLPsAmountOutMin
        );

        // Deposit (stake) Curve's MIM/USDC-USDT LP tokens in the Sorbettiere's
        // staking pool
        _sorbettiereDeposit(receivedMimUsdcUsdtLPs);

        return receivedMimUsdcUsdtLPs;
    }

    /**
     * @notice Withdraws tokens (LPs) from Abracadabra's farm and removes a
     *         liquidity from Curve's liquidity pools.
     * @param params A withdrawal parameters.
     * @return A tuple with received USDC, USDT and MIM amounts.
     */
    function _withdraw(
        InternalWithdrawParams memory params
    ) private returns (uint256, uint256, uint256) {
        // Withdraw (unstake) Curve's MIM/USDC-USDT LP tokens rom the
        // Sorbettiere's staking pool
        _sorbettiereWithdraw(params.amount);

        // Remove liquidity from the Curve's MIM/USDC-USDT and USDC/USDT
        // liquidity pools
        uint256[2] memory mimUsdcUsdtLPsLiquidity = _curveRemoveLiquidity(
            MIM_USDC_USDT_LP_POOL,
            params.actualWithdraw,
            params.mimAmountOutMin,
            params.usdcUsdtLPsAmountOutMin
        );
        uint256[2] memory usdcUsdtLiquidity = _curveRemoveLiquidity(
            USDC_USDT_POOL,
            mimUsdcUsdtLPsLiquidity[1],
            params.usdcAmountOutMin,
            params.usdtAmountOutMin
        );

        return (
            usdcUsdtLiquidity[0],
            usdcUsdtLiquidity[1],
            mimUsdcUsdtLPsLiquidity[0]
        );
    }

    /**
     * @notice Harvests SPELL tokens from Abracadabra's farm and swaps them for
     *         MIM tokens.
     * @return receivedMim An amount of MIM tokens received after SPELL tokens
     *                     exchange.
     */
    function _harvest(bool toRevertIfFail) private returns (uint256 receivedMim) {
        // Harvest rewards from the Sorbettiere (in SPELL tokens)
        _sorbettiereDeposit(0);

        uint256 spellBalance = IERC20Upgradeable(SPELL).balanceOf(
            address(this)
        );
        (uint256 mimUsdRate, , bool mimUsdFlag) = _getPrice(MIM_USD_ORACLE);
        (uint256 spellUsdRate, , bool spellUsdFlag) = _getPrice(
            SPELL_USD_ORACLE
        );

        if (mimUsdFlag && spellUsdFlag) {
            // Swap Sorbettiere rewards (SPELL tokens) for MIM tokens
            if (spellBalance >= compoundMinAmount) {
                address[] memory path = _toDynamicArray([SPELL, WETH, MIM]);
                uint256 amountOut = _getAmountOut(spellBalance, path);
                uint256 amountOutChainlink = (spellUsdRate * spellBalance) /
                    mimUsdRate;

                bool priceIsCorrect =
                    amountOut >=
                    (amountOutChainlink * (10000 - maxSlippage)) / 10000;

                if (priceIsCorrect) {
                    receivedMim = _swapTokensForTokens(
                        SPELL,
                        MIM,
                        spellBalance,
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
     * @notice Compounds earned SPELL tokens to earn more rewards.
     * @param amountsOutMin An array with minimum receivable amounts during
     *                      swaps and liquidity addings.
     * @return An amount of newly deposited (compounded) tokens (LPs).
     */
    function _compound(
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) private returns (uint256) {
        // Harvest SPELL tokens and swap them to MIM tokens
        uint256 receivedMim = _harvest(toRevertIfFail);

        if (receivedMim != 0) {
            // Swap one third of MIM tokens for USDC and another third for USDT
            _swapThirdOfMimToUsdcAndThirdToUsdt(
                receivedMim,
                amountsOutMin[0],
                amountsOutMin[1]
            );

            // Reinvest swapped tokens (earned rewards)
            return
                _deposit(
                    InternalDepositParams({
                        usdcAmount: IERC20Upgradeable(USDC).balanceOf(
                            address(this)
                        ),
                        usdtAmount: IERC20Upgradeable(USDT).balanceOf(
                            address(this)
                        ),
                        mimAmount: IERC20Upgradeable(MIM).balanceOf(
                            address(this)
                        ),
                        usdcUsdtLPsAmountOutMin: amountsOutMin[2],
                        mimUsdcUsdtLPsAmountOutMin: amountsOutMin[3]
                    })
                );
        }

        return 0;
    }

    /**
     * @notice Deposits an amount of tokens (LPs) to Abracadabra's farm.
     * @param amount An amount of tokens (LPs) to deposit.
     */
    function _sorbettiereDeposit(uint256 amount) private {
        ICurve(MIM_USDC_USDT_LP_POOL).approve(SORBETTIERE, amount);
        ISorbettiere(SORBETTIERE).deposit(0, amount);
    }

    /**
     * @notice Withdraws an amount of tokens (LPs) from Abracadabra's farm.
     * @param amount An amount of tokens (LPs) to withdraw.
     */
    function _sorbettiereWithdraw(uint256 amount) private {
        ISorbettiere(SORBETTIERE).withdraw(0, amount);
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
     * @notice Adds a liquidity in `tokenA` and `tokenB` to a Curve's `pool`.
     * @param pool A Curve's pool address for liquidity adding.
     * @param tokenA An address of token A.
     * @param amountA An amount of token A.
     * @param tokenB An address of token B.
     * @param amountB An amount of token B.
     * @param amountOutMin A minimum receivable LP token amount after a adding
     *                     of liquidity.
     * @return An amount of LP tokens after liquidity adding.
     */
    function _curveAddLiquidity(
        address pool,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        uint256 amountOutMin
    ) private returns (uint256) {
        IERC20(tokenA).approve(pool, amountA);
        IERC20(tokenB).approve(pool, amountB);

        return ICurve(pool).add_liquidity([amountA, amountB], amountOutMin);
    }

    /**
     * @notice Removes an `amount` of liquidity from a Curve's `pool`.
     * @param pool A Curve's pool address for liquidity removing.
     * @param amount An amount of LP tokens to remove from a liquidity pool.
     * @param minAmountOutA A minimum receivable A token amount after a removing
     *                      of liquidity.
     * @param minAmountOutB A minimum receivable B token amount after a removing
     *                      of liquidity.
     * @return An array with token A and token B amounts that were removed from
     *         a Curve's liquidity pool.
     */
    function _curveRemoveLiquidity(
        address pool,
        uint256 amount,
        uint256 minAmountOutA,
        uint256 minAmountOutB
    ) private returns (uint256[2] memory) {
        ICurve(pool).approve(pool, amount);

        return
            ICurve(pool).remove_liquidity(
                amount,
                [minAmountOutA, minAmountOutB]
            );
    }

    /**
     * @notice Swaps 1/3 of MIM tokens for USDC and 1/3 for USDT on SushiSwap
     *         using hardcoded paths (through WETH).
     * @param mimTokensAmount A minimum receivable MIM amount after an exchange.
     * @param usdcAmountOutMin A minimum receivable USDC amount after an
     *                         exchange.
     * @param usdtAmountOutMin A minimum receivable USDT amount after an
     *                         exchange.
     * @return receivedUsdc An amount of output USDC tokens after an exchange.
     * @return receivedUsdt An amount of output USDT tokens after an exchange.
     * @return remainingMim An amount of remaining MIM tokens.
     */
    function _swapThirdOfMimToUsdcAndThirdToUsdt(
        uint256 mimTokensAmount,
        uint256 usdcAmountOutMin,
        uint256 usdtAmountOutMin
    )
        private
        returns (
            uint256 receivedUsdc,
            uint256 receivedUsdt,
            uint256 remainingMim
        )
    {
        uint256 third = mimTokensAmount / 3;

        receivedUsdc = _swapTokensForTokens(
            MIM,
            USDC,
            third,
            usdcAmountOutMin,
            _toDynamicArray([MIM, WETH, USDC])
        );
        receivedUsdt = _swapTokensForTokens(
            MIM,
            USDT,
            third,
            usdtAmountOutMin,
            _toDynamicArray([MIM, WETH, USDT])
        );
        remainingMim = third;
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

            IERC20Upgradeable(MIM_USDC_USDT_LP_POOL).safeTransfer(
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
     * @notice Converts an array from 3 elements to dynamyc array.
     * @param input An array from 3 elements to convert to dynamic array.
     * @return A newly created dynamic array.
     */
    function _toDynamicArray(
        address[3] memory input
    ) private pure returns (address[] memory) {
        address[] memory output = new address[](3);

        for (uint256 i = 0; i < input.length; ++i) {
            output[i] = input[i];
        }

        return output;
    }
}

