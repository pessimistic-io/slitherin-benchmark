// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICoverRightToken {
    function expiry() external view returns (uint256);

    function getClaimableOf(address _user) external view returns (uint256);

    function mint(
        uint256 _poolId,
        address _user,
        uint256 _amount
    ) external;

    function burn(
        uint256 _poolId,
        address _user,
        uint256 _amount
    ) external;

    function generation() external view returns (uint256);
}

