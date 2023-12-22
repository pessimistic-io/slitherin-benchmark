//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibRevshare.sol";
import "./IRevshareVault.sol";
import "./LibConstants.sol";

import "./console.sol";

/**
 * Utilities library used by RevshareVault for computations and rate adjustments.
 */
library LibRSUtils {

    //utility to remove guard check on loop iterations
    function incr(uint i) internal pure returns (uint) {
        unchecked {
            return i + 1;
        }
    }

    /**
     * Computes total AUM in USD for all active fee tokens
     */
    function aumUSD(LibRevshare.RevshareStorage storage fs) public view returns(uint usd) {
        //for each fee token allowed in the vault
        //move to memory so we're not accessing storage in loop
        IERC20[] memory feeTokens = fs.feeTokens;
        for(uint i=0;i<feeTokens.length;i=incr(i)) {
            IERC20 ft = IERC20(feeTokens[i]);
            LibRevshare.PriceFeed storage pf = fs.allowedFeeTokens[address(ft)];
            
            //make sure fee token still active
            //get the price of the asset
            uint price = getPrice(pf);
            //use it to compute USD value
            (uint _usd,) = _toUSD(fs, ft, price, 0);
            usd += _usd;
        }

        return usd;
    }

    /**
     * Get a summary of assets in the vault
     */
    function assets(LibRevshare.RevshareStorage storage fs) public view returns (IRevshareVault.AssetInfo[] memory tokens) {
         /**
         * RISK: Must limit the fee token count to avoid miner not allowing call due to high
         * gas usage
         */

        //create in-memory structure only for active fee tokens
        tokens = new IRevshareVault.AssetInfo[](fs.feeTokens.length);

        //count offset of return tokens
        uint cnt = 0;
        
        //copy fee tokens in memory to we're not accessing storage in loop
        IERC20[] memory feeTokens = fs.feeTokens;
        for(uint i=0;i<feeTokens.length;i=incr(i)) {
            IERC20 ft = feeTokens[i];
            LibRevshare.PriceFeed storage pf = fs.allowedFeeTokens[address(ft)];

            //lookup USD price of asset in 30-dec units
            uint price = getPrice(pf);

            //convert to total usd-precision USD value
            (uint usd, uint bal) = _toUSD(fs, ft, price, 0);

            tokens[cnt] = IRevshareVault.AssetInfo({
                token: address(ft),
                balance: bal,
                usdValue: usd,
                usdPrice: (price*LibConstants.USD_PRECISION) / LibConstants.PRICE_PRECISION
            });
            ++cnt;
        }
    }

    /**
     * Get the current USD volume threshold to mint a single DXBL token
     */
    function mintRate(LibRevshare.RevshareStorage storage rs) public view returns (uint rate) {
        /**
        * formula for mint rate:
        * startingRate+(startingRate*(ratePerMM*MM_vol))
        */
        uint16 normalizedMMInVolume = uint16(rs.currentVolume / LibConstants.MM_VOLUME);

        //mint rate is a bucket with min/max volume thresholds and establishes how many 
        //percentage points per million to apply to the starting mint rate 
        uint percIncrease = rs.currentMintRate.rate * normalizedMMInVolume;

        //mint rate percentage is expressed in 18-dec units so have to divide that out before adding to base
        rate = rs.baseMintThreshold + ((rs.baseMintThreshold * percIncrease)/1e18);
    } 

    /**
     * Convert the given raw fee-token volume amount into USD units based on current price of fee token
     */
    function computeVolumeUSD(LibRevshare.RevshareStorage storage fs, address feeToken, uint amount) public view returns(uint volumeUSD) {
        LibRevshare.PriceFeed storage pf = fs.allowedFeeTokens[feeToken];

        //price is in USD with 30decimal precision
        uint ftp = getPrice(pf);

        (uint v,) = _toUSD(fs, IERC20(feeToken), ftp, amount);
        volumeUSD = v;
    }

    /**
     * Compute the Net Asset Value (NAV) for each DXBL token in circulation.
     */
    function computeNavUSD(LibRevshare.RevshareStorage storage rs) public view returns (uint nav) {
        //console.log("--------------- START COMPUTE NAV ---------------------");
        
        //get the total supply of dxbl tokens
        uint supply = rs.dxbl.totalSupply();

        //get the total USD under management by this vault
        uint aum = aumUSD(rs);

        //if either is 0, the nav is 0
        if(supply == 0 || aum == 0) {
            return 0;
        }
         
        //supply is 18decs while aum and nav are expressed in USD units
        nav = (aum*1e18) / supply;
      //  console.log("--------------- END COMPUTE NAV ---------------------");
    }

    /**
     * Adjust the vault's 24hr USD volume with the newly executed volume amount
     */
    function adjustVolume(LibRevshare.RevshareStorage storage rs, uint volumeUSD) public {
        //get the current hour
        uint lastTrade = rs.lastTradeTimestamp;

        //record when we last adjusted volume
        rs.lastTradeTimestamp = block.timestamp;
        uint newVolume = volumeUSD;
        if(lastTrade > 0 && lastTrade <= (block.timestamp - LibConstants.DAY)) {
            delete rs.hourlyVolume;
        } else {
            //otherwise, since we never rolled over 24hrs, just delete the volume
            //that accrued 24hrs ago
            uint hr = (block.timestamp % LibConstants.DAY) / LibConstants.HOUR;
            uint slot = 0;
            //remove guard for some efficiency gain
            unchecked{slot = (hr+1)%24; }

            //get the volume bin 24hrs ago by wrapping around to next hour in 24hr period
            uint yesterdayTotal = rs.hourlyVolume[slot];

            //if we get called multiple times in the block, the same hourly total
            //would be deducted multiple times. So we reset it here so that we're 
            //not deducting it multiple times in the hour. Only the first deduction
            //will be applied and 0'd out.
            rs.hourlyVolume[slot] = 0;

            //add new volume to current hour bin
            rs.hourlyVolume[hr] += volumeUSD;

            //manipulate volume in memory not storage
            newVolume = rs.currentVolume + volumeUSD;

            //Remove volume from 24hr's ago if there was anything
            if(yesterdayTotal > 0) {
                //note that because currentVolume includes yesterday's, then this subtraction 
                //is safe.
                newVolume -= yesterdayTotal;
            } 
        }
        rs.currentVolume = newVolume;
        _adjustMintRate(rs, uint16(newVolume / LibConstants.MM_VOLUME));
    }

    /**
     * Get the price of an asset by calling its chainlink price feed
     */
    function getPrice(LibRevshare.PriceFeed storage pf) public view returns (uint) {
        
        //get latest price
        (   ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = pf.feed.latestRoundData();

        //make sure price valid
        require(answer > 0, "No price data available");

        //10min buffer around 24hr window for chainlink feed to update prices
        uint stale = block.timestamp - LibConstants.DAY - 600;
        require(updatedAt > stale, "Stale price data");
        return (uint256(answer) * LibConstants.PRICE_PRECISION) / (10**pf.decimals);
    }

    /**
     * Convert an assets total balance to USD
     */
    function _toUSD(LibRevshare.RevshareStorage storage fs, IERC20 token, uint price, uint amt) internal view returns(uint usd, uint bal) {
        bal = amt;
        if(bal == 0) {
            bal = token.balanceOf(address(this));
        }
        
        //compute usd in raw form (fee-token units + price-precision units) but account for
        //USD precision
        usd = (bal * price)*LibConstants.USD_PRECISION;

        //then divide out the fee token and price-precision units
        usd /= (10**fs.tokenDecimals[address(token)]*LibConstants.PRICE_PRECISION);
        
    }

    /**
     * Make an adjustment to the mint rate if the 24hr volume falls into a new rate bucket
     */
    function _adjustMintRate(LibRevshare.RevshareStorage storage rs, uint16 normalizedMMInVolume) internal {
        
        LibRevshare.MintRateRange memory mr = rs.currentMintRate;
        //if the current rate bucket's max is less than current normalized volume
        if(mr.maxMMVolume <= normalizedMMInVolume) {
            //we must have increased volume so we have to adjust the rate up
            _adjustMintRateUp(rs, normalizedMMInVolume);
            //otherwise if the current rate's min is more than the current volume
        } else if(mr.minMMVolume >= normalizedMMInVolume) {
            //it means we're trading less volume than the current rate, so we need
            //to adjust it down
            _adjustMintRateDown(rs, normalizedMMInVolume);
        } //else rate stays the same
    }

    /**
     * Increase the minimum volume required to mint a single token
     */
    function _adjustMintRateUp(LibRevshare.RevshareStorage storage rs, uint16 mm) internal {
        LibRevshare.MintRateRange memory mr = rs.currentMintRate;
        while(!_rateInRange(mr,mm)) {
            //move to the next higher rate if one is configured, otherwise stay where we are
            LibRevshare.MintRateRange storage next = rs.mintRateRanges[mr.index + 1];
            if(next.rate == 0) {
                //reached highest rate, that will be the capped rate 
                break;
            }
            mr = next;
        }

        //don't waste gas storing if not changed
        if(rs.currentMintRate.rate != mr.rate) {
            rs.currentMintRate = mr;
        }
        
    }
    
    /**
     * Decrease minimum volume required to mint a DXBL token
     */
    function _adjustMintRateDown(LibRevshare.RevshareStorage storage rs, uint16 mm) internal {
        LibRevshare.MintRateRange memory mr = rs.currentMintRate;
        while(!_rateInRange(mr,mm)) {
            if(mr.index > 0) {
                //move to the next higher rate if one is configured, otherwise stay where we are
                LibRevshare.MintRateRange storage next = rs.mintRateRanges[mr.index - 1];
                mr = next;
            } else {
                //we go to the lowest rate then
                break;
            }
        }
        rs.currentMintRate = mr;
    }

    //test to see if volume is range for a rate bucket
    function _rateInRange(LibRevshare.MintRateRange memory range, uint16 mm) internal pure returns (bool) {
        return range.minMMVolume <= mm && mm < range.maxMMVolume;
    }
    
}
