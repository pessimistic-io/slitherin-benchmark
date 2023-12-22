// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGToken {
    function manager() external view returns (address);

    function admin() external view returns (address);

    function currentEpoch() external view returns (uint);

    function currentEpochStart() external view returns (uint);

    function currentEpochPositiveOpenPnl() external view returns (uint);

    function updateAccPnlPerTokenUsed(uint prevPositiveOpenPnl, uint newPositiveOpenPnl) external returns (uint);

    struct LockedDeposit {
        address owner;
        uint shares; // 1e18
        uint assetsDeposited; // 1e18
        uint assetsDiscount; // 1e18
        uint atTimestamp; // timestamp
        uint lockDuration; // timestamp
    }

    function getLockedDeposit(uint depositId) external view returns (LockedDeposit memory);

    function sendAssets(uint assets, address receiver) external;

    function receiveAssets(uint assets, address user) external;

    function distributeReward(uint assets) external;

    function currentBalanceDai() external view returns (uint);

    function tvl() external view returns (uint);

    function marketCap() external view returns (uint);

    function getPendingAccBlockWeightedMarketCap(uint currentBlock) external view returns (uint);
}

