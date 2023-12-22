//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Remove {
    function removeItem(
        uint256[] storage _element,
        uint256 _removeElement
    ) internal {
        uint256 i;
        for (; i < _element.length; ) {
            if (_element[i] == _removeElement) {
                _element[i] = _element[_element.length - 1];
                _element.pop();
                break;
            }

            unchecked {
                ++i;
            }
        }
    }
}

