/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

// do we need this?
/**
 * @title Tracks configurations for dated irs markets
 */
library MarketConfiguration {
    error MarketAlreadyExists(uint128 marketId);

    struct Data {
        // todo: new market ids should be created here
        /**
         * @dev Id fo a given interest rate swap market
         */
        uint128 marketId;
        /**
         * @dev Address of the quote token.
         * @dev IRS contracts settle in the quote token
         * i.e. settlement cashflows and unrealized pnls are in quote token terms
         */
        address quoteToken;
    }

    /**
     * @dev Loads the MarketConfiguration object for the given dated irs market id
     * @param irsMarketId Id of the IRS market that we want to load the configurations for
     * @return datedIRSMarketConfig The CollateralConfiguration object.
     */
    function load(uint128 irsMarketId) internal pure returns (Data storage datedIRSMarketConfig) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.MarketConfiguration", irsMarketId));
        assembly {
            datedIRSMarketConfig.slot := s
        }
    }

    /**
     * @dev Configures a dated interest rate swap market
     * @param config The MarketConfiguration object with all the settings for the irs market being configured.
     */
    function set(Data memory config) internal {
        // todo: replace this by custom error (e.g. ZERO_ADDRESS)
        require(config.quoteToken != address(0), "Invalid Market");

        Data storage storedConfig = load(config.marketId);

        if (storedConfig.quoteToken != address(0)) {
            revert MarketAlreadyExists(config.marketId);
        }

        storedConfig.marketId = config.marketId;
        storedConfig.quoteToken = config.quoteToken;
    }
}

