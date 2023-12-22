//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;


import "./LibStorage.sol";
import "./LibRevshare.sol";
import "./LibConstants.sol";
import "./MultiSigConfigurable.sol";

import "./IERC20Metadata.sol";

/**
 * Configuration settings for RevshareVault. This applies multi-sig functionality by extending
 * base multi-sig contract.
 */
abstract contract ConfigurableRS is MultiSigConfigurable {

    using LibRevshare for LibRevshare.RevshareStorage;

    /**
     * Initialize revshare vault settings. This can only be called once after deployment of
     * proxy.
     */
    function initialize(LibRevshare.RevshareConfig calldata config) public {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();

        //init revshare settings
        rs.initialize(config);

        //init multi-sig settings
        super.initializeMSConfigurable(config.multiSigConfig);
    }

    /*************************************************************************
    * Set the DXBL token contract. One time only
    **************************************************************************/
    function setDXBL(address token) public {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        require(token != address(0), "Invalid DXBL token address");
        require(address(rs.dxbl) == address(0), "Already initialized DXBL address");
        rs.dxbl = IDXBL(token);
    }

    /*************************************************************************
    * Set the Dexible contract. One time only
    **************************************************************************/
    function setDexible(address dex) public {
        LibRevshare.RevshareStorage storage rs = LibStorage.getRevshareStorage();
        require(rs.dexible == address(0), "Already initialized Dexible address");
        require(dex != address(0), "Invalid dexible address");
        rs.dexible = dex;
    }

    /*************************************************************************
    * DISCOUNT CHANGES
    **************************************************************************/

    /**
     * Set a new discount rate for DXBL tokens but only after multi-sig approval and timelock
     */
    function setDiscountRateBps(uint32 bps) public afterApproval(this.setDiscountRateBps.selector) {
        LibStorage.getRevshareStorage().setDiscountRateBps(bps);
    }
    //END DISCOUNT CHANGES____________________________________________________________________________

    /*************************************************************************
    * FEE TOKEN CHANGES
    **************************************************************************/

    /**
     * Set the fee tokens for the vault but only after approval and timelock. This REPLACES
     * all allowed fee tokens.
     */
    function setFeeTokens(LibRevshare.FeeTokenConfig calldata details) public afterApproval(this.setFeeTokens.selector) {
        LibStorage.getRevshareStorage().setFeeTokens(details);
    }
    //END FEE TOKEN CHANGES____________________________________________________________________________


    /*************************************************************************
    * MINT RATE CHANGES
    **************************************************************************/
    /**
     * Set the mint rate buckets that determine minimum volume for a single DXBL token
     */
    function setMintRates(LibRevshare.MintRateRangeConfig[] calldata ranges) public afterApproval(this.setMintRates.selector) {
        LibStorage.getRevshareStorage().setMintRates(ranges);
    }
    //END MINT RATE CHANGES____________________________________________________________________________

}
