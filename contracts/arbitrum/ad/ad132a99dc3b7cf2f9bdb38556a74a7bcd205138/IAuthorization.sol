// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

interface IAuthorization {
    function authorizeAccount(address account) external;

    function deauthorizeAccount(address account) external;

    function isAccountAuthorized(address account) external view returns (bool);

    function isAdminAccount(address account) external view returns (bool);

    function getAuthorizedAccountsCount() external view returns (uint256);

    function getAuthorizedAccountAt(
        uint256 index
    ) external view returns (address);
}

