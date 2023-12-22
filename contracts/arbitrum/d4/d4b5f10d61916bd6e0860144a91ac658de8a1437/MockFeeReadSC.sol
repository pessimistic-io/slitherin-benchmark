// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

contract MockFeeReadSC {
    struct GetFeesParam {
        uint256 srcChainID;
        uint256 destChainID;
    }

    struct GetFeesReturn {
        uint256 contractFee;
        uint256 agentFee;
    }

    function getFee(
        GetFeesParam memory /* param */
    ) external pure returns (GetFeesReturn memory fee) {
        return GetFeesReturn(0.01 ether, 0);
    }
}

