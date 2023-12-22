// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

interface IMultiFeeDistribution {
    function exit(bool claimRewards) external;

    function stake(
        uint256 amount,
        address onBehalfOf,
        uint256 typeIndex
    ) external;

    function getPriceProvider() external view returns (address);

    function autocompoundEnabled(address user) external view returns (bool);

    function defaultLockIndex(address _user) external view returns (uint256);

    function autoRelockDisabled(address user) external view returns (bool);

    function totalBalance(address user) external view returns (uint256);

    function zapVestingToLp(address _address) external returns (uint256);

    function withdrawExpiredLocksFor(
        address _address
    ) external returns (uint256);

    function setDefaultRelockTypeIndex(uint256 _index) external;

    function daoTreasury() external view returns (address);

    function stakingToken() external view returns (address);

    function claimFromConverter(address) external;

    function mint(address user, uint256 amount, bool withPenalty) external;

    function withdraw(uint256 amount) external;

    function getAllRewards() external;

    function relock() external;

    function setRelock(bool _status) external;
}

