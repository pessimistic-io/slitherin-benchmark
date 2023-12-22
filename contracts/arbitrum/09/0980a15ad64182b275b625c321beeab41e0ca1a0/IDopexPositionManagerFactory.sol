//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IDopexPositionManagerFactory {
    function createPositionmanager(address _user) external returns (address positionManager);
    function callback() external view returns (address);
    function minSlipageBps() external view returns (uint256);
    function userPositionManagers(address _user) external view returns (address);
}
