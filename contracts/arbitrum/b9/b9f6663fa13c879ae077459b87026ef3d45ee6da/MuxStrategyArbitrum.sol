// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./IMuxOrderBook.sol";
import "./IMuxRewardsRouter.sol";
import "./IMuxLiquidityPool.sol";
import "./ReentrancyGuard.sol";
import "./FractBaseTokenizedStrategy.sol";

/**
 * @title Strategy for MUX in Arbitrum.
 */
contract MuxStrategyArbitrum is FractBaseTokenizedStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --------------------------------------------------------------------------------------------------
    // MUX Addresses for Arbitrum
    // --------------------------------------------------------------------------------------------------
    address public constant MUX_ORDER_BOOK = address(0xa19fD5aB6C8DCffa2A295F78a5Bb4aC543AAF5e3);
    address public constant MUX_LIQUIDITY_POOL = address(0x3e0199792Ce69DC29A0a36146bFa68bd7C8D6633);
    address public constant MUX_REWARDS_ROUTER = address(0xaf9C4F6A0ceB02d4217Ff73f3C95BbC8c7320ceE);
    address public constant MUX_LP_TOKEN = address(0x7CbaF5a14D953fF896E5B3312031515c858737C8);
    address public constant MUX_TOKEN = address(0x8BB2Ac0DCF1E86550534cEE5E9C8DED4269b679B);
    address public constant STAKED_MLP_TOKEN = address(0x0a9bbf8299FEd2441009a7Bb44874EE453de8e5D);
    address public constant MLP_REWARDS_TRACKER = address(0x290450cDea757c68E4Fe6032ff3886D204292914);
    address public constant WETH_ADDRESS = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    constructor(
        string memory receiptTokenName, 
        string memory receiptTokenSymbol, 
        uint8 receiptTokenDecimals) FractBaseTokenizedStrategy(
            receiptTokenName, 
            receiptTokenSymbol, 
            receiptTokenDecimals) {}

    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit into the strategy.
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */
    function deposit(IERC20 token, uint256 amount) external onlyOwner nonReentrant {
        _deposit(token, amount);
    }

    /**
     * @notice Withdraw from the strategy. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdraw(IERC20 token, uint256 amount) external onlyOwner nonReentrant {
        _withdraw(token, amount);
    }

    /**
     * @notice Withdraw from the strategy to the owner. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdrawToOwner(IERC20 token, uint256 amount) external onlyOwner nonReentrant {
        _withdrawToOwner(token, amount);
    }

    /**
     * @notice Swap rewards via the paraswap router.
     * @param token The token to swap.
     * @param amount The amount of tokens to swap. 
     * @param callData The callData to pass to the paraswap router. Generated offchain.
     */
    function swap(IERC20 token, uint256 amount, bytes memory callData) external payable onlyOperator 
    {
        //call internal swap
        _swap(token, amount, callData);
    }

    /*///////////////////////////////////////////////////////////////
                            Strategy Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds liquidity to MUX.
     * @dev Swaps a token (say USDC) for MUXLP tokens. You can get the asset identifiers by calling "getAllMuxAssets()"
     * @param token The asset to deposit (for example: USDC)
     * @param assetId The ID of the asset to deposit (for example: USDC)
     * @param amount The deposit amount.
     */
    function addLiquidity(IERC20 token, uint8 assetId, uint256 amount) external onlyOwnerOrOperator nonReentrant {
        token.safeApprove(MUX_ORDER_BOOK, amount); 

        uint96 rawAmount = uint96(amount);
        IMuxOrderBook(MUX_ORDER_BOOK).placeLiquidityOrder(assetId, rawAmount, true);

        token.safeApprove(MUX_ORDER_BOOK, 0); 
    }

    /**
     * @notice Removes liquidity from MUX.
     * @dev Swaps MUXLP tokens for another token (say USDC). You can get the asset identifiers by calling "getAllMuxAssets()"
     * @param assetId The ID of the asset to receive in exchange for MUXLP.
     * @param amount The amount of MUXLP tokens to sell.
     */
    function removeLiquidity(uint8 assetId, uint256 amount) external onlyOwnerOrOperator nonReentrant {
        IERC20 token = IERC20(MUX_LP_TOKEN);
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore > 0, "Insufficient balance");

        token.safeApprove(MUX_ORDER_BOOK, amount); 

        uint96 rawAmount = uint96(amount);
        IMuxOrderBook(MUX_ORDER_BOOK).placeLiquidityOrder(assetId, rawAmount, false);

        token.safeApprove(MUX_ORDER_BOOK, 0);

        require(token.balanceOf(address(this)) == balanceBefore - amount, "Balance check failed");
    }

    /**
     * @notice Stakes MUXLP tokens. You get sMLP (staked MLP) tokens in exchange.
     * @return Returns the current balance of sMLP (staked MLP) tokens.
     */
    function stake() external onlyOwnerOrOperator nonReentrant returns (uint256) {
        uint256 currentBalanceInMuxLp = IERC20(MUX_LP_TOKEN).balanceOf(address(this));
        require(currentBalanceInMuxLp > 0, "No MuxLP tokens available");

        uint256 stakedMLPBefore = IERC20(STAKED_MLP_TOKEN).balanceOf(address(this));

        IERC20(MUX_LP_TOKEN).safeApprove(MLP_REWARDS_TRACKER, currentBalanceInMuxLp); 

        uint256 stakedAmount = IMuxRewardsRouter(MUX_REWARDS_ROUTER).stakeMlp(currentBalanceInMuxLp);

        IERC20(MUX_LP_TOKEN).safeApprove(MLP_REWARDS_TRACKER, 0); 

        uint256 stakedMLPAfter = IERC20(STAKED_MLP_TOKEN).balanceOf(address(this));
        require(stakedMLPAfter >= stakedMLPBefore + stakedAmount, "Balance check failed");

        return stakedMLPAfter;
    }

    /**
     * @notice Unstakes sMLP (staked MLP) tokens. You get MLP tokens in exchange.
     */
    function unstake() external onlyOwnerOrOperator nonReentrant {
        uint256 muxLpBefore = IERC20(MUX_LP_TOKEN).balanceOf(address(this));
        uint256 stakedMLP = IERC20(STAKED_MLP_TOKEN).balanceOf(address(this));

        IMuxRewardsRouter(MUX_REWARDS_ROUTER).unstakeMlp(stakedMLP);

        require(IERC20(MUX_LP_TOKEN).balanceOf(address(this)) > muxLpBefore, "Balance check failed");
    }

    /**
     * @notice Claims rewards from MUX.
     * @dev MUX distributes rewards every Thursday UTC. You will receive WETH + MUX
     */
    function claimRewards() external onlyOwnerOrOperator nonReentrant {
        uint256 muxBefore = IERC20(MUX_TOKEN).balanceOf(address(this));
        uint256 wethBefore = IERC20(WETH_ADDRESS).balanceOf(address(this));
        
        IMuxRewardsRouter(MUX_REWARDS_ROUTER).claimFromMlp();

        require(IERC20(MUX_TOKEN).balanceOf(address(this)) > muxBefore, "No MUX rewards received");
        require(IERC20(WETH_ADDRESS).balanceOf(address(this)) > wethBefore, "No WETH rewards received");
    }

    /*///////////////////////////////////////////////////////////////
                        Getters
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the list of assets supported by MUX on the current chain.
     * @return Returns an array of assets
     */
    function getAllMuxAssets() external view returns (IMuxLiquidityPool.Asset[] memory) {
        return IMuxLiquidityPool(MUX_LIQUIDITY_POOL).getAllAssetInfo();
    }
}

