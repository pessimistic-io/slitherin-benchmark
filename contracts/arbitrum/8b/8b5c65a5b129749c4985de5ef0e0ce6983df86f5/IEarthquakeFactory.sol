pragma solidity 0.8.18;

interface IEarthquakeFactory {
    function asset(uint256 _marketId) external view returns (address asset);

    function getVaults(uint256) external view returns (address[] memory);
}

