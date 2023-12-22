//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./IRangeValueGenerator.sol";

abstract contract FisherYatesRangeValueGenerator is IRangeValueGenerator {
    uint256 constant minValue = 1;

    uint256[] internal _numbers;
    uint256 internal _lastIndex;

    function rand() internal virtual returns (uint256) {
        if (_lastIndex == 0) {
            revert AllValuesGenerated();
        }
        uint256 randomIndex = uint256(
            keccak256(
                abi.encode(
                    block.timestamp,
                    _lastIndex,
                    block.coinbase,
                    msg.sender,
                    msg.sender.balance,
                    block.prevrandao
                )
            )
        ) % _lastIndex;
        uint256 randomNumber = _numbers[randomIndex];

        _numbers[randomIndex] = _numbers[_lastIndex - 1];
        _lastIndex--;

        return randomNumber;
    }

    function min() external pure override returns (uint256) {
        return minValue;
    }
}

