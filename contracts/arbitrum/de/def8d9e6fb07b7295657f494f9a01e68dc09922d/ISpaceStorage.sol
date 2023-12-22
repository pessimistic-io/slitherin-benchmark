// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import {Storage} from "./Struct.sol";

interface ISpaceStorage {
    //
    //Variables
    //
    function threshold() external view returns (uint24);

    // Function signature for mapping
    function validators(address key) external view returns (bool);

    // Function signature for mapping
    function known_networks(uint256 key) external view returns (Storage.NETWORK memory);

    // Function signature for mapping
    function minted(address key) external view returns (Storage.TKN memory);
    // Function signature for mapping
    function getAddressFromOriginHash(string memory key) external view returns (address);

    // Function signature for mapping
    function transfers(bytes32 key) external view returns (uint256);

    // Function signature for mapping
    function lock_map(string memory key) external view returns (address);

    //
    //Methods
    //
    function addNetwork(
        uint256, 
        uint8
    ) external;

    function removeNetwork(
        uint256 id
    ) external;

    function addValidator(
        address
    ) external;

    function removeValidator(
        address
    ) external;

    function setThreshold(
        uint24
    ) external;

    function addMinted(
        address token_address, 
        string memory origin_hash, 
        Storage.TKN memory tkn
    ) external;

    function incrementNonce(
        bytes32 key
    ) external;

    function addLockMap(
        string memory t, 
        address token_hash
    ) external;
}
