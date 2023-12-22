// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

interface IDeviceValidation {
    function setDeviceKey(
        address account,
        uint256 deviceId,
        string memory key
    ) external;

    function clearDeviceKey(address account, uint256 deviceId) external;

    function clearAccountKeys(address account) external;

    function getDeviceKey(
        address account,
        uint256 deviceId
    ) external view returns (string memory key);

    function getDeviceKeys(
        address account
    ) external view returns (uint256[] memory devices, string[] memory keys);

    function hasDevices(address account) external view returns (bool);
}

