// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagicDomainReverseRegistrar {
    event ReverseClaimed(address indexed addr, bytes32 indexed node);
    event DefaultResolverChanged(address indexed resolver);

    function setDefaultResolver(address resolver) external;

    function claim(address owner) external returns (bytes32);

    function claimForAddr(
        address addr,
        address owner,
        address resolver
    ) external returns (bytes32);

    function claimWithResolver(address owner, address resolver)
        external
        returns (bytes32);

    function setName(string memory name) external returns (bytes32);

    function setNameForAddr(
        address addr,
        address owner,
        address resolver,
        string memory name
    ) external returns (bytes32);

    function node(address addr) external pure returns (bytes32);
}
