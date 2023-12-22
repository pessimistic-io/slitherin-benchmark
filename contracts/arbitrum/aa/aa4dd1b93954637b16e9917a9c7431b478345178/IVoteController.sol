// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IVoteController {
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }

    event PoolAdded(address pool);
    event PoolToggled(address indexed pool, bool isDisabled);
    event Voted(
        address indexed account,
        uint256 oldAmount,
        uint256 oldUnlockTime,
        uint256[] oldWeights,
        uint256 amount,
        uint256 unlockTime,
        uint256[] weights
    );

    // mapping(address => mapping(address => uint256)) public override userWeights;

    function userWeights(address account, address pool) external view returns (uint256);

    function getPools() external view returns (address[] memory);

    function addPool(address newPool) external;

    function togglePool(uint256 index) external;

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function sumAtTimestamp(address pool, uint256 timestamp) external view returns (uint256);

    function count(uint256 timestamp) external view returns (uint256[] memory weights, address[] memory pools);

    function cast(uint256[] memory weights) external;

    function syncWithLocker(address account) external;
}

