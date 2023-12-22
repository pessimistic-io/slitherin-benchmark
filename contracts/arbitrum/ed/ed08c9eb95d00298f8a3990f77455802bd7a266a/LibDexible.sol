//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./IDXBL.sol";
import "./LibMultiSig.sol";
import "./IRevshareVault.sol";
import "./LibConstants.sol";

/**
 * Primary library for Dexible contract ops and storage. All functions are protected by
 * modifiers in Dexible contract except for initialize.
 */
library LibDexible {

    event ChangedRevshareVault(address indexed old, address indexed newRevshare);
    event ChangedRevshareSplit(uint8 split);
    event ChangedBpsRates(uint32 stdRate, uint32 minRate);

    //used to change revshare vault address
    struct RevshareChange {
        address revshare;
        uint allowedAfterTime;
    }

    //used to change the revshare split percentage
    struct SplitChange {
        uint8 split;
        uint allowedAfterTime;
    }

    //used to changes the std and min bps fees
    struct BpsFeeChange {
        uint16 stdBps;
        uint16 minBps;
    }

    //primary initialization config settings
    struct DexibleConfig {
        
        //percent to split to revshare
        uint8 revshareSplitRatio;

        //std bps rate to apply to all trades
        uint16 stdBpsRate;

        //minimum bps rate regardless of tokens held
        uint16 minBpsRate;

        //the revshare vault contract
        address revshareManager;

        //treasury for Dexible team
        address treasury;

        //the DXBL token address
        address dxblToken;

        //address of account to assign roles
        address roleManager;

        //minimum flat fee to charge if bps fee is too low
        uint112 minFeeUSD;

        //config info for multisig settings
        LibMultiSig.MultiSigConfig multiSigConfig;
    }

    /**
     * This is the primary storage for Dexible operations.
     */
    struct DexibleStorage {
        //how much of fee goes to revshare vault
        uint8 revshareSplitRatio;
         
        //standard bps fee rate
        uint16 stdBpsRate;

        //minimum fee applied regardless of tokens held
        uint16 minBpsRate;

        //min fee to charge if bps too low
        uint112 minFeeUSD;
        
        //revshare vault address
        address revshareManager;

        //treasury address
        address treasury;

        //the DXBL token
        IDXBL dxblToken;
    }

    /**
     * Initialize storage settings. This can only be called once after deployment of proxy.
     */
    function initialize(DexibleStorage storage ds, DexibleConfig calldata config) public {
        require(ds.treasury == address(0), "Dexible was already initialized");

        require(config.revshareManager != address(0), "Invalid RevshareVault address");
        require(config.treasury != address(0), "Invalid treasury");
        require(config.dxblToken != address(0), "Invalid DXBL token address");
        require(config.revshareSplitRatio > 0, "Invalid revshare split ratio");
        require(config.stdBpsRate > 0, "Must provide a standard bps fee rate");
        require(config.minBpsRate > 0, "minBpsRate is required");
        require(config.minBpsRate < config.stdBpsRate, "Min bps rate must be less than std");

        ds.revshareSplitRatio = config.revshareSplitRatio;
        ds.revshareManager = config.revshareManager;
        ds.treasury = config.treasury;
        ds.dxblToken = IDXBL(config.dxblToken);
        ds.stdBpsRate = config.stdBpsRate;
        ds.minBpsRate = config.minBpsRate;
        ds.minFeeUSD = config.minFeeUSD; //can be 0
    }

    /**
     * Set the stored revshare vault.
     */
    function setRevshareVault(DexibleStorage storage ds, address t) public {
        require(t != address(0), "Invalid revshare vault");
        emit ChangedRevshareVault(ds.revshareManager, t);
        ds.revshareManager = t;
    }

    /**
     * Set the revshare split percentage
     */
    function setRevshareSplit(DexibleStorage storage ds, uint8 split) public {
        require(split > 0, "Invalid split");
        ds.revshareSplitRatio = split;
        emit ChangedRevshareSplit(split);
    }

    /**
     * Set new std/min bps rates
     */
    function setNewBps(DexibleStorage storage rs, BpsFeeChange calldata changes) public {
        require(changes.minBps > 0,"Invalid min bps fee");
        require(changes.stdBps > 0, "Invalid std bps fee");
        rs.minBpsRate = changes.minBps;
        rs.stdBpsRate = changes.stdBps;
        emit ChangedBpsRates(changes.stdBps, changes.minBps);
    }

    

}
