// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeMath.sol";

import "./IVault.sol";
import "./IAsset.sol";

import "./IFlashLoanReceiver.sol";
import "./IUniswapV3Router.sol";
import "./ILiquidityPool.sol";
import "./IxTokenManager.sol";

/**
 * Contract which liquidates users on xToken Lending which are below the minimum health ratio
 * Main function is flashLiquidate
 * Takes out USDC loan from Lending to liquidate user and sells received collateral to repay loan
 * Supports Uniswap and Balancer for swapping tokens
 */
contract FlashLiquidator is
    IFlashLoanReceiver,
    Initializable,
    OwnableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    ILiquidityPool private liquidityPool; // liquidity pool address
    IERC20Upgradeable baseToken; // liquidity pool borrow token

    IUniswapV3Router private constant uniRouter =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uni V3 router

    IVault private constant balancerRouter =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8); // Balancer swap vault

    IERC20Upgradeable private constant USDC =
        IERC20Upgradeable(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8); // USDC
    IERC20Upgradeable private constant WETH =
        IERC20Upgradeable(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
    IERC20Upgradeable private constant WBTC =
        IERC20Upgradeable(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f); // WBTC
    IERC20Upgradeable private constant LINK =
        IERC20Upgradeable(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4); // LINK

    IERC20Upgradeable[] private lendingTokens; // Tokens in Lending markets

    mapping(address => MarketType) tokenSellMarket; // Mapping of token => market to sell to

    mapping(address => TradeType) tokenSellType; // Mapping of token => type of trade to do (Direct vs Multihop)

    mapping(address => uint24) tokenPoolFee; // Mapping of token => Pool fee (for Uniswap ; Direct swaps)

    mapping(address => bytes) tokenTradePath; // Mapping of token => Trade path (for Uniswap ; Multihop swaps)

    mapping(address => bytes32) tokenPoolId; // Mapping of token => pool id (for Balancer ; Direct swaps)

    mapping(address => BalancerParams) tokenBalancerParams; // Mapping of token => BalancerParams (for Balancer ; Multihop swaps)

    IxTokenManager private xTokenManager;

    // balancer multihop params
    struct BalancerParams {
        uint8 steps; // how many steps of the swap
        address[] internalTokens; // addresses of internal tokens (input -> internal[1] -> internal[2] -> /..)
        bytes32[] poolIds; // pool ids for the swap
    }

    // Markets to sell collaterals on liquidation
    enum MarketType {
        Uniswap,
        Balancer
    }

    // Type of trades for the markets
    // Direct -> Swap token for USDC directly
    // Multihop -> Use a trade path to sell token
    enum TradeType {
        Direct,
        Multihop
    }

    // Parameters to pass into liquidation function
    struct LiquidationParams {
        address borrower;
        uint256 liquidationAmount;
    }

    // Initializer function
    function initialize(
        address _liquidityPool,
        IxTokenManager _xTokenManager,
        address _baseToken
    ) external initializer {
        __Ownable_init();

        liquidityPool = ILiquidityPool(_liquidityPool);
        xTokenManager = _xTokenManager;
        baseToken = IERC20Upgradeable(_baseToken);

        // approve liquidity pool
        USDC.safeApprove(_liquidityPool, type(uint256).max);
        // approve uniswap swap router
        USDC.safeApprove(address(uniRouter), type(uint256).max);
        WETH.safeApprove(address(uniRouter), type(uint256).max);
        WBTC.safeApprove(address(uniRouter), type(uint256).max);
        LINK.safeApprove(address(uniRouter), type(uint256).max);
        // approve balancer swap router
        USDC.safeApprove(address(balancerRouter), type(uint256).max);
        WETH.safeApprove(address(balancerRouter), type(uint256).max);
        WBTC.safeApprove(address(balancerRouter), type(uint256).max);
        LINK.safeApprove(address(balancerRouter), type(uint256).max);

        lendingTokens.push(WETH);
        lendingTokens.push(WBTC);
        lendingTokens.push(LINK);

        // Set on which exchanges we trade each asset and
        // whether we use direct or multihop swap

        tokenSellMarket[address(WETH)] = MarketType.Uniswap;
        tokenSellType[address(WETH)] = TradeType.Direct;
        tokenSellMarket[address(WBTC)] = MarketType.Uniswap;
        tokenSellType[address(WBTC)] = TradeType.Multihop;
        tokenSellMarket[address(LINK)] = MarketType.Balancer;
        tokenSellType[address(LINK)] = TradeType.Multihop;
    }

    /**
     * @dev Liquidate a xToken Borrower using a flash loan from Lending
     * @param _borrower user to liquidate
     * @param _flashAmount amount to liquidate for
     */
    function flashLiquidate(address _borrower, uint256 _flashAmount)
        external
        onlyOwnerOrManager
    {
        bytes memory _params = abi.encode(
            LiquidationParams({
                borrower: _borrower,
                liquidationAmount: _flashAmount
            })
        );
        liquidityPool.flashLoan(address(this), _flashAmount, _params);

        baseToken.safeTransfer(msg.sender, baseToken.balanceOf(address(this)));
    }

    /**
     * @dev Lending flash loan callback
     * @dev Liquidation and swap logic is here
     * @dev Liquidate user, receiving his collateral (wETH, wBTC or LINK)
     * @dev Swap collateral on Uniswap V3 or Balancer and pay back loan
     */
    function executeOperation(
        uint256 _flashAmount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        require(
            _flashAmount <= baseToken.balanceOf(address(this)),
            "Not enough balance to perform liquidation"
        );
        LiquidationParams memory params = abi.decode(
            _params,
            (LiquidationParams)
        );
        liquidityPool.liquidate(params.borrower, params.liquidationAmount);

        uint256 minReturn = _flashAmount.add(_fee);

        // Go through all lending market tokens
        // Check if any balance received of that token after liquidation
        // If there is, swap the token on the specified market in *tokenSellMarket*
        // And the specified type of swap in *tokenSellType*
        for (uint256 i = 0; i < lendingTokens.length; i++) {
            IERC20Upgradeable lendingToken = lendingTokens[i];
            uint256 inputAmount = lendingToken.balanceOf(address(this));
            if (inputAmount > 0) {
                address inputToken = address(lendingToken); // collateral token
                address outputToken = address(baseToken); // USDC

                MarketType market = tokenSellMarket[inputToken];
                TradeType trade = tokenSellType[outputToken];

                if (market == MarketType.Uniswap) {
                    if (trade == TradeType.Direct) {
                        uint24 fee = tokenPoolFee[inputToken];
                        _swapExactInputUniswap(
                            inputToken,
                            outputToken,
                            inputAmount,
                            minReturn,
                            fee
                        );
                    } else if (trade == TradeType.Multihop) {
                        bytes memory tradePath = tokenTradePath[inputToken];
                        _swapExactInputUniswapMultiHop(
                            tradePath,
                            inputAmount,
                            minReturn
                        );
                    }
                } else if (market == MarketType.Balancer) {
                    if (trade == TradeType.Direct) {
                        bytes32 poolId = tokenPoolId[inputToken];
                        _swapExactInputBalancer(
                            inputToken,
                            outputToken,
                            inputAmount,
                            minReturn,
                            poolId
                        );
                    } else if (trade == TradeType.Multihop) {
                        BalancerParams
                            memory balancerParams = tokenBalancerParams[
                                inputToken
                            ];
                        _swapExactInputBalancerMultihop(
                            balancerParams.steps,
                            inputToken,
                            outputToken,
                            balancerParams.internalTokens,
                            balancerParams.poolIds,
                            inputAmount
                        );
                    }
                }
            }
        }
    }

    // ---- Market Swap Helper functions ----

    /**
     * @dev Uniswap V3 swap exact amount of token for amount of other token
     * @param inputToken address of token to swap
     * @param outputToken address of token to receive
     * @param inputAmount amount of input token to swap
     * @param minReturn minimum amount to receive of output token
     * @param poolFee pool fee for token swap
     */
    function _swapExactInputUniswap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minReturn,
        uint24 poolFee
    ) private returns (uint256 amountOut) {
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(inputToken),
                tokenOut: address(outputToken),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: minReturn,
                sqrtPriceLimitX96: 0
            });

        return uniRouter.exactInputSingle(params);
    }

    /**
     * @dev Swap exact input amount of first token in path for the last token in path
     * @dev Trade path is a sequence of *token*-*fee*-*token*,
     * @dev specifying which pools should the swap go through
     * @param tradePath path for the swap
     * @param inputAmount amount of input tokens for the swap
     * @param minReturn minimum amount of tokens to be received
     */
    function _swapExactInputUniswapMultiHop(
        bytes memory tradePath,
        uint256 inputAmount,
        uint256 minReturn
    ) private returns (uint256 amountOut) {
        IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router
            .ExactInputParams({
                path: tradePath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: minReturn
            });

        return uniRouter.exactInput(params);
    }

    /**
     * Swap exact input of token in a pool in balancer
     * Check out balancer docs for more info
     * https://dev.balancer.fi/resources/swaps/single-swap
     * @param inputToken address of token to swap
     * @param outputToken address of token to receive
     * @param inputAmount amount of input token to swap
     * @param minReturn minimum amount to receive of output token
     * @param poolId id of pool to swap in
     */
    function _swapExactInputBalancer(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minReturn,
        bytes32 poolId
    ) private {
        IVault.SingleSwap memory _singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind(0),
            assetIn: IAsset(inputToken),
            assetOut: IAsset(outputToken),
            amount: inputAmount,
            userData: ""
        });

        IVault.FundManagement memory _fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: address(this),
            toInternalBalance: false
        });
        balancerRouter.swap(
            _singleSwap,
            _fundManagement,
            minReturn,
            block.timestamp
        );
    }

    /**
     * Swap exact input of token in a pool in balancer using a multihop swap
     * There's no min amount out parameter for this swap for Balancer
     * Check out Balancer docs for more info
     * https://dev.balancer.fi/resources/swaps/batch-swaps
     * @param steps number of steps to take for swap (how many pools to route through)
     * @param inputToken address of token to swap
     * @param outputToken address of token to receive
     * @param internalTokens addresses of tokens to hop through
     * @param poolIds pool ids to hop through
     * @param inputAmount amount of input token to swap
     */
    function _swapExactInputBalancerMultihop(
        uint8 steps,
        address inputToken,
        address outputToken,
        address[] memory internalTokens,
        bytes32[] memory poolIds,
        uint256 inputAmount
    ) private {
        IAsset[] memory assets = new IAsset[](steps);
        assets[0] = IAsset(inputToken);
        for (uint256 i = 1; i < steps - 1; ++i) {
            assets[i] = IAsset(internalTokens[i - 1]);
        }
        assets[2] = IAsset(outputToken);

        int256[] memory limits = new int256[](steps);
        for (uint256 i = 0; i < steps; ++i) {
            limits[i] = type(int256).max;
        }

        // Generate swap steps
        IVault.BatchSwapStep[] memory swapSteps = new IVault.BatchSwapStep[](
            steps - 1
        );

        // 1st step is swap input token for first internalToken
        IVault.BatchSwapStep memory swapStep = IVault.BatchSwapStep({
            poolId: poolIds[0],
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: inputAmount,
            userData: ""
        });
        swapSteps[0] = swapStep;

        // next steps are swap through all internalTokens, ending with outputToken
        for (uint256 i = 1; i < steps - 1; ++i) {
            swapStep = IVault.BatchSwapStep({
                poolId: poolIds[i],
                assetInIndex: i, // index of asset in *assets*
                assetOutIndex: i + 1,
                amount: 0, // amount 0 means we use entire output amount from previous swap step
                userData: ""
            });
            swapSteps[i] = swapStep;
        }

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: address(this),
            toInternalBalance: false
        });

        balancerRouter.batchSwap(
            IVault.SwapKind(0),
            swapSteps,
            assets,
            fundManagement,
            limits,
            block.timestamp
        );
    }

    // ---- Management functions ----

    /**
     * Set which market will be used for token to sell to
     * @param token token address
     * @param market market type -> Uniswap or Balancer
     */
    function setTokenSellMarket(address token, MarketType market)
        external
        onlyOwnerOrManager
    {
        tokenSellMarket[token] = market;
    }

    /**
     * Set whether token will be sold directly for USDC or use a trade path
     * @param token token address
     * @param trade type of trade -> Direct or Multihop
     */
    function setTokenDirectOrMultihopTrade(address token, TradeType trade)
        external
        onlyOwnerOrManager
    {
        tokenSellType[token] = trade;
    }

    /**
     * Set pool fee for a given token on Uniswap
     * @param token token address
     * @param poolFee pool fee
     */
    function setTokenPoolFeeForUniswap(
        address token,
        uint24 poolFee
    ) external onlyOwnerOrManager {
        tokenPoolFee[token] = poolFee;
    }

    /**
     * Set trade path for a given token on Uniswap
     * @param token token address
     * @param tradePath a sequence of *token*-*fee*-*token*, specifying which pools the swap will go through
     */
    function setTokenMultihopRouteForUniswap(
        address token,
        bytes calldata tradePath
    ) external onlyOwnerOrManager {
        tokenTradePath[token] = tradePath;
    }

    /**
     * Set pool id for a given token on Balancer
     * @param token token address
     * @param poolId id of the pool to swap through
     */
    function setTokenPoolIdForBalancer(address token, bytes32 poolId)
        external
        onlyOwnerOrManager
    {
        tokenPoolId[token] = poolId;
    }

    /**
     * Set multihop swap parameters for Balancer
     * @dev Parameters include number of swap steps, intermediate tokens and pool ids
     * @param token token address
     * @param params Balancer parameters for multihop swap
     */
    function setTokenMultihopRouterForBalancer(
        address token,
        BalancerParams memory params
    ) external onlyOwnerOrManager {
        require(
            params.internalTokens.length == params.steps - 2,
            "Internal tokens should be equal to swap steps - 2"
        );
        require(
            params.poolIds.length == params.steps - 1,
            "Pools count should be equal to swap steps - 1"
        );
        tokenBalancerParams[token] = params;
    }

    /**
     * Approve a new market token to router
     */
    function approveTokenToRouter(IERC20 token, MarketType market)
        external
        onlyOwnerOrManager
    {
        if (market == MarketType.Uniswap) {
            token.approve(address(uniRouter), type(uint256).max);
        }
        if (market == MarketType.Balancer) {
            token.approve(address(balancerRouter), type(uint256).max);
        }
    }

    /**
     * Add a market token
     */
    function addMarketToken(IERC20Upgradeable token)
        external
        onlyOwnerOrManager
    {
        lendingTokens.push(token);
    }

    modifier onlyOwnerOrManager() {
        require(
            msg.sender == owner() ||
                xTokenManager.isManager(msg.sender, address(this)),
            "Non-admin caller"
        );
        _;
    }

    // Required for balancer swaps
    receive() external payable {}

    fallback() external payable {}
}

