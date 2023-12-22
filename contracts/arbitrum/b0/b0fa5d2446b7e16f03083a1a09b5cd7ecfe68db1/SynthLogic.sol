// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PriceConvertor.sol";
import "./IPool.sol";
import "./IERC20X.sol";
import "./ISyntheX.sol";
import "./Errors.sol";

import "./console.sol";

library SynthLogic {
    using PriceConvertor for uint256;
    
    event Liquidate(address indexed liquidator, address indexed account, address indexed outAsset, uint256 outAmount, uint256 outPenalty, uint256 outRefund);
    
    uint constant BASIS_POINTS = 10000;
    uint constant SCALER = 1e18;

    struct MintVars {
        address to;
        uint amountIn; 
        IPriceOracle priceOracle; 
        address synthIn; 
        address feeToken; 
        uint balance;
        uint totalSupply;
        uint totalDebt;
        DataTypes.AccountLiquidity liq;
        uint issuerAlloc;
        ISyntheX synthex;
    }

    struct BurnVars {
        uint amountIn; 
        IPriceOracle priceOracle; 
        address synthIn; 
        address feeToken; 
        uint balance;
        uint totalSupply;
        uint userDebtUSD;
        uint totalDebt;
        uint issuerAlloc;
        ISyntheX synthex;
    }

    struct SwapVars {
        address to;
        address synthIn;
        address synthOut;
        uint amount; 
        DataTypes.SwapKind kind;
        IPriceOracle priceOracle;
        address feeToken;
        uint issuerAlloc;
        ISyntheX synthex;
    }
    
    struct LiquidateVars {
        uint amountIn; 
        address account;
        IPriceOracle priceOracle; 
        address synthIn; 
        address collateralOut;
        address feeToken;
        uint totalSupply;
        uint totalDebt;
        DataTypes.AccountLiquidity liq;
        uint issuerAlloc;
        ISyntheX synthex;
    }

    function commitMint(
        MintVars memory vars,
        mapping(address => DataTypes.Synth) storage synths
    ) public returns(uint mintAmount) {
        require(synths[vars.synthIn].isActive, Errors.ASSET_NOT_ACTIVE);
        require(vars.liq.liquidity > 0, Errors.INSUFFICIENT_COLLATERAL);
        require(vars.amountIn > 0, Errors.ZERO_AMOUNT);
        require(vars.to != address(0), Errors.INVALID_ADDRESS);

        address[] memory tokens = new address[](2);
        tokens[0] = vars.synthIn;
        tokens[1] = vars.feeToken;
        uint[] memory prices = vars.priceOracle.getAssetsPrices(tokens);

        // 10 cETH * 1000 = 10000 USD
        // +10% fee = 11 cETH debt to issue (11000 USD)
        // 10 cETH minted to user (10000 USD)
        // 1 cETH fee (1000 USD) = 0.5 cETH minted to vault (1-issuerAlloc) + 0.5 cETH not minted (burned) 
        // This would result in net -0.5 cETH ($500) worth of debt issued; i.e. $500 of debt is reduced from pool (for all users)
        
        // Amount of debt to issue (in usd, including mintFee)
        uint amountUSD = vars.amountIn.toUSD(prices[0]);
        uint amountPlusFeeUSD = amountUSD + (amountUSD * synths[vars.synthIn].mintFee / (BASIS_POINTS));

        if(vars.liq.liquidity < int(amountPlusFeeUSD)){
            amountPlusFeeUSD = uint(vars.liq.liquidity);
        }

        // call for reward distribution before minting
        vars.synthex.distribute(msg.sender, vars.totalSupply, vars.balance);

        // Amount of debt to issue (in usd, including mintFee)
        mintAmount = amountPlusFeeUSD;
        if(vars.totalSupply > 0){
            require(vars.totalDebt > 0, Errors.INVALID_AMOUNT);
            // Calculate the amount of debt tokens to mint
            // debtSharePrice = totalDebt / totalSupply
            // mintAmount = amountUSD / debtSharePrice 
            mintAmount = amountPlusFeeUSD * vars.totalSupply / vars.totalDebt;
        }

        // Amount * (fee * issuerAlloc) is burned from global debt
        // Amount * (fee * (1 - issuerAlloc)) to vault
        // Fee amount of feeToken: amountUSD * fee * (1 - issuerAlloc) / feeTokenPrice
        amountUSD = amountPlusFeeUSD * (BASIS_POINTS) / (BASIS_POINTS + synths[vars.synthIn].mintFee);
        vars.amountIn = amountUSD.toToken(prices[0]);

        // Mint FEE tokens to vault
        address vault = vars.synthex.vault();
        if(vault != address(0)) {
            uint feeAmount = (
                (amountPlusFeeUSD - amountUSD)      // total fee amount in USD
                * (BASIS_POINTS - vars.issuerAlloc)      // multiplying (1 - issuerAlloc)
                / (BASIS_POINTS))                   // for multiplying issuerAlloc
                .toToken(prices[1]             // to feeToken amount
            );
            IERC20X(vars.feeToken).mint(
                vault,
                feeAmount
            );
        }

        // return the amount of synths to issue
        IERC20X(vars.synthIn).mint(vars.to, vars.amountIn);
    }

    function commitBurn(
        BurnVars memory vars,
        mapping(address => DataTypes.Synth) storage synths
    ) internal returns(uint burnAmount) {
        require(vars.amountIn > 0, Errors.ZERO_AMOUNT);
        // check if synth is valid
        if(!synths[vars.synthIn].isActive) require(synths[vars.synthIn].isDisabled, Errors.ASSET_NOT_ENABLED);

        address[] memory tokens = new address[](2);
        tokens[0] = vars.synthIn;
        tokens[1] = vars.feeToken;
        uint[] memory prices = vars.priceOracle.getAssetsPrices(tokens);

        // amount of debt to burn (in usd, including burnFee)
        // amountUSD = amount * price / (1 + burnFee)
        uint amountUSD = vars.amountIn.toUSD(prices[0]) * (BASIS_POINTS) / (BASIS_POINTS + synths[vars.synthIn].burnFee);
        // ensure user has enough debt to burn
        if(vars.userDebtUSD < amountUSD){
            // amount = debt + debt * burnFee / BASIS_POINTS
            vars.amountIn = (vars.userDebtUSD + (vars.userDebtUSD * (synths[vars.synthIn].burnFee) / (BASIS_POINTS))).toToken(prices[0]);
            amountUSD = vars.userDebtUSD;
        }
        // ensure user has enough debt to burn
        if(amountUSD == 0) return 0;

        // call for reward distribution
        vars.synthex.distribute(msg.sender, vars.totalSupply, vars.balance);

        require(vars.totalDebt > 0, Errors.INVALID_AMOUNT);
        require(vars.totalSupply > 0, Errors.INVALID_AMOUNT);
        burnAmount = vars.totalSupply * amountUSD / vars.totalDebt;

        address vault = vars.synthex.vault();
        if(vault != address(0)) {
            // Mint fee * (1 - issuerAlloc) to vault
            uint feeAmount = ((
                amountUSD * synths[vars.synthIn].burnFee * (BASIS_POINTS - vars.issuerAlloc) / (BASIS_POINTS)
            ) / BASIS_POINTS                // for multiplying burnFee
            ).toToken(prices[1]);           // to feeToken amount

            IERC20X(vars.feeToken).mint(
                vault,
                feeAmount
            );
        }

        IERC20X(vars.synthIn).burn(msg.sender, vars.amountIn);
    }

    function commitSwap(
        SwapVars memory vars,
        mapping(address => DataTypes.Synth) storage synths
    ) internal returns(uint[2] memory) {
        require(vars.amount > 0, Errors.ZERO_AMOUNT);
        require(vars.to != address(0), Errors.INVALID_ADDRESS);
        // check if enabled synth is calling
        // should be able to swap out of disabled (inactive) synths
        if(!synths[vars.synthIn].isActive) require(synths[vars.synthIn].isDisabled, Errors.ASSET_NOT_ENABLED);
        // ensure exchange is not to same synth
        require(vars.synthIn != vars.synthOut, Errors.INVALID_ARGUMENT);

        address[] memory t = new address[](3);
        t[0] = vars.synthIn;
        t[1] = vars.synthOut;
        t[2] = vars.feeToken;
        uint[] memory prices = vars.priceOracle.getAssetsPrices(t);

        uint amountUSD = 0;
        uint fee = 0;
        uint amountOut = 0;
        uint amountIn = 0;
        if(vars.kind == DataTypes.SwapKind.GIVEN_IN) {
            amountIn = vars.amount;
            amountUSD = vars.amount.toUSD(prices[0]);
            fee = amountUSD * (synths[vars.synthOut].mintFee + synths[vars.synthIn].burnFee) / BASIS_POINTS;
            amountOut = (amountUSD - fee).toToken(prices[1]);
        } else {
            amountOut = vars.amount;
            amountUSD = vars.amount.toUSD(prices[1]);
            fee = amountUSD - amountUSD * BASIS_POINTS / (BASIS_POINTS + synths[vars.synthOut].mintFee + synths[vars.synthIn].burnFee);
            amountIn = (amountUSD + fee).toToken(prices[0]);
        }

        // 1. Mint (amount - fee) toSynth to recipient
        IERC20X(vars.synthOut).mint(vars.to, amountOut);
        // 2. Mint fee * (1 - issuerAlloc) (in feeToken) to vault
        address vault = vars.synthex.vault();
        if(vault != address(0)) {
            IERC20X(vars.feeToken).mint(
                vault,
                (fee * (BASIS_POINTS - vars.issuerAlloc)        // multiplying (1 - issuerAlloc)
                / (BASIS_POINTS))                           // for multiplying issuerAlloc
                .toToken(prices[2])
            );
        }
        // 3. Burn all fromSynth
        IERC20X(vars.synthIn).burn(msg.sender, amountIn);

        return [amountIn, amountOut];
    }

    function commitLiquidate(
        LiquidateVars memory vars,
        mapping(address => mapping(address => uint)) storage accountCollateralBalance,
        mapping(address => DataTypes.Synth) storage synths,
        mapping(address => DataTypes.Collateral) storage collaterals
    ) external returns(uint refundOut, uint burnAmount) {
        DataTypes.Vars_Liquidate memory iv;
        require(vars.amountIn > 0, Errors.ZERO_AMOUNT);


        // check if synth is enabled
        if(!synths[vars.synthIn].isActive) require(synths[vars.synthIn].isDisabled, Errors.ASSET_NOT_ENABLED);

        // Check account liquidity
        require(vars.liq.debt > 0, Errors.INSUFFICIENT_DEBT);
        require(vars.liq.collateral > 0, Errors.INSUFFICIENT_COLLATERAL);
        iv.ltv = vars.liq.debt * (SCALER) / (vars.liq.collateral);
        require(iv.ltv > collaterals[vars.collateralOut].liqThreshold * SCALER / BASIS_POINTS, Errors.ACCOUNT_BELOW_LIQ_THRESHOLD);
        // Ensure user has entered the collateral market

        iv.tokens = new address[](3);
        iv.tokens[0] = vars.synthIn;
        iv.tokens[1] = vars.collateralOut;
        iv.tokens[2] = vars.feeToken;
        iv.prices = vars.priceOracle.getAssetsPrices(iv.tokens);

        // Amount of debt to burn (in usd, excluding burnFee)
        iv.amountUSD = vars.amountIn.toUSD(iv.prices[0]) * (BASIS_POINTS)/(BASIS_POINTS + synths[vars.synthIn].burnFee);
        if(vars.liq.debt < iv.amountUSD) {
            iv.amountUSD = vars.liq.debt;
        }

        // Amount of debt to burn (in terms of collateral)
        iv.amountOut = iv.amountUSD.toToken(iv.prices[1]);
        iv.penalty = 0;
        refundOut = 0;

        // Sieze collateral
        uint balanceOut = accountCollateralBalance[vars.account][vars.collateralOut];
        if(iv.ltv > SCALER){
            // if ltv > 100%, take all collateral, no penalty
            if(iv.amountOut > balanceOut){
                iv.amountOut = balanceOut;
            }
        } else {
            // take collateral based on ltv, and apply penalty
            balanceOut = balanceOut * iv.ltv / SCALER;
            if(iv.amountOut > balanceOut){
                iv.amountOut = balanceOut;
            }
            // penalty = amountOut * liqBonus
            iv.penalty = iv.amountOut * (collaterals[vars.collateralOut].liqBonus - BASIS_POINTS) / (BASIS_POINTS);

            // if we don't have enough for [complete] bonus, take partial bonus
            if(iv.ltv * collaterals[vars.collateralOut].liqBonus / BASIS_POINTS > SCALER){
                // penalty = amountOut * (1 - ltv)/ltv 
                require(iv.ltv > 0, Errors.INVALID_AMOUNT);
                iv.penalty = iv.amountOut * (SCALER - iv.ltv) / (iv.ltv);
            }
            // calculate refund if we have enough for bonus + extra
            else {
                // refundOut = amountOut * (1 - ltv * liqBonus)
                refundOut = iv.amountOut * (SCALER - (iv.ltv * collaterals[vars.collateralOut].liqBonus / BASIS_POINTS)) / SCALER;
            }
        }

        accountCollateralBalance[vars.account][vars.collateralOut] -= (iv.amountOut + iv.penalty + refundOut);

        // Add collateral to liquidator
        accountCollateralBalance[msg.sender][vars.collateralOut]+= (iv.amountOut + iv.penalty);

        iv.amountUSD = iv.amountOut.toUSD(iv.prices[1]);
        // Amount of debt to burn
        require(vars.totalDebt > 0, Errors.INVALID_AMOUNT);
        burnAmount = vars.totalSupply * iv.amountUSD / vars.totalDebt;

        // send (burn fee - issuerAlloc) in feeToken to vault
        uint fee = iv.amountUSD * (synths[vars.synthIn].burnFee) / (BASIS_POINTS);
        address vault = vars.synthex.vault();
        if(vault != address(0)) {
            IERC20X(vars.feeToken).mint(
                vault,
                (fee * (BASIS_POINTS - vars.issuerAlloc)        // multiplying (1 - issuerAlloc)
                / BASIS_POINTS)                            // for multiplying issuerAlloc
                .toToken(iv.prices[2])
            );
        }

        emit Liquidate(msg.sender, vars.account, vars.collateralOut, iv.amountOut, iv.penalty, refundOut);

        // amount (in synth) plus burn fee
        IERC20X(vars.synthIn).burn(msg.sender, iv.amountUSD.toToken(iv.prices[0]) * (BASIS_POINTS + synths[vars.synthIn].burnFee) / (BASIS_POINTS));
    }
}
