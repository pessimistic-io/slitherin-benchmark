// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./ILBPair.sol";

interface ILBFactory {
    struct LBPairInformation {
        uint16 binStep;
        ILBPair LBPair;
        bool createdByOwner;
        bool ignoredForRouting;
    }

    function getLBPairInformation(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 binStep
    )
        external
        view
        returns (LBPairInformation memory lbPairInformation);
}

