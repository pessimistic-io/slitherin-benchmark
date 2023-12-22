// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

enum SmolAddressEnum {
    OLDSMOLSADDRESS,
    SMOLSADDRESS,

    SMOLSSTATEADDRESS,
    SCHOOLADDRESS,

    SMOLSTRAITSTORAGEADDRESS,

    SMOLSRENDERERADDRESS,
    TRANSFERBLOCKERADDRESS
}

interface ISmolsAddressRegistry{
    function getAddress(SmolAddressEnum) external view returns(address);
}
