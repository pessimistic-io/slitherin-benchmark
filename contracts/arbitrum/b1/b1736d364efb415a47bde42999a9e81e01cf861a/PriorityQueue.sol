// SPDX-License-Identifier: BUSL-1.1

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity 0.8.13;

library PriorityQueue {
    struct Heap {
        mapping(uint256 => uint256) next;
        mapping(uint256 => uint256) prev;
        mapping(uint256 => uint256) values;
        uint256 size;
    }

    function enqueue(
        PriorityQueue.Heap storage self,
        uint256 key,
        uint256 value
    ) internal {
        require(key != 0 && value != 0, "!ZV");
        if (!contains(self, key)) {
            if (headKey(self) > key) {
                _prepend(self, key);
            } else if (tailKey(self) < key) {
                _append(self, key);
            } else {
                uint256 i = tailKey(self);
                for (; i != 0; ) {
                    i = self.prev[i];
                    if (i < key) {
                        _insert(self, i, key, self.next[i]);
                        break;
                    }
                }
                require(i != 0, "!ALG");
            }
        }
        self.values[key] += value;
    }

    function dequeue(PriorityQueue.Heap storage self)
        internal
        returns (uint256 value)
    {
        uint256 key = self.next[0];
        value = self.values[key];
        delete self.values[key];
        _remove(self, key);
    }

    function headKey(PriorityQueue.Heap storage self)
        internal
        view
        returns (uint256)
    {
        return self.next[0];
    }

    function tailKey(PriorityQueue.Heap storage self)
        internal
        view
        returns (uint256)
    {
        return self.prev[0];
    }

    function headValue(PriorityQueue.Heap storage self)
        internal
        view
        returns (uint256)
    {
        return self.values[headKey(self)];
    }

    function tailValue(PriorityQueue.Heap storage self)
        internal
        view
        returns (uint256)
    {
        return self.values[tailKey(self)];
    }

    function numBy(PriorityQueue.Heap storage self, uint256 key)
        internal
        view
        returns (uint256 num)
    {
        if (self.size != 0 && key != 0) {
            uint256 i = headKey(self);
            for (; i != 0; ) {
                if (i > key) {
                    break;
                }
                unchecked {
                    i = self.next[i];
                    num++;
                }
            }
        }
    }

    function contains(Heap storage self, uint256 key)
        internal
        view
        returns (bool)
    {
        return headKey(self) == key || self.prev[key] != 0;
    }

    function _append(Heap storage self, uint256 key) private {
        _insert(self, tailKey(self), key, 0);
    }

    function _prepend(Heap storage self, uint256 key) private {
        _insert(self, 0, key, headKey(self));
    }

    function _insert(
        Heap storage self,
        uint256 prev_,
        uint256 key,
        uint256 next_
    ) private {
        require(key != 0, "!ERR");
        self.next[prev_] = key;
        self.next[key] = next_;
        self.prev[next_] = key;
        self.prev[key] = prev_;
        self.size++;
    }

    function _remove(Heap storage self, uint256 key) private {
        require(key != 0 && contains(self, key), "!ERR");
        self.next[self.prev[key]] = self.next[key];
        self.prev[self.next[key]] = self.prev[key];
        delete self.next[key];
        delete self.prev[key];
        self.size--;
    }
}

