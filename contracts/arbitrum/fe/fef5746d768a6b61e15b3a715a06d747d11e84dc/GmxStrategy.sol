//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeERC20Upgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";

import "./IERC20Upgradeable.sol";

import "./AggregatorV2V3Interface.sol";

import "./OwnableUpgradeable.sol";

import "./ISwapRouter.sol";
import "./IQuoter.sol";

import "./AddressUpgradeable.sol";

import "./IParallaxStrategy.sol";
import "./IParallax.sol";

import "./IGMXRouter.sol";
import "./IGMXTracker.sol";

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
 * @title A smart-contract that implements GMX farm earning strategy.
 */
contract GmxStrategyUpgradeable is
    IParallaxStrategy,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TokensRescuer
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct InitParams {
        address _PARALLAX;
        address _WETH;
        address _GMX;
        address _GMX_TRACKER;
        address _GMX_REWARD_TRACKER;
        address _GMX_ROUTER;
        address _QUOTER;
        address _UNISWAP_V3_ROUTER;
        address _GMX_USD_ORACLE;
        address _WETH_USD_ORACLE;
        uint256 _EXPIRE_TIME;
        uint256 maxSlippage;
        uint256 initialCompoundMinAmount;
    }

    uint8 public constant ADDRESS_SIZE = 20;

    address public constant STRATEGY_AUTHOR = address(0);

    address public PARALLAX;

    address public GMX_ROUTER;
    address public GMX_TRACKER;
    address public GMX_REWARD_TRACKER;

    address public QUOTER;
    address public UNISWAP_V3_ROUTER;

    address public WETH;
    address public GMX;

    AggregatorV2V3Interface public GMX_USD_ORACLE;
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

    modifier onlyCorrectPathLength(bytes memory path) {
        _onlyCorrectPathLength(path);
        _;
    }

    modifier onlyCorrectPath(
        address tokenIn,
        address tokenOut,
        bytes memory path
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
     *                   WETH - address of WETH token.
     *                   GMX - address of GMX token.
     *                   GMX_TRACKER - GMX tracker.
     *                   GMX_REWARD_TRACKER - address of GMX reward tracker.
     *                   GMX_ROUTER - address of the GMX farm staking
     *                                 smart-contract.
     *                   QUOTER - address of uniswap quoter for calculating
     *                           amountOut
     *                   UNISWAP_V3_ROUTER - address of the uniswap v3 router.
     *                   GMX_USD_ORACLE - GMX/USD chainLink oracle address.
     *                   WETH_USD_ORACLE - address of WETH/USD chainLink oracle.
     *                   EXPIRE_TIME - number (in seconds) during which
     *                                 all exchange transactions in this
     *                                 strategy are valid. If time elapsed,
     *                                 exchange and transaction will fail.
     *                   initialCompoundMinAmount - value in reward token
     *                                              after which compound must be
     *                                              executed.
     */
    function __GmxStrategy_init(
        InitParams memory initParams
    ) external initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __gmxStrategy_init_unchained(initParams);
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
     * @notice Sets a value (in GMX token) after which compound must
     *         be executed.The compound operation is performed during every
     *         deposit and withdrawal. And sometimes there may not be enough
     *         reward tokens to complete all the exchanges and liquidity.
     *         additions. As a result, deposit and withdrawal transactions
     *         may fail. To avoid such a problem, this value is provided.
     *         And if the number of rewards is even less than it, the compound
     *         does not occur. As soon as there are more of them, a compound
     *         immediately occurs in time of first deposit or withdrawal.
     *         Can only be called by the Parallax contact.
     * @param newCompoundMinAmount A value in GMX token after which compound
     *                             must be executed.
     */
    function setCompoundMinAmount(
        uint256 newCompoundMinAmount
    ) external onlyParallax {
        compoundMinAmount = newCompoundMinAmount;
    }

    /**
     * @notice deposits GMX tokens into the GMX staking.
     *         GMX tokens that are depositing must be approved to this contract.
     *         Executes compound before depositing.
     *         Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens for deposit
     *                holder - holder of position.
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
            IERC20Upgradeable(GMX).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            // Deposit (stake) GMX tokens in the GMX farm staking pool
            _deposit(params.amounts[0]);
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
     * @notice accepts ETH token. Swaps it for GMX tokens
     *      Deposits GMX into the GMX staking smart-contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - minimum amount of output GMX tokens
     *                  during swap of ETH tokens to GMX tokens on Uniswap v3.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of ETH tokens to GMX tokens
     *                 (e.g.: [WETH, GMX], or [WETH, USDC, GMX]).
     *                 The first element must be WETH, the last one GMX.
     *                holder - holder of position.
     *                user - address of the user
     *                 to whose account the deposit will be made
     *                positionId - id of the position.
     * @return amount of deposited tokens
     */
    function depositAndSwapNativeToken(
        DepositParams memory params
    ) external payable nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.data.length, 1);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 1);

        if (msg.value > 0) {
            IWethMintable(WETH).deposit{ value: msg.value }();

            uint256 receivedGmx = _swapTokensForTokens(
                WETH,
                GMX,
                msg.value,
                params.amountsOutMin[0],
                params.data[0]
            );

            // Deposit
            _deposit(receivedGmx);

            return receivedGmx;
        }

        return 0;
    }

    /**
     * @notice accepts ERC20 token. Swaps it for GMX tokens
     *      Deposits GMX tokens into the GMX staking smart-contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of erc20 tokens for swap and deposit
     *               amountsOutMin -  an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 5 elements:
     *                 0 - minimum amount of output USDC tokens
     *                 during swap of ERC20 tokens to USDC tokens on Uniswap v3.
     *               user - address of the user
     *                 to whose account the deposit will be made
     *               holder - holder of position.
     *               positionId - id of the position.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - address of the ERC20 token.
     *                 1 - route for swap of ERC20 tokens to GMX tokens
     *                 (e.g.: [TOKEN, GMX], or [TOKEN, WETH, GMX]).
     * @return amount of deposited tokens
     */
    function depositAndSwapERC20Token(
        DepositParams memory params
    ) external nonReentrant onlyParallax returns (uint256) {
        _onlyCorrectArrayLength(params.data.length, 2);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 1);

        address token = address(uint160(bytes20(params.data[0])));

        _onlyWhitelistedToken(token);

        if (params.amounts[0] > 0) {
            // Transfer whitelisted ERC20 tokens from a user to this contract
            IERC20Upgradeable(token).safeTransferFrom(
                params.user,
                address(this),
                params.amounts[0]
            );

            uint256 receivedGmx;
            if (token == GMX) {
                receivedGmx = params.amounts[0];
            } else {
                receivedGmx = _swapTokensForTokens(
                    token,
                    GMX,
                    params.amounts[0],
                    params.amountsOutMin[0],
                    params.data[1]
                );
            }

            //Deposit
            _deposit(receivedGmx);

            return receivedGmx;
        }

        return 0;
    }

    /**
     * @notice withdraws needed amount of staked GMX tokens
     *      from the GMX staking smart-contract.
     *      Sends to the user his GMX tokens
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
            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );

            _withdraw(params.amount);

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(GMX).safeTransfer(
                params.receiver,
                actualWithdraw
            );

            if (withdrawalFee > 0) {
                IERC20Upgradeable(GMX).safeTransfer(
                    IParallax(PARALLAX).feesReceiver(),
                    withdrawalFee
                );
            }
        }
    }

    /**
     * @notice withdraws needed amount of staked GMX tokens
     *      from the GMX staking smart-contract.
     *      Sends to the user his GMX tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               earned - GMX tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     */
    function withdrawTokens(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        if (params.amount > 0) {
            // Calculate withdrawal fee and actual witdraw
            (
                uint256 actualWithdraw,
                uint256 withdrawalFee
            ) = _calculateActualWithdrawAndWithdrawalFee(
                    params.amount,
                    params.earned
                );

            _withdraw(params.amount);

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            IERC20Upgradeable(GMX).safeTransfer(
                params.receiver,
                actualWithdraw
            );

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked GMX tokens
     *      from the GMX staking smart-contract.
     *      Exchanges all received GMX tokens for ETH token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of GMX tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - minimum amount of output ETH tokens during
     *                 swap of GMX tokens to ETH tokens on Uniswap v3.
     *               earned - GMX tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of GMX tokens to ETH tokens
     *                 (e.g.: [GMX, WETH], or [GMX, USDC, WETH]).
     */
    function withdrawAndSwapForNativeToken(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.data.length, 1);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 1);

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
            _withdraw(params.amount);

            uint256 receivedEth = _swapTokensForTokens(
                GMX,
                WETH,
                actualWithdraw,
                params.amountsOutMin[0],
                params.data[0]
            );

            IWethMintable(WETH).withdraw(receivedEth);

            // Send tokens to the receiver and withdrawal fee to the fees
            // receiver
            AddressUpgradeable.sendValue(payable(params.receiver), receivedEth);

            _takeFee(withdrawalFee);
        }
    }

    /**
     * @notice withdraws needed amount of staked GMX tokens
     *      from the GMX staking smart-contract.
     *      Exchanges all received GMX tokens for ERC20 token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of GMX tokens to withdraw
     *               receiver - adress of recipient
     *                 to whom the assets will be sent
     *               holder - holder of position.
     *               amountsOutMin - an array of minimum values
     *                 that will be received during exchanges,
     *                 withdrawals or deposits of liquidity, etc.
     *                 All values can be 0 that means
     *                 that you agreed with any output value.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - minimum amount of output ERC20 tokens tokens during
     *                 swap of GMX tokens to ERC20 tokens on Uniswap v3.
     *               earned - GMX tokens earned in proportion to the amount of
     *                 withdrawal
     *               positionId - id of the position.
     *               data - additional data for strategy.
     *                 For this strategy and this method
     *                 it must contain 1 elements:
     *                 0 - route for swap of GMX tokens to ERC20 tokens
     *                 (e.g.: [GMX, ERC20], or [GMX, USDC, ERC20]).
     */
    function withdrawAndSwapForERC20Token(
        WithdrawParams memory params
    ) external nonReentrant onlyParallax {
        _onlyCorrectArrayLength(params.data.length, 2);
        _onlyCorrectArrayLength(params.amountsOutMin.length, 1);

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
            _withdraw(params.amount);

            // Swap GMX tokens for ERC20 tokens
            uint256 receivedERC20;

            if (token == GMX) {
                receivedERC20 += actualWithdraw;
            } else {
                receivedERC20 += _swapTokensForTokens(
                    GMX,
                    token,
                    actualWithdraw,
                    params.amountsOutMin[0],
                    params.data[1]
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

    /// @inheritdoc IParallaxStrategy
    function compound(
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) external nonReentrant onlyParallax returns (uint256) {
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
    function __gmxStrategy_init_unchained(
        InitParams memory initParams
    ) internal onlyInitializing {
        PARALLAX = initParams._PARALLAX;
        WETH = initParams._WETH;
        GMX = initParams._GMX;
        GMX_TRACKER = initParams._GMX_TRACKER;
        GMX_REWARD_TRACKER = initParams._GMX_REWARD_TRACKER;
        GMX_ROUTER = initParams._GMX_ROUTER;
        QUOTER = initParams._QUOTER;
        UNISWAP_V3_ROUTER = initParams._UNISWAP_V3_ROUTER;
        GMX_USD_ORACLE = AggregatorV2V3Interface(initParams._GMX_USD_ORACLE);
        WETH_USD_ORACLE = AggregatorV2V3Interface(initParams._WETH_USD_ORACLE);
        EXPIRE_TIME = initParams._EXPIRE_TIME;
        maxSlippage = initParams.maxSlippage;
        compoundMinAmount = initParams.initialCompoundMinAmount;
    }

    /**
     * @notice Deposits GMX tokens (LPs) into GMX's farm.
     * @param amount A deposit parameters.
     */
    function _deposit(uint256 amount) private {
        IERC20Upgradeable(GMX).approve(GMX_TRACKER, amount);
        IGMXRouter(GMX_ROUTER).stakeGmx(amount);
    }

    /**
     * @notice Withdraws tokens (LPs) from GMX's farm
     * @param amount A withdrawal parameters.
     */
    function _withdraw(uint256 amount) private {
        // Withdraw (unstake) GMX's tokens from the GMX's staking pool
        IGMXRouter(GMX_ROUTER).unstakeGmx(amount);
    }

    /**
     * @notice Harvests WETH tokens from GMX staking
     * @return receivedGmx An amount of GMX tokens received after WETH tokens
     *                     exchange.
     */
    function _harvest(
        bool toRevertIfFail
    ) private returns (uint256 receivedGmx) {
        //Harvest rewards from the Sorbettiere (in WETH tokens)
        IGMXTracker(GMX_REWARD_TRACKER).claim(address(this));

        uint256 wethBalance = IERC20Upgradeable(WETH).balanceOf(address(this));

        (uint256 wethUsdRate, , bool wethUsdFlag) = _getPrice(WETH_USD_ORACLE);
        (uint256 gmxUsdRate, , bool gmxUsdFlag) = _getPrice(GMX_USD_ORACLE);

        if (wethUsdFlag && gmxUsdFlag) {
            // Swap WETH rewards for GMX tokens
            if (wethBalance >= compoundMinAmount) {
                bytes memory path = abi.encodePacked(WETH, uint24(10000), GMX);
                uint256 amountOut = _getAmountOut(wethBalance, path);

                uint256 amountOutChainlink = (gmxUsdRate * wethBalance) /
                    wethUsdRate;

                bool priceIsCorrect = amountOut >=
                    (amountOutChainlink * (10000 - maxSlippage)) / 10000;

                if (priceIsCorrect) {
                    receivedGmx = _swapTokensForTokens(
                        WETH,
                        GMX,
                        wethBalance,
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
     * @notice Compounds earned GMX tokens to earn more rewards.
     * @return An amount of newly deposited (compounded) tokens (LPs).
     */
    function _compound(
        uint256[] memory,
        bool toRevertIfFail
    ) private returns (uint256) {
        // Harvest WETH tokens and swap them to GMX tokens
        _harvest(toRevertIfFail);

        IGMXRouter(GMX_ROUTER).compound();

        uint256 balanceGmx = IERC20Upgradeable(GMX).balanceOf(address(this));

        if (balanceGmx != 0) {
            // Reinvest swapped tokens (earned rewards)
            _deposit(balanceGmx);

            return balanceGmx;
        }

        return 0;
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
     * @notice Swaps `tokenIn` for `tokenOut` on GMXSwap using provided `path`.
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
        bytes memory path
    )
        private
        onlyCorrectPathLength(path)
        onlyCorrectPath(tokenIn, tokenOut, path)
        returns (uint256)
    {
        IERC20Upgradeable(tokenIn).safeIncreaseAllowance(
            UNISWAP_V3_ROUTER,
            amountIn
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams(
                path,
                address(this),
                _getDeadline(),
                amountIn,
                amountOutMin
            );

        uint256 amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);

        return amountOut;
    }

    /**
     * @notice This function extracts a specific slice of the given byte array
     *         as an address.
     * @param input The byte array from which to extract the address.
     * @param start The starting index in the byte array to begin the extraction.
     * @return token The extracted address from the input bytes.
     */
    function _sliceAddress(
        bytes memory input,
        uint256 start
    ) public pure returns (address token) {
        bytes memory addressBytes = new bytes(ADDRESS_SIZE);

        assembly {
            let src := add(add(input, 32), start)
            let dst := add(addressBytes, 32)
            mstore(dst, mload(src))

            token := mload(add(addressBytes, ADDRESS_SIZE))
        }
    }

    /**
     * @notice A function that takes a specified fee.
     * @dev This is a private function to deduct fees.
     * @param withdrawalFee The amount of the fee to be taken
     */
    function _takeFee(uint256 withdrawalFee) private {
        if (withdrawalFee > 0) {
            accumulatedFees += withdrawalFee;

            IERC20Upgradeable(GMX).safeTransfer(
                IParallax(PARALLAX).feesReceiver(),
                withdrawalFee
            );
        }
    }

    /**
     * @notice Returns an amount of output tokens after the exchange of
     *         `amountIn` on GMXSwap using provided `path`.
     * @param amountIn An amount of tokens to exchange.
     * @param path A path that will be used for an exchange.
     * @return An amount of output tokens after an exchange of `amountIn` on
     *         GMXSwap using provided `path`.
     */
    function _getAmountOut(
        uint256 amountIn,
        bytes memory path
    ) private onlyCorrectPathLength(path) returns (uint256) {
        return IQuoter(QUOTER).quoteExactInput(path, amountIn);
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
     * @notice Returns a deadline timestamp for GMXSwap's exchanges.
     * @return A deadline timestamp for GMXSwap's exchanges
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
    function _onlyCorrectPathLength(bytes memory path) private pure {
        // 2*ADDRESS_SIZE + FEE_SIZE
        if (path.length < 43) {
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
        bytes memory path
    ) private pure {
        address tokenA = _sliceAddress(path, 0);
        address tokenB = _sliceAddress(path, path.length - ADDRESS_SIZE);

        if (tokenIn != tokenA || tokenOut != tokenB) {
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
}

