// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";

import {IMagicDomainRegistry} from "./IMagicDomainRegistry.sol";

/**
 * @dev Registry of all in-use domains, and their associated metadata / access control
 */
contract MagicDomainRegistry is IMagicDomainRegistry, Initializable {
    /**
     * @notice Metadata for a given node
     * @param owner owner of the associated node
     * @param resolver The associated resolver for the node. Used to handle magic domain logic
     * @param ttl The amount of time this node wishes to be cached for before getting a refreshed copy
     */
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
        bool blockSubnodes;
    }

    mapping (bytes32 => Record) records;
    // wallet address -> delegate (sender) address -> is approved
    mapping (address => mapping(address => bool)) operators;

    /**
     * @dev Initializes the contract by setting the root node owner to the caller.
     */
    function initialize() external initializer {
        records[0x0].owner = msg.sender;
    }

    // ---------
    // External
    // ---------

    /**
     * @dev Enable or disable approval for a third party ("operator") to manage
     *  all of `msg.sender`'s MagicDomainRegistry records. Emits the ApprovalForAll event.
     * @param _operator Address to add to the set of onlyNodeOwnerOperator operators.
     * @param _approved True if the operator is approved, false to revoke approval.
     */
    function setApprovalForAll(address _operator, bool _approved) external {
        operators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    // ---------
    // Node Admin
    // ---------

    /**
     * @dev Sets the record for the root node.
     * @param _owner The address of the new owner.
     * @param _resolver The address of the resolver.
     * @param _ttl The TTL in seconds.
     */
    function setRootRecord(address _owner, address _resolver, uint64 _ttl) external {
        setRootOwner(_owner);
        _setResolverAndTTL(0x0, _resolver, _ttl);
    }

    /**
     * @dev Sets the record for a subnode.
     * @param _node The parent node.
     * @param _label The hash of the label specifying the subnode.
     * @param _owner The address of the new owner.
     * @param _resolver The address of the resolver.
     * @param _ttl The TTL in seconds.
     */
    function setSubnodeRecord(bytes32 _node, bytes32 _label, address _owner, address _resolver, uint64 _ttl) external {
        bytes32 subnode = setSubnodeOwner(_node, _label, _owner);
        _setResolverAndTTL(subnode, _resolver, _ttl);
    }
    
    /**
     * @dev Removes all record of a subnode keccak256(node, label). May only be called by the owner of the parent node.
     * @param _node The parent node.
     * @param _label The hash of the label specifying the subnode.
     */
    function removeSubnodeRecord(bytes32 _node, bytes32 _label) public nodeSubnodesAllowed(_node) onlyNodeOwnerOperator(_node) {
        bytes32 subnode = keccak256(abi.encodePacked(_node, _label));
        delete records[subnode];
        emit RecordRemoved(_node, _label);
    }

    /**
     * @dev Transfers ownership of the root node to a new address. May only be called by the current owner of the root node.
     * @param _owner The address of the new owner.
     */
    function setRootOwner(address _owner) public onlyNodeOwnerOperator(0x0) {
        _setOwner(0x0, _owner);
        emit Transfer(0x0, _owner);
    }

    /**
     * @dev Transfers ownership of a subnode keccak256(node, label) to a new address. May only be called by the owner of the parent node.
     * @param _node The parent node.
     * @param _label The hash of the label specifying the subnode.
     * @param _owner The address of the new owner.
     */
    function setSubnodeOwner(bytes32 _node, bytes32 _label, address _owner) public nodeSubnodesAllowed(_node) onlyNodeOwnerOperator(_node) returns(bytes32) {
        bytes32 subnode = keccak256(abi.encodePacked(_node, _label));
        _setOwner(subnode, _owner);
        emit NewOwner(_node, _label, _owner);
        return subnode;
    }

    /**
     * @dev Changes the ability to modify further subnodes for a subnode keccak256(node, label). May only be called by the owner of the parent node.
     * @param _node The parent node.
     * @param _label The hash of the label specifying the subnode.
     * @param _blockSubnodes The address of the new owner.
     */
    function setBlockSubnodeForSubnode(bytes32 _node, bytes32 _label, bool _blockSubnodes) public nodeSubnodesAllowed(_node) onlyNodeOwnerOperator(_node) returns(bytes32) {
        bytes32 subnode = keccak256(abi.encodePacked(_node, _label));
        records[subnode].blockSubnodes = _blockSubnodes;
        emit BlockSubnodeStatusChanged(_node, _label, _blockSubnodes);
        return subnode;
    }

    /**
     * @dev Sets the resolver address for the specified node.
     * @param _node The node to update.
     * @param _resolver The address of the resolver.
     */
    function setResolver(bytes32 _node, address _resolver) public onlyNodeOwnerOperator(_node) {
        emit NewResolver(_node, _resolver);
        records[_node].resolver = _resolver;
    }

    /**
     * @dev Sets the TTL for the specified node.
     * @param _node The node to update.
     * @param _ttl The TTL in seconds.
     */
    function setTTL(bytes32 _node, uint64 _ttl) public onlyNodeOwnerOperator(_node) {
        emit NewTTL(_node, _ttl);
        records[_node].ttl = _ttl;
    }

    // ---------
    // Views
    // ---------

    /**
     * @dev Returns the address that owns the specified node.
     * @param _node The specified node.
     * @return address of the owner.
     */
    function owner(bytes32 _node) public view returns (address) {
        address addr = records[_node].owner;
        if (addr == address(this)) {
            return address(0x0);
        }

        return addr;
    }

    /**
     * @dev Returns the address of the resolver for the specified node.
     * @param _node The specified node.
     * @return address of the resolver.
     */
    function resolver(bytes32 _node) public view returns (address) {
        return records[_node].resolver;
    }

    /**
     * @dev Returns the TTL of a node, and any records associated with it.
     * @param _node The specified node.
     * @return _ttl of the node.
     */
    function ttl(bytes32 _node) public view returns (uint64) {
        return records[_node].ttl;
    }

    /**
     * @dev Returns whether a node can modify subnodes.
     * @param _node The specified node.
     * @return blockSubnodes The block status of the node.
     */
    function areSubnodesBlocked(bytes32 _node) public view returns (bool) {
        return records[_node].blockSubnodes;
    }

    /**
     * @dev Returns whether a record has been imported to the registry.
     * @param _node The specified node.
     * @return Bool if record exists
     */
    function recordExists(bytes32 _node) public view returns (bool) {
        return records[_node].owner != address(0x0);
    }

    /**
     * @dev Query if an address is an onlyNodeOwnerOperator _operator for another address.
     * @param _owner The address that owns the records.
     * @param _operator The address that acts on behalf of the owner.
     * @return true if `_operator` is an _approved _operator for `owner`, false otherwise.
     */
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return operators[_owner][_operator];
    }

    // ---------
    // Internal
    // ---------

    function _setOwner(bytes32 _node, address _owner) internal {
        records[_node].owner = _owner;
    }

    function _setResolverAndTTL(bytes32 _node, address _resolver, uint64 _ttl) internal {
        if(_resolver != records[_node].resolver) {
            records[_node].resolver = _resolver;
            emit NewResolver(_node, _resolver);
        }

        if(_ttl != records[_node].ttl) {
            records[_node].ttl = _ttl;
            emit NewTTL(_node, _ttl);
        }
    }

    // ---------
    // Modifiers
    // ---------

    // Permits modifications of subnodes for the given node.
    modifier nodeSubnodesAllowed(bytes32 _node) {
        address _owner = records[_node].owner;
        require(!records[_node].blockSubnodes, "MagicDomainRegistry: Can't modify subnodes of this node");
        _;
    }

    // Permits modifications only by the owner of the specified node.
    modifier onlyNodeOwnerOperator(bytes32 _node) {
        address _owner = records[_node].owner;
        require(_owner == msg.sender || operators[_owner][msg.sender], "MagicDomainRegistry: Not owner of node");
        _;
    }
}
