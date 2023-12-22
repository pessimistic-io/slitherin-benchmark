// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./Counters.sol";

contract WaveMapping is Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private waveHoldersCount;

    mapping(address => bool) private waveHoldersMap;

    function includeToWaveMap(address account) external onlyOwner {
        if (waveHoldersMap[account] == false) {
            waveHoldersMap[account] = true;
            waveHoldersCount.increment();
            }
    }

    function excludeToWaveMap(address account) external onlyOwner {
        if (waveHoldersMap[account] == true) {
            waveHoldersMap[account] = false;
            waveHoldersCount.decrement();
            }
    }

    function setIncludeToWaveMap(address _address, bool _isIncludeToWaveMap) external onlyOwner {
        waveHoldersMap[_address] = _isIncludeToWaveMap;
    }

    function isPartOfWave(address _address) external view returns (bool) {
        return waveHoldersMap[_address];
    }

    function getNumberOfWaveHolders() external view returns (uint256) {
        return waveHoldersCount.current();
    }

}
