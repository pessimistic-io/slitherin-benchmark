// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

library GlobalDataTypes {
    struct ValidParams {
        address market;
        uint256 sizeDelta;
        bool isLong;
        uint256 globalLongSizes;
        uint256 globalShortSizes;
        uint256 userLongSizes;
        uint256 userShortSizes;
        uint256 marketLongSizes;
        uint256 marketShortSizes;
        uint256 aum;
    }
}

