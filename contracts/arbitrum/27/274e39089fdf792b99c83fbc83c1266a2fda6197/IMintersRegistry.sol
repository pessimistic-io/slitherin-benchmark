// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMintersRegistry {
    struct MinterInfo {
        string name;
        string latitude;
        string longitude;
    }

    event MinterSet(address minter, bool isMinter);
    event MintersSet(address[] minters, bool isMinter);

    event MinterInfoSet(address minter, MinterInfo name);
    event MintersInfoSet(address[] minters, MinterInfo[] names);

    function setMinter(address _minter, bool _isMinter) external;

    function isMinter(address minter) external view returns (bool);

    function setMinters(address[] calldata _minters, bool _isMinter) external;

    function setMinterInfo(address minter, MinterInfo calldata info) external;

    function setMintersInfo(
        address[] calldata minters,
        MinterInfo[] calldata infos
    ) external;

    function getMinterInfo(
        address minter
    ) external view returns (MinterInfo memory);
}

