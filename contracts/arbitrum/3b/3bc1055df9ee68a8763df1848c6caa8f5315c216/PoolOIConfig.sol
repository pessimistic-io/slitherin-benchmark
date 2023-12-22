pragma solidity 0.8.4;

import "./Interfaces.sol";
import "./Ownable.sol";

contract PoolOIConfig is Ownable {
    uint256 public _maxPoolOI;
    IPoolOIStorage public _poolOIStorage;

    constructor(uint256 maxPoolOI, IPoolOIStorage poolOIStorage) {
        _maxPoolOI = maxPoolOI;
        _poolOIStorage = poolOIStorage;
    }

    function setMaxPoolOI(uint256 maxPoolOI) external onlyOwner {
        _maxPoolOI = maxPoolOI;
    }

    function getMaxPoolOI() external view returns (uint256) {
        uint256 currentPoolOI = _poolOIStorage.totalPoolOI();
        if (currentPoolOI >= _maxPoolOI) {
            return 0;
        } else {
            return _maxPoolOI - currentPoolOI;
        }
    }

    function getPoolOICap() external view returns (uint256) {
        return _maxPoolOI;
    }
}

