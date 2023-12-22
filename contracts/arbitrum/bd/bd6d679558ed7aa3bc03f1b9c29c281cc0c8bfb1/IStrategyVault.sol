// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IStrategyVault {

    function depositToken() external view returns (address);
    function strategies(uint) external view returns (address);
    function strategyAllocation(uint) external view returns (uint256);
    function previousHarvestTimeStamp() external view returns (uint);
    function waterMark() external view returns (uint);
    function performanceFee() external view returns (uint);
    function adminFee() external view returns (uint);
    function withdrawalFee() external view returns (uint);
    function governanceFee() external view returns (uint);
    function deposited(address _strategy) external view returns (uint);
    function withdrawn(address _strategy) external view returns (uint);
    function numPositions() external view returns (uint);
    function maxStrategies() external view returns (uint);
    function maxFee() external view returns (uint);


    // User Actions
    function depositOtherToken(address token, uint256 _amount, uint256 _slippage) external payable;
    function deposit(uint256 _amount) external payable;
    // function depositAll() external;
    function withdraw(uint256 _shares) external;
    function withdrawAll() external;

    // Governance Actions
    function setFees(uint performance, uint admin, uint withdrawal) external;
    function setGovernanceFee(uint _governanceFee) external;
    function setStrategiesAndAllocations(address[] memory _strategies, uint256[] memory _strategiesAllocation) external;
    function migrateStrategy(address _oldAddress, address _newAddress) external;
    function resetStrategyPnl(address _strategy) external;

    // View Functions
    function version() external pure returns (string memory);
    function getStrategies() external view returns (address[] memory strats);
    function getStrategyAllocations() external view returns (uint[] memory allocations);
    function getPricePerFullShare() external view returns (uint256);
    function getPricePerFullShareOptimized() external returns (uint256);
    function getWithdrawable(address user) external view returns (uint);
    function balance() external view returns (uint256);
    function balanceOptimized() external returns (uint256);
    function vaultCapacity() external view returns (uint depositable, uint tvl, uint capacity);
    function balanceOfWithRewards(address _user) external view returns (uint256 userBalance);
}
