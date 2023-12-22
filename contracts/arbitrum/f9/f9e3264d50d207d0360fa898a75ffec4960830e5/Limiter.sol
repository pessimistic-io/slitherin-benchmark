// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LinkedListLibrary, LinkedList} from "./LinkedList.sol";

using LinkedListLibrary for LinkedList;

struct Transfer {
    int amount;
    uint timestamp;
}

struct Limiter {
    uint interval;
    uint limit;
    LinkedList _keys;
    mapping(uint128 => Transfer) _transfers;
}

using LimiterLibrary for Limiter;

library LimiterLibrary {
    function transfers(Limiter storage self) internal view returns (Transfer[] memory) {
        Transfer[] memory _transfers = new Transfer[](self._keys.length());
        uint index = 0;
        uint128 key = self._keys.first();
        while (key != 0) {
            _transfers[index] = self._transfers[key];
            key = self._keys.next(key);
            index++;
        }
        return _transfers;
    }

    function temporarilyIncreaseLimit(Limiter storage self, uint _limitIncrease) internal {
        _addUncheckedTransfer(self, -int(_limitIncrease));
    }

    function temporarilyDecreaseLimit(Limiter storage self, uint _limitDecrease) internal {
        _addUncheckedTransfer(self, int(_limitDecrease));
    }

    function remainingLimit(Limiter storage self) internal view returns (int) {
        return int(self.limit) - self.usedLimit();
    }

    function usedLimit(Limiter storage self) internal view returns (int) {
        int _sum = 0;
        uint128 key = self._keys.first();
        while (key != 0) {
            if (self._transfers[key].timestamp > block.timestamp - self.interval) {
                _sum += self._transfers[key].amount;
            }
            key = self._keys.next(key);
        }
        return _sum;
    }

    function _filterTransfers(Limiter storage self) private {
        uint128 key = self._keys.first();
        while (key != 0) {
            if (self._transfers[key].timestamp > block.timestamp - self.interval) {
                break;
            }
            delete self._transfers[key];
            key = self._keys.remove(key);
        }
    }

    function _addTransferNode(Limiter storage self, int _amount) private {
        uint128 key = self._keys.generate();
        self._transfers[key] = Transfer({amount: int(_amount), timestamp: block.timestamp});
    }

    function _addUncheckedTransfer(Limiter storage self, int _amount) private {
        _filterTransfers(self);
        _addTransferNode(self, _amount);
    }

    function addTransfer(Limiter storage self, uint _amount) internal returns (bool) {
        _addUncheckedTransfer(self, int(_amount));
        return self.remainingLimit() >= 0;
    }
}

