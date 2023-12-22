// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title Address Storage
 * @author SyntheX (prasad@chainscore.finance)
 * 
 * @notice Contract to store addresses
 * @notice This contract is used to store addresses of other contracts
 * @dev Vaild keys are:
 * VAULT - Vault address
 * PRICE_ORACLE - Price oracle address
 * SYNTHEX - Main Synthex contract address
 * 
 */
abstract contract AddressStorage {

    /// @notice Event to be emitted when address is updated
    event AddressUpdated(bytes32 indexed key, address indexed value);    

    // Mapping to store addresses (hashedKey => address)
    mapping(bytes32 => address) private addresses;

    uint256[49] private __gap;

    /**
     * @notice Function to get address of a contract
     * @param _key Key of the address
     * @return Address of the contract
     */
    function getAddress(bytes32 _key) public view returns (address) {
        return addresses[_key];
    }

    /**
     * @notice Function to set address of a contract
     * @param _key Key of the address
     * @param _value Address of the contract
     */
    function _setAddress(bytes32 _key, address _value) internal {
        addresses[_key] = _value;
        emit AddressUpdated(_key, _value);
    }
}
