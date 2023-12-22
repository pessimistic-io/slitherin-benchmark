pragma solidity >=0.5;

interface ITarotSolidlyPriceOracle {
    function MIN_T() external pure returns (uint32);

    function getReserveInfo(address pair)
        external
        view
        returns (
            uint256 reserve0CumulativeSlotA,
            uint256 reserve1CumulativeSlotA,
            uint256 reserve0CumulativeSlotB,
            uint256 reserve1CumulativeSlotB,
            uint32 lastUpdateSlotA,
            uint32 lastUpdateSlotB,
            bool latestIsSlotA,
            bool initialized
        );

    function initialize(address pair) external;

    function getResult(address pair) external returns (uint224 price, uint32 T);

    function getBlockTimestamp() external view returns (uint32);

    event ReserveInfoUpdate(address indexed pair, uint256 reserve0Cumulative, uint256 reserve1Cumulative, uint32 blockTimestamp, bool latestIsSlotA);
}

