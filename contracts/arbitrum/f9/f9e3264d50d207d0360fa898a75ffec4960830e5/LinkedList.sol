// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

using LinkedListLibrary for LinkedList;

struct Node {
    uint128 previous;
    uint128 next;
}

struct LinkedList {
    uint128 _first;
    uint128 _last;
    uint128 _next;
    uint128 _length;
    mapping(uint128 => Node) _nodes;
}

/**
 * @dev Library for a doubly linked list that stores mono-increasing uint128 values.
 * The list is 1-indexed, with 0 used as a sentinel value.
 * Uses uint128 for storage efficiency.
 */
library LinkedListLibrary {
    /**
     * @dev Generates a new mono-increasing value, pushes it to back of the list and returns it.
     * @param self The linked list.
     */
    function generate(LinkedList storage self) internal returns (uint128) {
        self._next++;
        if (self._last != 0) {
            self._nodes[self._next].previous = self._last;
            self._nodes[self._last].next = self._next;
        } else {
            self._first = self._next;
        }
        self._last = self._next;
        self._length++;
        return self._next;
    }

    /**
     * @dev Returns the length of the list.
     * @param self The linked list.
     */
    function length(LinkedList storage self) internal view returns (uint128) {
        return self._length;
    }

    /**
     * @dev Returns the first value of the list (zero if the list is empty).
     * @param self The linked list.
     */
    function first(LinkedList storage self) internal view returns (uint128) {
        return self._first;
    }

    /**
     * @dev Returns the next value in the list following a specific value (zero if no next value).
     * @param self The linked list.
     * @param _value The value to query the next value of.
     */
    function next(LinkedList storage self, uint128 _value) internal view returns (uint128) {
        return self._nodes[_value].next;
    }

    /**
     * @dev Removes a value in the list.
     * @param self The linked list.
     * @param _value The value to remove.
     */
    function remove(LinkedList storage self, uint128 _value) internal returns (uint128) {
        Node storage node = self._nodes[_value];
        if (node.previous != 0) {
            self._nodes[node.previous].next = node.next;
        } else {
            self._first = node.next;
        }
        if (node.next != 0) {
            self._nodes[node.next].previous = node.previous;
        } else {
            self._last = node.previous;
        }
        uint128 _next = self._nodes[_value].next;
        delete self._nodes[_value];
        self._length--;
        return _next;
    }
}

