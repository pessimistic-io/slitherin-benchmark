// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "./contracts_IERC20.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DebtMath} from "./DebtMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";
import {DexOracleLogic} from "./DexOracleLogic.sol";
import {SafeMath} from "./SafeMath.sol";

import "./console.sol";

/**
 * @title Perpetual Debt Logic library
 * @author Tazz Labs
 * @notice Implements the logic to update the perpetual debt state
 */

library PerpetualDebtLogic {
    using WadRayMath for uint256;
    using SafeMath for uint256;
    using DexOracleLogic for DataTypes.DexOracleData;

    // Number of seconds in a year (given 365.25 days)
    uint256 internal constant ONE_YEAR = 31557600;

    event Refinance(uint256 refinanceBlockNumber, uint256 elapsedTime, uint256 rate, uint256 refinanceMultiplier);

    //TODO add descriptions in Iguild
    event Mint(address indexed user, address indexed onBehalfOf, uint256 assetAmount, uint256 liabilityAmount);
    event Burn(address indexed user, address indexed onBehalfOf, uint256 assetAmount, uint256 liabilityAmount);
    event BurnAndDistribute(
        address indexed assetUser,
        address indexed liabilityUser,
        uint256 assetAmount,
        uint256 liabilityAmount
    );

    /**
     * @notice Initializes a perpetual debt.
     * @param perpDebt The perpetual debt object
     * @param assetTokenAddress The address of the underlying asset token contract (zToken)
     * @param liabilityTokenAddress The address of the underlying liability token contract (dToken)
     * @param moneyAddress The address of the money token on which the debt is denominated in
     * @param duration The duration, in seconds, of the perpetual debt
     * @param notionalPriceLimitMax Maximum price used for refinance purposes
     * @param notionalPriceLimitMin Minimum price used for refinance purposes
     * @param dexFactory Uniswap v3 factory address
     * @param dexFee Uniswap v3 pool fee (to identify pool used for refinance oracle purposes)
     **/
    function init(
        DataTypes.PerpetualDebtData storage perpDebt,
        address assetTokenAddress,
        address liabilityTokenAddress,
        address moneyAddress,
        uint256 duration,
        uint256 notionalPriceLimitMax,
        uint256 notionalPriceLimitMin,
        address dexFactory,
        uint24 dexFee
    ) internal {
        require(address(perpDebt.zToken) == address(0), Errors.PERPETUAL_DEBT_ALREADY_INITIALIZED);
        perpDebt.zToken = IAssetToken(assetTokenAddress);
        perpDebt.dToken = ILiabilityToken(liabilityTokenAddress);
        perpDebt.money = IERC20(moneyAddress);
        perpDebt.beta = WadRayMath.ray().div(duration);
        perpDebt.lastRefinance = block.number;

        updateNotionalPriceLimit(perpDebt, notionalPriceLimitMax, notionalPriceLimitMin);

        //Init Oracle
        perpDebt.dexOracle.init(dexFactory, assetTokenAddress, moneyAddress, dexFee);
        perpDebt.dexOracle.updateTWAPPrice();
    }

    /**
     * @notice Updates notional price limit
     * @param notionalPriceLimitMax Maximum price used for refinance purposes
     * @param notionalPriceLimitMin Minimum price used for refinance purposes
     **/
    function updateNotionalPriceLimit(
        DataTypes.PerpetualDebtData storage perpDebt,
        uint256 notionalPriceLimitMax,
        uint256 notionalPriceLimitMin
    ) internal {
        require(notionalPriceLimitMax < 2 * WadRayMath.ray(), Errors.PRICE_LIMIT_OUT_OF_BOUNDS);
        require(notionalPriceLimitMin <= notionalPriceLimitMax, Errors.PRICE_LIMIT_ERROR);
        perpDebt.notionalPriceMax = notionalPriceLimitMax; //[ray]
        perpDebt.notionalPriceMin = notionalPriceLimitMin; //[ray]
    }

    function getMoney(DataTypes.PerpetualDebtData storage perpDebt) internal view returns (IERC20) {
        return perpDebt.money;
    }

    function getAsset(DataTypes.PerpetualDebtData storage perpDebt) internal view returns (IAssetToken) {
        return perpDebt.zToken;
    }

    function getLiability(DataTypes.PerpetualDebtData storage perpDebt) internal view returns (ILiabilityToken) {
        return perpDebt.dToken;
    }

    // @dev retuned values as per oracle decimal units
    function getNotionalPrice(DataTypes.PerpetualDebtData storage perpDebt, address oracle)
        internal
        view
        returns (uint256)
    {
        IAssetToken zToken = perpDebt.zToken;
        return _getAssetPrice(address(zToken), oracle).rayDiv(zToken.getNotionalFactor());
    }

    // @dev retuned values as per oracle decimal units
    function getAssetBasePrice(DataTypes.PerpetualDebtData storage perpDebt, address oracle)
        internal
        view
        returns (uint256)
    {
        IAssetToken zToken = perpDebt.zToken;
        return _getAssetPrice(address(zToken), oracle);
    }

    // @dev retuned values as per oracle decimal units
    function getLiabilityBasePrice(DataTypes.PerpetualDebtData storage perpDebt, address oracle)
        internal
        view
        returns (uint256)
    {
        IAssetToken zToken = perpDebt.zToken;
        ILiabilityToken dToken = perpDebt.dToken;

        return _getAssetPrice(address(zToken), oracle).rayDiv(_getAssetLiabilityNotionalRatio(zToken, dToken)); // in base Currency units
    }

    // @dev retuned values as per oracle decimal units
    function _getAssetPrice(address asset, address oracle) internal view returns (uint256) {
        return IPriceOracleGetter(oracle).getAssetPrice(asset); //returns price in BASE_CURRENCY units
    }

    function getAssetGivenLiability(DataTypes.PerpetualDebtData storage perpDebt, uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256 assetFactor = perpDebt.zToken.getNotionalFactor();
        uint256 liabilityFactor = perpDebt.dToken.getNotionalFactor();

        return amount.rayMul(liabilityFactor.rayDiv(assetFactor));
    }

    function _getAssetLiabilityNotionalRatio(IAssetToken zToken, ILiabilityToken dToken)
        internal
        view
        returns (uint256)
    {
        return zToken.getNotionalFactor().rayDiv(dToken.getNotionalFactor()); // RAY
    }

    //@DEV meant to be run only offchain.  Checks current DEX price each time
    //returns estimate APY given current zPrice
    //apy_ in 10000 units.  ie, 10000 = 0% return in a year.
    function getAPY(DataTypes.PerpetualDebtData storage perpDebt) internal view returns (uint256 apy_) {
        uint256 zPrice = perpDebt.dexOracle.getPrice(0);

        //convert to Notional Price (RAY)
        uint256 notionalPrice = zPrice.rayDiv(perpDebt.zToken.getNotionalFactor());

        //Get estimated rate per second (in RAY)
        int256 logRate = DebtMath.calculateApproxRate(perpDebt.beta, notionalPrice);
        uint256 rate = DebtMath.calculateApproxNotionalUpdate(logRate, 1);

        apy_ = rate.rayPow(ONE_YEAR); //calculate 1 year compounding
        apy_ = apy_.mul(10000).div(WadRayMath.ray()); //convert to percent decimal precision

        return apy_;
    }

    function refinance(DataTypes.PerpetualDebtData storage perpDebt) internal {
        if (block.number > perpDebt.lastRefinance) {
            //calculate TWAP Price since last update (needs to be done in same block as refinance below)
            (uint256 zPrice, uint256 elapsedTime) = perpDebt.dexOracle.updateTWAPPrice();

            //convert to Notional Price
            uint256 notionalPrice = zPrice.rayDiv(perpDebt.zToken.getNotionalFactor());

            //impose price limits
            if (notionalPrice > perpDebt.notionalPriceMax) {
                notionalPrice = perpDebt.notionalPriceMax;
            } else {
                if (notionalPrice < perpDebt.notionalPriceMin) {
                    notionalPrice = perpDebt.notionalPriceMin;
                }
            }

            //calculate rate
            int256 rate = DebtMath.calculateApproxRate(perpDebt.beta, notionalPrice);
            uint256 updateMultiplier = DebtMath.calculateApproxNotionalUpdate(rate, elapsedTime);

            //update assets and liabilities notional multipliers
            perpDebt.zToken.updateNotionalFactor(updateMultiplier);
            perpDebt.dToken.updateNotionalFactor(updateMultiplier);

            //update last refinance block number
            perpDebt.lastRefinance = block.number;

            //emit message
            emit Refinance(block.number, elapsedTime, uint256(int256(WadRayMath.ray()) + rate), updateMultiplier);
        }
    }

    /**
     * @dev Mint perpetual debt
     * @dev Function takes zToken amount to be minted as input parameter, and will mint an equivalent amount of dTokens
     * @dev such that zToken notional minted == dToken notional minted (ie, notionals are conserved)
     * @param user address of user that is minting zTokens (and who will own the asset)
     * @param onBehalfOf address of user that is minting dTokens (and who will own liability)
     * @param amount [wad] base amount of zTokens being minted to the user
     **/
    function mint(
        DataTypes.PerpetualDebtData storage perpDebt,
        address user,
        address onBehalfOf,
        uint256 amount
    ) internal {
        uint256 assetFactor = perpDebt.zToken.getNotionalFactor();
        uint256 liabilityFactor = perpDebt.dToken.getNotionalFactor();

        //@dev conserve notional amounouts, using zToken decimal space
        uint256 dMintAmount = amount.rayMul(assetFactor.rayDiv(liabilityFactor));

        perpDebt.zToken.mint(user, amount);
        perpDebt.dToken.mint(user, onBehalfOf, dMintAmount);
        emit Mint(user, onBehalfOf, amount, dMintAmount);
    }

    /**
     * @dev Burn perpetual debt
     * @dev Function takes zToken amount to be burned as input parameter, and will burn an equivalent amount of dTokens
     * @dev such that zToken notional minted == dToken notional burned (ie, notionals are conserved)
     * @param user address of user that is burning zTokens (equal notional of asset and liabilities are burned)
     * @param onBehalfOf address of user that is burning dTokens (equal notional of asset and liabilities are burned)
     * @param amount [wad] notional amount of zTokens being burned by user.  User has to have right amount of asset and liability in wallet for a successfull burn
     **/
    function burn(
        DataTypes.PerpetualDebtData storage perpDebt,
        address user,
        address onBehalfOf,
        uint256 amount
    ) internal {
        // @dev - burn according to lowest precision space
        uint256 assetFactor = perpDebt.zToken.getNotionalFactor();
        uint256 liabilityFactor = perpDebt.dToken.getNotionalFactor();
        uint256 dBurnAmount;

        uint256 assetToLiabilityFactor = assetFactor.rayDiv(liabilityFactor);

        // Calculate amount of dToken that will be burned (without leaving dust)
        if (assetToLiabilityFactor <= WadRayMath.ray()) {
            dBurnAmount = amount.rayMul(assetToLiabilityFactor);
        } else {
            //execute burn in asset space, and then move result to debt base
            //@dev this corrects rounding errors given assets have a smaller decimal precision vs debt when assetToLiabilityFactor > RAY
            uint256 accountDebtBalance = perpDebt.dToken.balanceOf(onBehalfOf);
            uint256 accountZTokenEquivalence = accountDebtBalance.rayDiv(assetToLiabilityFactor);
            require(accountZTokenEquivalence >= amount, Errors.INSUFFICIENT_BALANCE_TO_BURN);

            //calculate burn amount in asset space
            uint256 newAccountDebtBalance = (accountZTokenEquivalence.sub(amount)).rayMul(assetToLiabilityFactor);
            dBurnAmount = accountDebtBalance.sub(newAccountDebtBalance);
        }

        // Burn calculated ammounts
        perpDebt.zToken.burn(user, amount);
        perpDebt.dToken.burn(onBehalfOf, dBurnAmount);

        emit Burn(user, onBehalfOf, amount, dBurnAmount);
    }

    /**
     * @dev burn liabilityUser liabilities (dTokens), using assetUser's assets (zTokens).
     * @dev if assets cannot cover liabilities, then deficit is distributed to all remaining assets
     * @dev if asset surplus remains, then surplus is distributed to all remaining assets
     * @dev Notional equivalence between assets and liabilities is maintained
     * @param assetUser address of user paying zTokens to burn and distribute
     * @param liabilityUser address of user whose liabilities are burned (onBehalfOf)
     * @param assetAmountNotional [wad] notional amount of asset from assetUser removed from assetUser's wallet
     * @param liabilityAmountNotional [wad] notional amount of liabilities burned from liabilityUser's wallet
     **/
    function burnAndDistribute(
        DataTypes.PerpetualDebtData storage perpDebt,
        address assetUser,
        address liabilityUser,
        uint256 assetAmountNotional,
        uint256 liabilityAmountNotional
    ) internal {
        //Burn liability
        uint256 maxLiabilityBurnAmount = perpDebt.dToken.balanceOf(liabilityUser);
        uint256 liabilityBurnAmount = perpDebt.dToken.notionalToBase(liabilityAmountNotional);
        uint256 assetBurnAmount = perpDebt.zToken.notionalToBase(assetAmountNotional);

        // Don't burn more than max debt
        if (maxLiabilityBurnAmount < liabilityBurnAmount) liabilityBurnAmount = maxLiabilityBurnAmount;

        //Burn asset & liability
        perpDebt.zToken.burn(assetUser, assetBurnAmount);
        perpDebt.dToken.burn(liabilityUser, liabilityBurnAmount);

        //Distribute surplus or deficit to ensure asset / liability notionals match
        //@dev distributeFactor in RAY
        uint256 distributeFactor = perpDebt.dToken.totalNotionalSupply().wadToRay().wadDiv(
            perpDebt.zToken.totalNotionalSupply()
        );
        perpDebt.zToken.updateNotionalFactor(distributeFactor);

        emit BurnAndDistribute(assetUser, liabilityUser, assetAmountNotional, liabilityAmountNotional);
    }
}

