// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./SafeCast.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./TickMath.sol";
import "./INonfungiblePositionManager.sol";
import "./LiquidityAmounts.sol";
import "./IWETH.sol";
import "./ITokenInterface.sol";
import "./LBInterface.sol";

/**
 * @title Pawnfi's FundingStrategy Contract
 * @author Pawnfi
 */
contract FundingStrategy is OwnableUpgradeable, ERC721HolderUpgradeable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice uniswap position manager address
    address public nonfungiblePositionManager;

    /// @notice uniswap factory address
    address public uniswapV3Factory;

    /// @notice WETH address
    address public WETH;

    /// @notice Liquidity Boosting address
    address public liquidityBoosting;

    /**
     * @notice Investment Info
     * @member pool Token pair address
     * @member tokenId The corresponding NFT token Id of liquidity position
     * @member liquidity Liquidity amount
     * @member sqrtPriceX96 Square root price
     * @member amounts Raised asset amount
     * @member finalAmounts Added liquidity amount
     * @member remainingAmounts Leftover asset amount
     * @member bonus lending revenue
     * @member returnAmounts Removed token amount
     * @member tokenFees Swap fee
     * @member itokens Supply certificate
     */
    struct InvestmentInfo {
        address pool;
        uint256 tokenId;
        uint128 liquidity;
        uint160 sqrtPriceX96;
        mapping(address => uint256) amounts;
        mapping(address => uint256) finalAmounts;
        mapping(address => uint256) remainingAmounts;
        mapping(address => uint256) bonus;
        mapping(address => uint256) returnAmounts;
        mapping(address => uint256) tokenFees;
        mapping(address => uint256) itokens;
    }

    // Store Investment Info of different event Id
    mapping(uint256 => InvestmentInfo) private _investmentInfoMap;

    /// @notice Corresponding lending market
    mapping(address => address) public lendPools;

    /// @notice Minimum deposit amount
    mapping(address => uint256) public depositMinimum;

    /**
     * @notice initialize contract parameters - only execute once
     * @param owner_ Owner address
     * @param nonfungiblePositionManager_ Uniswap position manager address
     * @param uniswapV3Factory_ uniswap factory address
     * @param liquidityBoosting_ Liquidity Boosintg address
     */
    function initialize(address owner_, address nonfungiblePositionManager_, address uniswapV3Factory_, address liquidityBoosting_) external initializer {
        _transferOwnership(owner_);

        nonfungiblePositionManager = nonfungiblePositionManager_;
        uniswapV3Factory = uniswapV3Factory_;
        WETH = LBInterface(liquidityBoosting_).WETH();
        liquidityBoosting = liquidityBoosting_;
    }

    /**
     * @notice Set corresponding lending market - exclusive to owner
     * @param token token address
     * @param lendPool Lending market address
     * @param amountMinimum Minimum supplied amount
     */
    function setLendPool(address token, address lendPool, uint256 amountMinimum) external onlyOwner {
        require(lendPools[token] == address(0));
        lendPools[token] = lendPool;
        depositMinimum[token] = amountMinimum;
    }

    /**
     * @notice Get liquidity information in Uniswap
     * @param rId EventID
     * @return tokenId Uniswap v3 ID
     * @return liquidity Liquidity amount
     * @return sqrtPriceX96 Square root price
     * @return finalAmount0 token0 amount
     * @return finalAmount1 token1 amount
     */
    function getLiquidityInfo(uint256 rId) external view returns (uint256 tokenId, uint128 liquidity, uint160 sqrtPriceX96, uint256 finalAmount0, uint256 finalAmount1) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        tokenId = investmentInfo.tokenId;
        liquidity = investmentInfo.liquidity;
        sqrtPriceX96 = investmentInfo.sqrtPriceX96;
        finalAmount0 = investmentInfo.finalAmounts[token0];
        finalAmount1 = investmentInfo.finalAmounts[token1];
    }

    /**
     * @notice Get position information after strategy execution
     * @param rId EventId
     * @return amount0 Committed token0 amount
     * @return amount1 Committed token1 amount
     * @return remainingAmount0 Leftover token0 amount
     * @return remainingAmount1 Leftover token1 amount
     * @return bonus0 token0 revenue in lending
     * @return bonus1 token1 revenue in lending
     * @return returnAmount0 Removed token0 amount
     * @return returnAmount1 Removed token1 amount
     * @return tokenFee0 token0 swap fee
     * @return tokenFee1 token1 swap fee
     * @return itoken0 token0 certificate in lending
     * @return itoken1 token1 certificate in lending
     */
    function getInvestmentInfo(uint256 rId)
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 remainingAmount0,
            uint256 remainingAmount1,
            uint256 bonus0,
            uint256 bonus1,
            uint256 returnAmount0,
            uint256 returnAmount1,
            uint256 tokenFee0,
            uint256 tokenFee1,
            uint256 itoken0,
            uint256 itoken1
        )
    {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        amount0 = investmentInfo.amounts[token0];
        amount1 = investmentInfo.amounts[token1];
        remainingAmount0 = investmentInfo.remainingAmounts[token0];
        remainingAmount1 = investmentInfo.remainingAmounts[token1];
        bonus0 = investmentInfo.bonus[token0];
        bonus1 = investmentInfo.bonus[token1];
        returnAmount0 = investmentInfo.returnAmounts[token0];
        returnAmount1 = investmentInfo.returnAmounts[token1];
        tokenFee0 = investmentInfo.tokenFees[token0];
        tokenFee1 = investmentInfo.tokenFees[token1];
        itoken0 = investmentInfo.itokens[token0];
        itoken1 = investmentInfo.itokens[token1];
    }

    /**
     * @notice Get token0 price (token1 as base) when adding liquidity to Uniswap 
     * @param rId EventID
     * @return price price token0
     */
    function getInvestmentPrice(uint256 rId) external view returns (uint256) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        return getPrice(investmentInfo.sqrtPriceX96);
    }

    /**
     * @notice Get original price in Uniswap
     * @param token0 token0 address
     * @param token1 token1 address
     * @param fee Fee tier
     * @param sqrtPriceX96 Square root Price
     */
    function getRealTimePrice(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) external view returns (uint256) {
        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, fee);
        if(sqrtPriceX96 == 0) {
            // (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        }
        return getPrice(sqrtPriceX96);
    }

    /**
     * @notice Get original price based on square root price
     * @param sqrtPriceX96 Square root price
     * @return Original price
     */
    function getPrice(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
        return FullMath.mulDiv(priceX96, 1e18, FixedPoint96.Q96);
    }

    /**
     * @notice Get revenue from supplying in lending market
     * @param rId EventID
     * @return capital0 Supplied token0 amount in lending
     * @return capital1 Supplied token1 amount in lending
     * @return bonus0 token0 revenue
     * @return bonus1 token1 revenue
     */
    function getLendInfos(uint256 rId) public returns (uint256 capital0, uint256 capital1, uint256 bonus0, uint256 bonus1) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        if(_strategyStatus(rId)) {
            capital0 = investmentInfo.remainingAmounts[token0];
            capital1 = investmentInfo.remainingAmounts[token1];
            bonus0 = investmentInfo.bonus[token0];
            bonus1 = investmentInfo.bonus[token1];
        } else {
            (capital0, bonus0) = _calculateLendInfo(token0, investmentInfo.itokens[token0], investmentInfo.remainingAmounts[token0]);
            
            (capital1, bonus1) = _calculateLendInfo(token1, investmentInfo.itokens[token1], investmentInfo.remainingAmounts[token1]);
        }
    }

    /**
     * @notice Calculate capital and revenue from supplying in lending market
     * @param token Supplied token address
     * @param iToken Supply certificate
     * @param remainingAmount Leftover Amount
     * @return capital Supplied amount
     * @return bonus Revenue
     */
    function _calculateLendInfo(address token, uint256 iToken, uint256 remainingAmount) private returns (uint256 capital, uint256 bonus) {
        address lendPool = lendPools[token];
        if(lendPool != address(0) && iToken > 0) {
            uint256 exchangeRate = IErc20Interface(lendPool).exchangeRateCurrent();
            uint256 balanceUnderlying = exchangeRate * iToken / 1e18;
            if(balanceUnderlying > remainingAmount) {
                bonus = balanceUnderlying - remainingAmount;
                capital = remainingAmount;
            } else {
                capital = balanceUnderlying;
            }
        } else {
            capital = remainingAmount;
        }
    }

    /**
     * @notice Get swap fee
     * @param rId EventID
     * @return token0Fee token0 swap fee
     * @return token1Fee token1 swap fee
     */
    function getSwapFees(uint256 rId) public returns (uint256 token0Fee, uint256 token1Fee) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        if(!_strategyStatus(rId)) {
            _collectFees(rId, token0, token1, true);
        }
        token0Fee = investmentInfo.tokenFees[token0];
        token1Fee = investmentInfo.tokenFees[token1];
    }

    /**
     * @notice Claim swap fee
     * @param rId Event id
     * @param token0 token0 address
     * @param token1 token1 address
     * @param update Identifier for token swap fee update
     */
    function _collectFees(uint256 rId, address token0, address token1, bool update) private {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: investmentInfo.tokenId,
            recipient: liquidityBoosting,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(collectParams);
        if(update) {
            investmentInfo.tokenFees[token0] = investmentInfo.tokenFees[token0] + amount0;
            investmentInfo.tokenFees[token1] = investmentInfo.tokenFees[token1] + amount1;
        }
    }

    /**
     * @notice Get the amount of tokens added to Uniswap based on event ID
     * @param rId EventId
     * @return amount0 token0 amount
     * @return amount1 token1 amount
     */
    function getAmountsForLiquidity(uint256 rId) public view returns (uint256 amount0, uint256 amount1) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];

        // (uint24 fee, uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, address token0, address token1)
        ( , , int24 tickLower, int24 tickUpper, address token0, address token1) = LBInterface(liquidityBoosting).getMarketMakingInfo(rId);

        uint256 returnAmount0 = investmentInfo.returnAmounts[token0];
        uint256 returnAmount1 = investmentInfo.returnAmounts[token1];
        if(returnAmount0 > 0 || returnAmount1 > 0) {
           (amount0, amount1) = (returnAmount0, returnAmount1);
        } else {
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            
            // (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(investmentInfo.pool).slot0();
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, investmentInfo.liquidity);
        }
    }

    /**
     * @notice Add raised tokens to Uniswap v3
     * @param rId EventId
     */
    function executeStrategy(uint256 rId) public {
        require(msg.sender == liquidityBoosting, "caller isn't liquidity offer");
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        
        (uint24 fee, uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, address token0, address token1) = LBInterface(liquidityBoosting).getMarketMakingInfo(rId);

        // (address token0, address token1, uint256 targetAmount0, uint256 targetAmount1, uint256 amount0, uint256 amount1)
        ( , , , , uint256 amount0, uint256 amount1) = LBInterface(liquidityBoosting).getAmountsInfo(rId);

        require(investmentInfo.amounts[token0] == 0 && investmentInfo.amounts[token1] == 0, "executed startegy");

        IERC20Upgradeable(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20Upgradeable(token1).safeTransferFrom(msg.sender, address(this), amount1);
        _approveMax(token0, nonfungiblePositionManager, amount0);
        _approveMax(token1, nonfungiblePositionManager, amount1);
        investmentInfo.amounts[token0] = amount0;
        investmentInfo.amounts[token1] = amount1;

        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, fee);
        if(pool != address(0)) {
            investmentInfo.pool = pool;
        } else {
            investmentInfo.pool = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);
        }

        InvestmentLocalVars memory liquidityVars = InvestmentLocalVars({
            token0: token0,
            token1: token1,
            amount0: amount0,
            amount1: amount1
        });
        (uint256 remainingAmount0, uint256 remainingAmount1) = _addLiquidity(rId, fee, tickLower, tickUpper, liquidityVars);
        
        InvestmentLocalVars memory lendVars = InvestmentLocalVars({
            token0: token0,
            token1: token1,
            amount0: remainingAmount0,
            amount1: remainingAmount1
        });
        _depositLendPools(rId, lendVars);
    }

    struct InvestmentLocalVars {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
    }

    /**
     * @notice Add liquidity to Uniswap
     * @param rId Event Id
     * @param fee Fee tier
     * @param tickLower Min price
     * @param tickUpper Max price
     * @param vars token address and amount
     * @return remainingAmount0 Leftover token0 amount
     * @return remainingAmount1 Leftover token1 amount
     */
    function _addLiquidity(uint256 rId, uint24 fee, int24 tickLower, int24 tickUpper, InvestmentLocalVars memory vars) private returns (uint256 remainingAmount0, uint256 remainingAmount1) {

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: vars.token0,
            token1: vars.token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: vars.amount0,
            amount1Desired: vars.amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        // (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(investmentInfo.pool).slot0();
        investmentInfo.sqrtPriceX96 = sqrtPriceX96;

        uint256 amount0Before = IERC20Upgradeable(vars.token0).balanceOf(address(this));
        uint256 amount1Before = IERC20Upgradeable(vars.token1).balanceOf(address(this));

        (
            investmentInfo.tokenId,
            investmentInfo.liquidity,
            ,
            
        ) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        uint256 amount0After = IERC20Upgradeable(vars.token0).balanceOf(address(this));
        uint256 amount1After = IERC20Upgradeable(vars.token1).balanceOf(address(this));
        
        investmentInfo.finalAmounts[vars.token0] = amount0Before - amount0After;
        investmentInfo.finalAmounts[vars.token1] = amount1Before - amount1After;
        remainingAmount0 = vars.amount0 - investmentInfo.finalAmounts[vars.token0];
        remainingAmount1 = vars.amount1 - investmentInfo.finalAmounts[vars.token1];
    }

    /**
     * @notice Supply asset to lending pool
     */
    function _depositLendPools(uint256 rId, InvestmentLocalVars memory vars) private {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];

        address lendPool0 = lendPools[vars.token0];
        address lendPool1 = lendPools[vars.token1];
        if(lendPool0 != address(0) && vars.amount0 >= depositMinimum[vars.token0]) {
            investmentInfo.itokens[vars.token0] = _depositLendPool(lendPool0, vars.token0, vars.amount0);
        }
        investmentInfo.remainingAmounts[vars.token0] = vars.amount0;
        if(lendPool1 != address(0) && vars.amount1 >= depositMinimum[vars.token1]) {
            investmentInfo.itokens[vars.token1] = _depositLendPool(lendPool1, vars.token1, vars.amount1);
        }
        investmentInfo.remainingAmounts[vars.token1] = vars.amount1;
    }

    /**
     * @notice Supply asset to lending pool
     * @param lendPool Lend market address
     * @param token token address
     * @param amount Supplied amount
     * @return Supply certificate
     */
    function _depositLendPool(address lendPool, address token, uint256 amount) private returns (uint256) {
        uint256 balanceBefore = IERC20Upgradeable(lendPool).balanceOf(address(this));
        uint256 exchangeRate = IErc20Interface(lendPool).exchangeRateCurrent();
        uint256 preMintCToken = amount * 1e18 / exchangeRate;
        if(amount > 0 && preMintCToken > 0) {
            if(token == WETH) {
                IWETH(token).withdraw(amount);
                IEtherInterface(lendPool).mint{value: amount}();
            } else {
                _approveMax(token, lendPool, amount);
                IErc20Interface(lendPool).mint(amount);
            }
        }
        uint256 balanceAfter = IERC20Upgradeable(lendPool).balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    /**
     * @notice token approval
     * @param token token address
     * @param spender Approved address
     * @param amount Approved amount
     */
    function _approveMax(address token, address spender, uint256 amount) private {
        uint256 allowance = IERC20Upgradeable(token).allowance(address(this), spender);
        if(allowance < amount) {
            IERC20Upgradeable(token).safeApprove(spender, 0);
            IERC20Upgradeable(token).safeApprove(spender, type(uint256).max);
        }
    }

    
    /**
     * @notice Get strategy status of specified Event Id
     * @param rId Event Id
     * @return true Strategy executed; false Strategy stopped 
     */
    function _strategyStatus(uint256 rId) private view returns (bool) {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        return investmentInfo.returnAmounts[token0] != 0 || investmentInfo.returnAmounts[token1] != 0;
    }

    /**
     * @notice Exit strategy
     * @param rId EventId
     */
    function exitedStrategy(uint256 rId) public {
        require(msg.sender == liquidityBoosting, "caller isn't liquidity offer");
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        address token0 = IUniswapV3Pool(investmentInfo.pool).token0();
        address token1 = IUniswapV3Pool(investmentInfo.pool).token1();
        require(investmentInfo.returnAmounts[token0] == 0 && investmentInfo.returnAmounts[token1] == 0, "exited strategy");
        _removeLiquidity(rId, token0, token1);
        _withdrawLendPools(rId, token0, token1);
    }

    /**
     * @notice Remove liquidity
     * @param rId Event ID
     * @param token0 token0 address
     * @param token1 token1 address
     */
    function _removeLiquidity(uint256 rId, address token0, address token1) private {
        _collectFees(rId, token0, token1, true);

        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: investmentInfo.tokenId,
            liquidity: investmentInfo.liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(nonfungiblePositionManager).decreaseLiquidity(params);

        _collectFees(rId, token0, token1, false);
        investmentInfo.returnAmounts[token0] = amount0;
        investmentInfo.returnAmounts[token1] = amount1;
    }

    /**
     * @notice Withdraw token from lending market
     * @param rId Event ID
     * @param token0 token0 address
     * @param token1 token1 address
     */
    function _withdrawLendPools(uint256 rId, address token0, address token1) private {
        InvestmentInfo storage investmentInfo = _investmentInfoMap[rId];
        uint256 amount0;
        uint256 amount1;
        uint256 itoken0 = investmentInfo.itokens[token0];
        uint256 itoken1 = investmentInfo.itokens[token1];
        if(itoken0 > 0) {
            uint256 income0 = _withdrawLendPool(lendPools[token0], token0, investmentInfo.itokens[token0]);
            if(income0 >= investmentInfo.remainingAmounts[token0]) {
                investmentInfo.bonus[token0] = income0 - investmentInfo.remainingAmounts[token0];
            }
            amount0 = income0;
        } else {
            amount0 = investmentInfo.remainingAmounts[token0];
        }
        if(itoken1 > 0) {
            uint256 income1 = _withdrawLendPool(lendPools[token1], token1, investmentInfo.itokens[token1]);
            if(income1 >= investmentInfo.remainingAmounts[token1]) {
                investmentInfo.bonus[token1] = income1 - investmentInfo.remainingAmounts[token1];
            }
            amount1 = income1;
        } else {
            amount1 = investmentInfo.remainingAmounts[token1];
        }
        IERC20Upgradeable(token0).safeTransfer(liquidityBoosting, amount0);
        IERC20Upgradeable(token1).safeTransfer(liquidityBoosting, amount1);
    }

    /**
     * @notice Withdraw token from lending market
     * @param lendpool Lending market address
     * @param token token address
     * @param amount Supply certificate
     */
    function _withdrawLendPool(address lendpool, address token, uint256 amount) private returns (uint256 income) {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(address(this));
        uint code = 0;
        if(amount > 0) {
            if(token == WETH) {
                uint256 balBefore = address(this).balance;
                code = IEtherInterface(lendpool).redeem(amount);
                uint256 balAfter = address(this).balance;
                IWETH(token).deposit{value: balAfter - balBefore}();
            } else {
                code = IErc20Interface(lendpool).redeem(amount);
            }
        }
        require(code == 0, "Lend pool redeem failed");
        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(address(this));
        income = balanceAfter - balanceBefore;
    }

    receive() external payable {}
}
