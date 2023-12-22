interface IMarketStore {
    struct Market {
        string name; // Market's full name, e.g. Bitcoin / U.S. Dollar
        string category; // crypto, fx, commodities, or indices
        address chainlinkFeed; // Price feed contract address
        uint256 maxLeverage; // No decimals
        uint256 maxDeviation; // In bps, max price difference from oracle to chainlink price
        uint256 fee; // In bps. 10 = 0.1%
        uint256 liqThreshold; // In bps
        uint256 fundingFactor; // Yearly funding rate if OI is completely skewed to one side. In bps.
        uint256 minOrderAge; // Min order age before is can be executed. In seconds
        uint256 pythMaxAge; // Max Pyth submitted price age, in seconds
        bytes32 pythFeed; // Pyth price feed id
        bool allowChainlinkExecution; // Allow anyone to execute orders with chainlink
        bool isReduceOnly; // accepts only reduce only orders
    }

    function get(string calldata market) external view returns (Market memory);
}

