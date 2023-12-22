// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function claimable(address _account) external view returns (uint256);

    function withdrawVesting() external;
}

