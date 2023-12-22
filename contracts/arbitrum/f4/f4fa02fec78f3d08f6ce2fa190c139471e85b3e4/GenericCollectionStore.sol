// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

library Roles {
    bytes32 public constant MINTER_ROLE = keccak256("kresko.roles.minter");
    bytes32 public constant OPERATOR_ROLE = keccak256("kresko.roles.operator");
}

library Bytes {
    function toString(bytes32 val) internal pure returns (string memory) {
        return string(abi.encodePacked(val));
    }

    function fromString(string memory val) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(val));
    }
}

library StoreOps {
    event StoreOperation(
        address indexed account,
        uint256 indexed tokenId,
        bytes32 indexed key,
        bytes32 value,
        uint256 action
    );

    /* -------------------------------------------------------------------------- */
    /*                                    READ                                    */
    /* -------------------------------------------------------------------------- */

    function get(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key
    ) internal view returns (bytes32[] memory) {
        return self[_tokenId][_account][_key];
    }

    function exists(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key
    ) internal view returns (bool) {
        return self[_tokenId][_account][_key].length != 0;
    }

    function getIndex(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        uint256 _idx
    ) internal view returns (bytes32) {
        return self[_tokenId][_account][_key][_idx];
    }

    /* -------------------------------------------------------------------------- */
    /*                                CREATE/UPDATE                               */
    /* -------------------------------------------------------------------------- */

    function create(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _value
    ) internal returns (bytes32) {
        require(!exists(self, _tokenId, _account, _key), "exists");
        return append(self, _tokenId, _account, _key, _value);
    }

    function append(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _value
    ) internal returns (bytes32) {
        self[_tokenId][_account][_key].push(_value);
        emit StoreOperation(_account, _tokenId, _key, _value, 1);
        return _value;
    }

    /**
     * @notice Update a value in the store if it exists, revert no value exists
     * @param _tokenId The token id to update
     * @param _account The account to update
     * @param _key The key to update
     * @param _newValue The new value to update
     * @return The new value
     */
    function safeUpdate(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _newValue
    ) internal returns (bytes32) {
        require(!exists(self, _tokenId, _account, _key), "exists");
        return update(self, _tokenId, _account, _key, _newValue);
    }

    /**
     * @notice Update a value in the store if it exists, create it if it doesn't
     * @param _tokenId The token id to update
     * @param _account The account to update
     * @param _key The key to update
     * @param _newValue The new value to update
     * @return The new value
     */
    function update(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _newValue
    ) internal returns (bytes32) {
        clear(self, _tokenId, _account, _key);
        append(self, _tokenId, _account, _key, _newValue);
        return _newValue;
    }

    /**
     * @notice Update with array of new values
     * @param _tokenId The token id to update
     * @param _account The account to update
     * @param _key The key to update
     * @param _newValues New values to set
     * @return The new value
     */
    function update(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32[] memory _newValues
    ) internal returns (bool) {
        clear(self, _tokenId, _account, _key);
        for (uint256 i = 0; i < _newValues.length; i++) {
            append(self, _tokenId, _account, _key, _newValues[i]);
        }
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   DELETE                                   */
    /* -------------------------------------------------------------------------- */

    function clear(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32 _key
    ) internal returns (bool) {
        delete self[_tokenId][_account][_key];
        emit StoreOperation(_account, _tokenId, _key, "", 0);
        return true;
    }

    function clearMany(
        mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
            storage self,
        uint256 _tokenId,
        address _account,
        bytes32[] memory _keys
    ) internal returns (bool) {
        for (uint256 i = 0; i < _keys.length; i++) {
            clear(self, _tokenId, _account, _keys[i]);
        }
        return true;
    }
}

contract GenericCollectionStore is AccessControlUpgradeable {
    using StoreOps for mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])));

    /* -------------------------------------------------------------------------- */
    /*                                  Modifiers                                 */
    /* -------------------------------------------------------------------------- */

    modifier storeAuth(address _account, bool _selfAccess) {
        if (_account != msg.sender) {
            require(hasRole(Roles.OPERATOR_ROLE, msg.sender), "!operator");
        } else {
            require(_selfAccess, "!self_access");
        }
        _;
    }

    // Mapping from Token ID -> Account -> Key -> Value
    mapping(uint256 => mapping(address => mapping(bytes32 => bytes32[])))
        internal _collectionStore;

    function storeGetByKey(
        uint256 _tokenId,
        address _account,
        bytes32 _key
    ) external view returns (bytes32[] memory) {
        return _collectionStore.get(_tokenId, _account, _key);
    }

    function storeGetByIndex(
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        uint256 _idx
    ) external view returns (bytes32) {
        return _collectionStore.getIndex(_tokenId, _account, _key, _idx);
    }

    function storeCreateValue(
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _value
    ) external storeAuth(_account, false) returns (bytes32) {
        return _collectionStore.create(_tokenId, _account, _key, _value);
    }

    function storeAppendValue(
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _value
    ) external storeAuth(_account, false) returns (bytes32) {
        return _collectionStore.append(_tokenId, _account, _key, _value);
    }

    function storeUpdateValue(
        uint256 _tokenId,
        address _account,
        bytes32 _key,
        bytes32 _value
    ) external storeAuth(_account, false) returns (bytes32) {
        return _collectionStore.safeUpdate(_tokenId, _account, _key, _value);
    }

    function storeClearKey(
        uint256 _tokenId,
        address _account,
        bytes32 _key
    ) external storeAuth(_account, false) returns (bool) {
        return _collectionStore.clear(_tokenId, _account, _key);
    }

    function storeClearKeys(
        uint256 _tokenId,
        address _account,
        bytes32[] memory _keys
    ) external storeAuth(_account, false) returns (bool) {
        return _collectionStore.clearMany(_tokenId, _account, _keys);
    }
}

