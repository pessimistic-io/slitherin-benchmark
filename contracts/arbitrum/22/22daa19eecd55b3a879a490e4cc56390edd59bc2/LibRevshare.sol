//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./IDXBL.sol";
import "./LibConstants.sol";
import "./LibMultiSig.sol";

/**
 * Interface for Chainlink oracle feeds
 */
interface IPriceFeed {
    function latestRoundData() external view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/**
 * Library used for revshare vault storage and updates
 */
library LibRevshare {

    /****************************************************************************
     * Copy of events from IRevshareEvents
     *****************************************************************************/
    event ProposedDiscountChange(uint32 oldRate, uint32 newRate, uint allowedAfterTime);
    event DiscountChanged(uint32 newRate);

    event ProposedVolumeGoal(uint oldVolume, uint newVolume, uint allowedAfterTime);
    event AppliedVolumeGoal(uint newVolume);

    event ProposedMintRateChange(uint16 minThreshold, uint16 maxThreshold, uint percentage, uint allowedAfterTime);
    event MintRateChange(uint16 minThreshold, uint16 maxThreshold, uint percentage);
    
    event ProposedFeeToken(address indexed token, address indexed priceFeed, bool removal, uint allowedAfterTime);
    event FeeTokenAdded(address indexed token, address indexed priceFeed);
    event FeeTokenRemoved(address indexed token);


    /****************************************************************************
     * Initialization Config Settings
     *****************************************************************************/
    //mint rate bucket
    struct MintRateRangeConfig {
        uint16 minMMVolume;
        uint16 maxMMVolume;
        uint rate;
    }

    //fee token and its associated chainlink feed
    struct FeeTokenConfig {
        address[] feeTokens;
        address[] priceFeeds;
    }

    //initialize config to intialize storage
    struct RevshareConfig {

        //the address of the wrapped native token
        address wrappedNativeToken;

        //starting volume needed to mint a single DXBL token. This increases
        //as we get closer to reaching the daily goal
        uint baseMintThreshold;

        //initial rate ranges to apply
        MintRateRangeConfig[] rateRanges;

        //set of fee token/price feed pairs to initialize with
        FeeTokenConfig feeTokenConfig;

        //multi-sig settings
        LibMultiSig.MultiSigConfig multiSigConfig;
    }

    /****************************************************************************
     * Stored Settings
     *****************************************************************************/
    //stored mint rate range
    struct MintRateRange {
        uint16 minMMVolume;
        uint16 maxMMVolume;
        uint rate;
        uint index;
    }

    //price feed for a fee token
    struct PriceFeed {
        IPriceFeed feed;
        uint8 decimals;
    }

    /**
     * Primary storage for revshare vault
     */
    struct RevshareStorage {

        //revshare pool creator
        address creator;

        //token address
        IDXBL dxbl;

        //dexible settlement
        address dexible;

        //wrapped native asset address for gas computation
        address wrappedNativeToken;

        //time before changes take effect
        uint32 timelockSeconds;

        //base volume needed to mint a single DXBL token. This increases
        //as we get closer to reaching the daily goal
        uint baseMintThreshold;

        //current daily volume adjusted each hour
        uint currentVolume;

        //to compute what hourly slots to deduct from 24hr window
        uint lastTradeTimestamp;

        //all known fee tokens. Some may be inactive
        IERC20[] feeTokens;

        //the current volume range we're operating in for mint rate
        MintRateRange currentMintRate;

        //The ranges of 24hr volume and their percentage-per-MM increase to 
        //mint a single token
        MintRateRange[] mintRateRanges;

        //hourly volume totals to adjust current volume every 24 hr slot
        uint[24] hourlyVolume;

        //fee token decimals
        mapping(address => uint8) tokenDecimals;

        //all allowed fee tokens mapped to their price feed address
        mapping(address => PriceFeed) allowedFeeTokens;
    }



    /****************************************************************************
     * Initialization functions
     *****************************************************************************/
    function initialize(RevshareStorage storage rs,
            RevshareConfig calldata config) public {

        require(rs.creator == address(0), "Already initialized");
        require(config.baseMintThreshold > 0, "Must provide a base mint threshold");
        require(config.wrappedNativeToken != address(0), "Invalid wrapped native token");

        rs.creator = msg.sender;
        rs.baseMintThreshold = config.baseMintThreshold;
        rs.wrappedNativeToken = config.wrappedNativeToken;
        
        _initializeMintRates(rs, config.rateRanges);
        _initializeFeeTokens(rs, config.feeTokenConfig);
    }


    /**
     * Initialize configured fee tokens
     */
    function _initializeFeeTokens(RevshareStorage storage rs, FeeTokenConfig calldata config) internal {
        require(config.feeTokens.length > 0 && config.feeTokens.length == config.priceFeeds.length, "Must provide equal-length arrays for fee tokens and price feeds");

        for(uint i=0;i<config.feeTokens.length;++i) {
            address token = config.feeTokens[i];
            address feed = config.priceFeeds[i];
            rs.feeTokens.push(IERC20(token));
            rs.tokenDecimals[token] = IERC20Metadata(token).decimals();
            rs.allowedFeeTokens[token] = PriceFeed({
                feed: IPriceFeed(feed),
                decimals: IPriceFeed(feed).decimals()
            });
        }
        require(rs.allowedFeeTokens[rs.wrappedNativeToken].decimals > 0, "Wrapped native asset must be a valid fee token");
    }


    /**
     * Initialize the mint rate buckets
     */
    function _initializeMintRates(RevshareStorage storage rs, MintRateRangeConfig[] calldata ranges) internal {
        require(rs.mintRateRanges.length == 0, "Already initialized rate ranges");
        for(uint i=0;i<ranges.length;++i) {
            MintRateRangeConfig calldata rc = ranges[i];
            require(rc.maxMMVolume > 0, "Max MM Volume must be > 0");
            require(rc.rate > 0, "Rate must be > 0");
            rs.mintRateRanges.push(MintRateRange({
                minMMVolume: rc.minMMVolume,
                maxMMVolume: rc.maxMMVolume,
                rate: rc.rate,
                index: i
            }));
        }
        rs.currentMintRate = rs.mintRateRanges[0];
    }

    /*************************************************************************
    * DISCOUNT CHANGES
    **************************************************************************/

    /**
     * This is really jsut a delegate to the DXBL token to set the discount rate for 
     * the token. Since the DXBL token has no timelock on its settings, it allows the
     * revshare vault to make the discount rate change only. This allows us to leverage 
     * the multi-sig timelock feature of the vault to control the discount rate of token.
     */
    function setDiscountRateBps(RevshareStorage storage rs, uint32 rate) public {
        //only minter (revshare) is allowed to set the discount rate on token contract
        rs.dxbl.setDiscountRate(rate);
        emit DiscountChanged(rate);
    }
    //END DISCOUNT CHANGES____________________________________________________________________________



    /*************************************************************************
    * FEE TOKEN CHANGES
    **************************************************************************/
    /** 
     * Adjusts fee tokens allowed by the protocol. Changes are a REPLACEMENT of fee 
     * token configuration
     */
    function setFeeTokens(RevshareStorage storage rs, FeeTokenConfig calldata details) public {
        require(details.feeTokens.length > 0 && details.feeTokens.length == details.priceFeeds.length, "Must provide equal-length arrays for fee tokens and price feeds");

        /**
         * NOTE: it's impractical right now to remove fee tokens. We may need to upgrade
         * contract logic to handle some type of deprecation period for expiring fee tokens
         * that will be removed in the future. This would allow withdraws on the token
         * but not new deposits, giving the community an opportunity to withdraw. But chances
         * are, if it's being deprecated, it's probably because there's no liquidity or a problem
         * with it.
         */
        IERC20[] memory existing = rs.feeTokens;
        for(uint i=0;i<existing.length;i = _incr(i)) {
            //if we've removed a fee token that was active
            if(!_contains(details.feeTokens, address(existing[i]))) {
                console.log("Fee token has balance", address(existing[i]));
                //we have to make sure the vault doesn't have a balance
                require(existing[i].balanceOf(address(this)) == 0, "Attempting to remove fee token that has non-zero balance");
            }
            
            delete rs.allowedFeeTokens[address(existing[i])];
            delete rs.tokenDecimals[address(existing[i])];
            emit FeeTokenRemoved(address(existing[i]));
        }

        delete rs.feeTokens;
        IERC20[] memory newTokens = new IERC20[](details.feeTokens.length);
        //current active token count in memory so that we're not updating storage in a loop
        for(uint i=0;i<details.feeTokens.length;++i) {
            address ft = details.feeTokens[i];
            address pf = details.priceFeeds[i];
            //store price feed info including cached decimal count
            rs.allowedFeeTokens[ft] = PriceFeed({
                feed: IPriceFeed(pf),
                decimals: IPriceFeed(pf).decimals()
            });
            //add fee token to array
            newTokens[i] = IERC20(ft);

            //cache decimals for tken
            rs.tokenDecimals[ft] = IERC20Metadata(ft).decimals();
            emit FeeTokenAdded(ft, pf);
        }
        rs.feeTokens = newTokens;
    }
    //END FEE TOKEN CHANGES____________________________________________________________________________



    /*************************************************************************
    * MINT RATE CHANGES
    **************************************************************************/

    /**
     * Set the mint rate buckets that control how much volume is required to mint a single
     * DXBL token. This is a REPLACEMENT to the existing rates. Make sure to account for 
     * all ranges.
     */
    function setMintRates(RevshareStorage storage rs, MintRateRangeConfig[] calldata changes) public {
        
        //replace existing ranges
        delete rs.mintRateRanges;

        //we're going to possible change the current mint rate depending on new buckets
        MintRateRange memory newCurrent = rs.currentMintRate;

        //the current 24hr volume, normalized in millions
        uint16 normalizedVolume = uint16(rs.currentVolume / LibConstants.MM_VOLUME);
        
        for(uint i=0;i<changes.length;++i) {
            MintRateRangeConfig calldata change = changes[i];
            MintRateRange memory newOne = MintRateRange({
                    minMMVolume: change.minMMVolume,
                    maxMMVolume: change.maxMMVolume,
                    rate: change.rate,
                    index: i
            });
            rs.mintRateRanges.push(newOne);
            //if the new change is in range of current volume level, it becomes the new rate
            if(change.minMMVolume <= normalizedVolume && normalizedVolume < change.maxMMVolume) {
                newCurrent = newOne;
            }
            emit MintRateChange(change.minMMVolume, change.maxMMVolume, change.rate);
        }
        rs.currentMintRate = newCurrent;
    }
    //END MINT RATE CHANGES____________________________________________________________________________

    function _incr(uint i) private pure returns (uint) {
        unchecked { return i + 1; }
    }

    function _contains(address[] memory ar, address tgt) private pure returns (bool) {
        for(uint i=0;i<ar.length;i=_incr(i)) {
            if(ar[i] == tgt) {
                return true;
            }
        }
        return false;
    }
    
}
