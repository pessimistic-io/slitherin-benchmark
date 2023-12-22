// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ICommonFacet.sol";
import "./IPermissionsFacet.sol";

interface IDutchAuctionFacet {
    struct Storage {
        uint32 duration;
        uint256 startCoefficientX96;
        uint256 endCoefficientX96;
        uint256 startTimestamp;
        bool isStarted;
        address strategy;
    }

    function checkTvlAfterRebalance(uint256 tvlBefore, uint256 tvlAfter) external returns (bool);

    function updateAuctionParams(
        uint32 duration,
        uint256 startCoefficientX96,
        uint256 endCoefficientX96,
        address strategy
    ) external;

    function auctionParams()
        external
        pure
        returns (
            uint256 startCoefficientX96,
            uint256 endCoefficientX96,
            uint32 duration,
            uint256 startTimestamp,
            bool isStarted,
            address strategy
        );

    function finishAuction() external;

    function startAuction() external;

    function stopAuction() external;
}

