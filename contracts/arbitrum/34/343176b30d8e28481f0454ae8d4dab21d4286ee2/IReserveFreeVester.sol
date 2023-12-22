// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IReserveFreeVester {
    function depositForAccount(address _account, uint256 _amount) external;
    function claimForAccount(address _account, address _receiver) external returns (uint256);
    function getMaxVestableAmount(address _account) external view returns (uint256);
    function usedAmounts(address) external view returns (uint256);
}
