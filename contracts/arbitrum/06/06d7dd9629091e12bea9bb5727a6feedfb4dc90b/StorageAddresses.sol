// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";

import "./IStorageAddresses.sol";

contract StorageAddresses is Initializable, IStorageAddresses {
    uint256 public totalOwners;

    mapping(address => bool) private owners;
    mapping(bytes32 => address) internal addresses;

    event NewOwner(address indexed _sender, address _owner);
    event RemoveOwner(address indexed _sender, address _owner);

    modifier onlyOwners() {
        require(isOwner(msg.sender), "StorageAddresses: Caller is not an owner");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice used to initialize the contract
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "StorageAddresses: _owner cannot be 0x0");

        owners[_owner] = true;
        totalOwners++;
    }

    /// @notice add owner
    /// @param _newOwner owner address
    function addOwner(address _newOwner) public onlyOwners {
        require(_newOwner != address(0), "StorageAddresses: _newOwner cannot be 0x0");
        require(!isOwner(_newOwner), "StorageAddresses: _newOwner is already owner");

        owners[_newOwner] = true;
        totalOwners++;

        emit NewOwner(msg.sender, _newOwner);
    }

    /// @notice add owners
    /// @param _newOwners owners array
    function addOwners(address[] calldata _newOwners) external onlyOwners {
        for (uint256 i = 0; i < _newOwners.length; i++) {
            addOwner(_newOwners[i]);
        }
    }

    /// @notice remove owner
    /// @param _owner owner address
    function removeOwner(address _owner) external onlyOwners {
        require(_owner != address(0), "StorageAddresses: _owner cannot be 0x0");
        require(isOwner(_owner), "StorageAddresses: _owner is not an owner");
        require(totalOwners > 1, "StorageAddresses: totalOwners must be greater than 1");

        owners[_owner] = false;
        totalOwners--;

        emit RemoveOwner(msg.sender, _owner);
    }

    /// @notice judge if its owner
    /// @param _owner owner address
    /// @return bool value
    function isOwner(address _owner) public view returns (bool) {
        return owners[_owner];
    }

    function _setAddress(bytes32 _key, address _storageAddress, bool _force) internal {
        require(_storageAddress != address(0), "StorageAddresses: _storageAddress cannot be 0x0");

        if (!_force) {
            require(addresses[_key] == address(0), "StorageAddresses: Duplicate _storageAddress");
        }

        addresses[_key] = _storageAddress;
    }

    function setAddress(address _finder, address _storageAddress, bool _force) public override onlyOwners {
        require(_finder != address(0), "StorageAddresses: _finder cannot be 0x0");

        _setAddress(_generateKey(_finder), _storageAddress, _force);
    }

    function setAddress(bytes32 _key, address _storageAddress, bool _force) public override onlyOwners {
        require(_key != bytes32(0), "StorageAddresses: _finder cannot be 0");

        _setAddress(_key, _storageAddress, _force);
    }

    function getAddress(address _finder) public view override returns (address) {
        require(_finder != address(0), "StorageAddresses: _finder cannot be 0x0");

        return addresses[_generateKey(_finder)];
    }

    function getAddress(bytes32 _key) public view override returns (address) {
        require(_key != bytes32(0), "StorageAddresses: _finder cannot be 0");

        return addresses[_key];
    }

    function _generateKey(address _finder) internal pure returns (bytes32) {
        return keccak256(abi.encode(_finder));
    }
}

