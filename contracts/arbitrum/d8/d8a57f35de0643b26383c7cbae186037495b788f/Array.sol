// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


library Array {
    function remove(address[] storage haystack, address needle) internal returns (uint256) {
        uint256 assetIndex = haystack.length;
        for (uint256 i = 0; i < haystack.length; i++) {
            if (haystack[i] == needle) {
                assetIndex = i;
                break;
            }
        }
        if (assetIndex < haystack.length) {
            haystack[assetIndex] = haystack[
                haystack.length - 1
            ];
            haystack.pop();
        }
        return assetIndex;
    }

}
