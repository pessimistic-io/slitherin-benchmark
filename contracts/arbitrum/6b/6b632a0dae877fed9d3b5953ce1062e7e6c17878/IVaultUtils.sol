// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IVaultUtils {
    function getVaultUserInfo(
        address _user
    ) external view returns (uint256 stakedAmount);

    function isUserInVaults(address _user) external view returns (bool);
}

