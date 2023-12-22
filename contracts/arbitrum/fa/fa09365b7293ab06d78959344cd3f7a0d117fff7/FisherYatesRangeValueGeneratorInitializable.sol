//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./IRangeValueGenerator.sol";
import "./FisherYatesRangeValueGenerator.sol";
import "./ToInitialize.sol";
import "./Ownable.sol";

contract FisherYatesRangeValueGeneratorInitializable is
    FisherYatesRangeValueGenerator,
    ToInitialize,
    Ownable
{
    error MaxValueExceeded();
    event Initialized();

    uint256 public immutable maxValue;
    uint256 internal _lastInitialized;

    constructor(address owner_, uint256 maxValue_) {
        maxValue = maxValue_;
        _lastIndex = maxValue;
        _transferOwnership(owner_);
    }

    function addChunk(uint256 amount) external onlyOwner {
        if (_lastInitialized + amount > maxValue) {
            revert MaxValueExceeded();
        }
        for (uint i = 1; i <= amount; ++i) {
            _numbers.push(_lastInitialized + i);
        }

        _lastInitialized += amount;

        if (_lastInitialized == maxValue) {
            initialized = true;
            emit Initialized();
        }
    }

    function rand() internal override isInitialized returns (uint256) {
        return super.rand();
    }

    function max() external view override returns (uint256) {
        return maxValue;
    }
}

