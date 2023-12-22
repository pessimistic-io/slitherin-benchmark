// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagicDomainRegistry {
    // Logged when the owner of a node assigns a new owner to a subnode.
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);
    // Logged when the owner of a node transfers ownership to a new account.
    event Transfer(bytes32 indexed node, address owner);
    // Logged when the resolver for a node changes.
    event NewResolver(bytes32 indexed node, address resolver);
    // Logged when the TTL of a node changes
    event NewTTL(bytes32 indexed node, uint64 ttl);
    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    // Logged when the owner of a node deletes a subnode.
    event RecordRemoved(bytes32 indexed node, bytes32 indexed label);
    // Logged when the owner of a node changes a subnode's ability to create more subnodes.
    event BlockSubnodeStatusChanged(bytes32 indexed node, bytes32 indexed label, bool blockSubnodes);

    function setRootRecord(address _owner, address resolver, uint64 ttl) external;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
    function removeSubnodeRecord(bytes32 _node, bytes32 _label) external;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external returns(bytes32);
    function setBlockSubnodeForSubnode(bytes32 _node, bytes32 _label, bool _blockSubnode) external returns(bytes32);
    function setResolver(bytes32 node, address resolver) external;
    function setRootOwner(address _owner) external;
    function setTTL(bytes32 node, uint64 ttl) external;
    function setApprovalForAll(address operator, bool approved) external;
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
    function ttl(bytes32 node) external view returns (uint64);
    function areSubnodesBlocked(bytes32 _node) external view returns (bool);
    function recordExists(bytes32 node) external view returns (bool);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}
