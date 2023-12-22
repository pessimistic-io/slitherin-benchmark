//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./IRevshareVault.sol";
import "./LibStorage.sol";
import "./LibConstants.sol";
import "./LibRSUtils.sol";
import "./ConfigurableRS.sol";
import "./SafeERC20.sol";

/**
 * The revshare vault is responsible for tracking 24hr volume levels for Dexible, computing
 * current Net Asset Value (NAV) of each token in circulation, minting DXBL tokens according
 * to volume threshold buckets, and redeeming DXBL for a portion of the vault's holdings.
 *
 * The vault has minting authority to the DXBL token and is the only way to create and
 * burn DXBL tokens.
 */
contract RevshareVault is ConfigurableRS, IRevshareVault {

    using LibRSUtils for LibRevshare.RevshareStorage;
    using SafeERC20 for IERC20;

    //makes sure only the Dexible contract can call a function
    modifier onlyDexible() {
        require(msg.sender == LibStorage.getRevshareStorage().dexible, "Unauthorized");
        _;
    }

    /**
     * Check whether a fee tokens is allowed to pay for fees
     */
    function isFeeTokenAllowed(address token) external override view returns(bool) {
        return address(LibStorage.getRevshareStorage().allowedFeeTokens[token].feed) != address(0);
    }

    /**
     * Get the current minimum volume required to mint a DXBL token. This is returned
     * in USD precision units (see LibConstants for that value but is likely 6-decimals)
     */
    function currentMintRateUSD() external override view returns (uint rate) {
        return LibStorage.getRevshareStorage().mintRate();
    }

    /**
     * Get the current NAV for each DXBL token in circulation. This is returned in 
     * USD precision units (see LibConstants but is likely 6 decimals)
     */
    function currentNavUSD() external view override returns(uint) {
        return LibStorage.getRevshareStorage().computeNavUSD();
    }

    /**
     * Get the current discount applied per DXBL token owned. This is a bps 
     * setting so 5 means 5 bps or .05%
     */
    function discountBps() external view override returns(uint32) {
        return LibStorage.getRevshareStorage().dxbl.discountPerTokenBps();
    }

    /**
     * Compute the total USD value of assets held in the vault.
     */
    function aumUSD() external view returns(uint) {
        return LibStorage.getRevshareStorage().aumUSD();
    }

    /**
     * Get details of assets held by the vault.
     */
    function assets() external view override returns (AssetInfo[] memory) {
        return LibStorage.getRevshareStorage().assets();
    }

    /**
     * Compute the USD volume traded in the last 24hrs
     */
    function dailyVolumeUSD() external view override returns (uint) {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        return rs.currentVolume;
    }

    /**
     * Get the USD price for a fee token
     */
    function feeTokenPriceUSD(address feeToken) external view override returns(uint) {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        LibRevshare.PriceFeed storage pf = rs.allowedFeeTokens[feeToken];
        require(address(pf.feed) != address(0), "Unsupported fee token");
        return LibRSUtils.getPrice(pf);
    }

    /**
     * Convert gas units to fee token units using oracle prices for native asset
     */
    function convertGasToFeeToken(address feeToken, uint gasCost) external view override returns(uint) {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        if(feeToken == rs.wrappedNativeToken) {
            //already in native units
            return gasCost;
        }
        uint np = LibRSUtils.getPrice(rs.allowedFeeTokens[rs.wrappedNativeToken]);
        uint ftp = LibRSUtils.getPrice(rs.allowedFeeTokens[feeToken]);
        uint ftpNative = (np*LibConstants.PRICE_PRECISION)/ftp;
        uint ftpUnits = (ftpNative * gasCost) / LibConstants.PRICE_PRECISION;
        return (ftpUnits * (10**rs.tokenDecimals[feeToken])) / 1e18; //native is always 18decs
    }

    /**
     * Estimate how much of a fee token will be withdrawn given a balance of DXBL tokens.
     */
    function estimateRedemption(address rewardToken, uint dxblAmount) external override view returns(uint) {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        uint nav = rs.computeNavUSD();
         //convert nav to price-precision units
        nav = (nav * LibConstants.PRICE_PRECISION) / LibConstants.USD_PRECISION;
        
        //we need to know the value of each token in rewardToken units
        //start by getting the USD price of reward token
        uint ftUSD = this.feeTokenPriceUSD(rewardToken);

        uint8 ftDecs = rs.tokenDecimals[rewardToken];

        //Divide nav of each token by the price of each reward token expanding 
        //precision to include the fee-token decimals
        uint ftUnitPrice = (nav*(10**ftDecs))/ftUSD;

        //compute how much rewardToken to withdraw based on unit price of each DXBL
        //in fee-token units. Have to remove the dexible token precision (18)
        return (dxblAmount * ftUnitPrice)/1e18;
    }

    /**
     * Assume fee token has been vetted prior to making this call. Since only called by Dexible,
     * easy to verify that assumption.
     */
    function rewardTrader(address trader, address feeToken, uint amount) external override onlyDexible notPaused {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        uint volumeUSD = rs.computeVolumeUSD(feeToken, amount);

        //determine the mint rate
        uint rate = rs.mintRate();

        //make the volume adjustment to the pool
        rs.adjustVolume(volumeUSD);

        //get the number of DXBL per $1 of volume
        uint tokens = (volumeUSD*1e18) / rate;

        rs.dxbl.mint(trader, tokens);
    }
    
    /**
     * Redeem or burn DXBL for a specific reward token. The min amount reflects any slippage
     * that could occur if someone withdraws the same asset before a trader and the balance
     * cannot cover both withdraws.
     */
    function redeemDXBL(address rewardToken, uint dxblAmount, uint minOutAmount) external override notPaused {

        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        //get the trader's balance to make sure they actually have tokens to burn
        uint traderBal = rs.dxbl.balanceOf(msg.sender);
        require(traderBal >= dxblAmount, "Insufficient DXBL balance to redeem");
        
        //estimate how much we could withdraw if there is sufficient reward tokens available
        uint wdAmt = this.estimateRedemption(rewardToken, dxblAmount);

        /**
        * NOTE: is it likely that there will be dust remaining for the asset due to USD
        * rounding/precision.
        *
        * It will be redeemable once the balance acrues enough for the
        * next burn request
        */

        //how much does the vault own?
        uint vaultBal = IERC20(rewardToken).balanceOf(address(this));

        //do we have enough to cover the withdraw?
        if(wdAmt > vaultBal) {
            //vault doesn't have sufficient funds to cover. See if meets trader's 
            //min expectations
            if(vaultBal >= minOutAmount) {
                wdAmt = vaultBal;
            } else {
                revert("Insufficient asset balance to produce expected withdraw amount");
            }
        }
        //if all good, transfer withdraw amount to caller
        IERC20(rewardToken).safeTransfer(msg.sender, wdAmt);

        //burn the tokens
        rs.dxbl.burn(msg.sender, dxblAmount);
        emit DXBLRedeemed(msg.sender, dxblAmount, rewardToken, wdAmt);
    }
}
