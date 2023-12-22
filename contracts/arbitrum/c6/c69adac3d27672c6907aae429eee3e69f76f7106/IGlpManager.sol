pragma solidity 0.8.17;

interface IGlpManager {
    function getPrice(bool _maximise) external view returns (uint256);

    function getAum(bool maximise) external view returns (uint256);

    function aumAddition() external view returns (uint256);

    function aumDeduction() external view returns (uint256);

    function shortsTracker() external view returns (address);

    function shortsTrackerAveragePriceWeight() external view returns (uint256);
}

