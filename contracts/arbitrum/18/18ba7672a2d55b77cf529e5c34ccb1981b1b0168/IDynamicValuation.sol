// SPDX-License-Identifier: MIT



pragma solidity >=0.8.0;

interface IDynamicValuation {
    struct OracleData {
        address dataFeed;
        uint8 dataFeedDecimals;
        uint32 heartbeat;
        uint8 tokenDecimals;
    }

    error WrongAddress();
    error NotUniqiueValues();

    error BadPrice();
    error TooOldPrice();
    error NoOracleForToken(address token);

    error NoObserver();

    error SequencerDown();
    error GracePeriodNotOver();

    event SetChainlinkOracle(address indexed token, OracleData oracleData);

    event SetGmxObserver(address indexed newGmxObserver);

    function factory() external view returns (address);

    function decimals() external view returns (uint8);

    function sequencerUptimeFeed() external view returns (address);

    function gmxObserver() external view returns (address);

    function initialize(
        address _factory,
        address _sequencerUptimeFeed,
        address _gmxObserver
    ) external;

    function setChainlinkPriceFeed(
        address token,
        address priceFeed,
        uint32 heartbeat
    ) external;

    function setGmxObserver(address newValue) external;

    function chainlinkOracles(
        address token
    ) external view returns (OracleData memory);

    function getOraclePrice(
        address token,
        uint256 amount
    ) external view returns (uint256);

    function getDynamicValuation(
        address addr
    ) external view returns (uint256 valuation);
}

