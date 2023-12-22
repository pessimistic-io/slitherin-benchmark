// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

library TakingFee {
    type Data is uint256;

    uint256 internal constant _TAKING_FEE_BASE = 1e9;
    uint256 private constant _TAKING_FEE_RATIO_OFFSET = 160;

    function enabled(Data self) internal pure returns (bool) {
        return ratio(self) != 0;
    }

    function ratio(Data self) internal pure returns (uint256) {
        return uint32(Data.unwrap(self) >> _TAKING_FEE_RATIO_OFFSET);
    }

    function receiver(Data self) internal pure returns (address) {
        return address(uint160(Data.unwrap(self)));
    }
}

