// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {OnChainCredential} from "./OnChainCredential.sol";

contract OnChainCredentialFactory {
    /// @dev mapping of the hackathon uuid to the credential contract address
    mapping(string => address) internal hackathonCredentialMapping;
    /// @dev The address of the mint authority allowed to create the credential contract
    address private _mintAuthority;
    /// @dev The owner of the contract
    address private owner;

    /// @dev The Error thrown when the caller is not the owner
    error InvalidCaller();

    /// @notice The event emitted when a new credential contract is deployed
    /// @param credential The contract address of the credential contract
    /// @param hackathon_uuid The uuid of the hackathon
    event OnChainCredentialCreated(
        address indexed credential,
        string hackathon_uuid
    );

    constructor(address _mintAuth) {
        owner = msg.sender;
        _mintAuthority = _mintAuth;
    }

    /// @notice Deploys a new Credential NFT Contract
    /// @param data this is the ABI encoded data for deploying new credential contract
    /// @dev data is ABI encoded as (string, string, string, address) only the owner can call this function
    function deployCredential(bytes memory data) external {
        if (msg.sender != owner) revert InvalidCaller();
        (
            string memory name,
            string memory symbol,
            string memory hackathon_uuid,
            address _hackathon_owner
        ) = abi.decode(data, (string, string, string, address));

        OnChainCredential credential = new OnChainCredential(
            name,
            symbol,
            _mintAuthority,
            _hackathon_owner
        );
        hackathonCredentialMapping[hackathon_uuid] = address(credential);

        emit OnChainCredentialCreated(address(credential), hackathon_uuid);
    }

    /// @notice Returns the address of the credential contract for a given hackathon UUID
    /// @param hackathon_uuid The UUID of the hackathon for which the credential contract address is to be returned
    /// @return hackathon_uuid The UUID of the hackathon
    function hackathonCredential(
        string memory hackathon_uuid
    ) external view returns (address) {
        return hackathonCredentialMapping[hackathon_uuid];
    }

    /// @notice Returns the address of the mint authority
    function mintAuthority() external view returns (address) {
        return _mintAuthority;
    }

    /// @notice Updates the mint authority
    /// @dev Only the owner can call this function
    function updateAuthority(address newAuthority) external {
        if (msg.sender != owner) revert InvalidCaller();
        _mintAuthority = newAuthority;
    }

    /// @notice Updates the owner Factory
    /// @dev Only the owner can call this function
    function updateOwner(address newOwner) external {
        if (msg.sender != owner) revert InvalidCaller();
        owner = newOwner;
    }
}

