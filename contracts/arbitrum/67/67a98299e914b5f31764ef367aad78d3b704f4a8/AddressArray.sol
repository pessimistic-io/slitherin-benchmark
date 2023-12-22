// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

library AddressArray {

    function findFirst(address[] memory self, address toFind) internal pure returns (uint) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == toFind) {
                return i;
            }
        }
        return self.length;
    }

    function exists(address[] memory self, address toFind) internal pure returns (bool) {
        for (uint i = 0; i < self.length; i++) {
            if (self[i] == toFind) {
                return true;
            }
        }
        return false;
    }

    function copy(address[] memory self) internal pure returns (address[] memory copied) {
        copied = new address[](self.length);
        for (uint i = 0; i < self.length; i++) {
            copied[i] = self[i];
        }
    }

    function sortDescending(
        address[] memory self,
        uint[] memory nums
    ) internal pure returns (address[] memory, uint[] memory) {
        uint n = nums.length;
        for (uint i = 0; i < n - 1; i++) {
            for (uint j = 0; j < n - i - 1; j++) {
                if (nums[j] < nums[j + 1]) {
                    // Swap nums[j] and nums[j + 1]
                    uint temp = nums[j];
                    nums[j] = nums[j + 1];
                    nums[j + 1] = temp;

                    // Swap self[j] and self[j + 1]
                    address tempAddress = self[j];
                    self[j] = self[j + 1];
                    self[j + 1] = tempAddress;
                }
            }
        }
        return (self, nums);
    }
}

