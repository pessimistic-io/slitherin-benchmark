// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";

interface IStrategyVault is IERC20 {
    function deposited(address strategy) external view returns (uint);
    function withdrawn(address strategy) external view returns (uint);
    function depositToken() external view returns (address);
    function wantsArray() external view returns (address[] memory);
    function strategyAllocation() external view returns (uint256[] memory);
    function previousHarvestTimeStamp() external view returns (uint);
    function waterMark() external view returns (uint);
    function performanceFee() external view returns (uint);
    function adminFee() external view returns (uint);
    function withdrawalFee() external view returns (uint);
    function numPositions() external view returns (uint);
    function getPricePerFullShare() external view returns (uint256);
    function getWithdrawable(address user) external view returns (uint);
    function balance() external view returns (uint256);
    function deposit(uint256 _amount) external;
    function depositAll() external;
    function withdraw(uint256 _shares) external;
    function withdrawAll() external;
    function setFees(uint performance, uint admin, uint withdrawal) external;
    function setStrategiesAllocation(uint256[] memory _strategiesAllocation) external;
    function epochHarvest() external;
    function earn() external;
    function inCaseTokensGetStuck(address _token, uint256 _amount) external;
    function pause() external;
    function unpause() external;
}

