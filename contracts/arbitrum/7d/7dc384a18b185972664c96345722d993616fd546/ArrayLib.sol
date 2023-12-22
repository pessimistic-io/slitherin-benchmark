// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

library ArrayLib {
    function indexOf(uint[] storage self, uint value) public view returns (int) {
        for (uint i = 0; i < self.length; i++)if (self[i] == value) return int(i);
        return -1;
    }
    function removeElement(uint256[] storage _array, uint256 _element) public {
        for (uint256 i; i<_array.length; i++) {
            if (_array[i] == _element) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
        }
    }
}
