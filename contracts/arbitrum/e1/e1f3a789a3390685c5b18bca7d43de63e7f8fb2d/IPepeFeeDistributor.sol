//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeFeeDistributor {
    function updateAllocations() external;

    function allocateStake() external returns (uint256);

    function allocateLock() external returns (uint256);

    function allocatePlsAccumulation() external returns (uint256);

    function allocateToAll() external;

    function updateContractAddresses(
        address _stakingContract,
        address _lockContract,
        address _plsAccumulationContract
    ) external;

    function updateContractShares(uint16 _stakeShare, uint16 _lockShare, uint16 _plsAccumulationShare) external;

    function getShareDebt(address _contract) external view returns (int256);

    function getContractShares() external view returns (uint16, uint16, uint16);

    function getContractAddresses() external view returns (address, address, address);

    function getLastBalance() external view returns (uint256);

    function getAccumulatedUsdcPerContract() external view returns (uint256);

    function getLastUpdatedTimestamp() external view returns (uint48);
}

