// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/***
 * @title Max Heap library
 * @notice Data structure used by the AuctionRaffle contract to store top bids.
 * It allows retrieving them in descending order on auction settlement.
 * @author TrueFi Engineering team
 */
library MaxHeap {
    function insert(uint256[] storage heap, uint256 key) internal {
        uint256 index = heap.length;
        heap.push(key);
        bubbleUp(heap, index, key);
    }

    function increaseKey(
        uint256[] storage heap,
        uint256 oldValue,
        uint256 newValue
    ) internal {
        uint256 index = findKey(heap, oldValue);
        increaseKeyAt(heap, index, newValue);
    }

    function increaseKeyAt(
        uint256[] storage heap,
        uint256 index,
        uint256 newValue
    ) internal {
        require(newValue > heap[index], "MaxHeap: new value must be bigger than old value");
        heap[index] = newValue;
        bubbleUp(heap, index, newValue);
    }

    function removeMax(uint256[] storage heap) internal returns (uint256 max) {
        require(heap.length > 0, "MaxHeap: cannot remove max element from empty heap");
        max = heap[0];
        heap[0] = heap[heap.length - 1];
        heap.pop();

        uint256 index = 0;
        while (true) {
            uint256 l = left(index);
            uint256 r = right(index);
            uint256 biggest = index;

            if (l < heap.length && heap[l] > heap[index]) {
                biggest = l;
            }
            if (r < heap.length && heap[r] > heap[biggest]) {
                biggest = r;
            }
            if (biggest == index) {
                break;
            }
            (heap[index], heap[biggest]) = (heap[biggest], heap[index]);
            index = biggest;
        }
        return max;
    }

    function bubbleUp(
        uint256[] storage heap,
        uint256 index,
        uint256 key
    ) internal {
        while (index > 0 && heap[parent(index)] < heap[index]) {
            (heap[parent(index)], heap[index]) = (key, heap[parent(index)]);
            index = parent(index);
        }
    }

    function findKey(uint256[] storage heap, uint256 value) internal view returns (uint256) {
        for (uint256 i = 0; i < heap.length; ++i) {
            if (heap[i] == value) {
                return i;
            }
        }
        revert("MaxHeap: key with given value not found");
    }

    function findMin(uint256[] storage heap) internal view returns (uint256 index, uint256 min) {
        uint256 heapLength = heap.length;
        require(heapLength > 0, "MaxHeap: cannot find minimum element on empty heap");

        uint256 n = heapLength / 2;
        min = heap[n];
        index = n;

        for (uint256 i = n + 1; i < heapLength; ++i) {
            uint256 element = heap[i];
            if (element < min) {
                min = element;
                index = i;
            }
        }
    }

    function parent(uint256 index) internal pure returns (uint256) {
        return (index - 1) / 2;
    }

    function left(uint256 index) internal pure returns (uint256) {
        return 2 * index + 1;
    }

    function right(uint256 index) internal pure returns (uint256) {
        return 2 * index + 2;
    }
}

