// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {OnChainCredential} from "./Credential.sol";

contract CredentialFactory {
    mapping(string => address) internal hackathonCredentialMapping;
    address private _mintAuthority;
    address private owner;

    error InvalidCaller();

    event CredentialCreated(address indexed credential, string hackathon_uuid);

    constructor(address _mintAuth) {
        owner = msg.sender;
        _mintAuthority = _mintAuth;
    }

    /// @notice Deploys a new Credential NFT Contract
    /// @param data this is the ABI encoded data for deploying new credential contract
    /// @dev data is ABI encoded as (string, string, string, address)
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
        emit CredentialCreated(address(credential), hackathon_uuid);
    }

    /// @notice Returns the address of the credential contract for a given hackathon UUID
    /// @param hackathon_uuid The UUID of the hackathon for which the credential contract address is to be returned
    /// @return Returns the address for the credential contract for the given hackathon UUID
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
    function updateAuthority(address newAuthority) external {
        if (msg.sender != owner) revert InvalidCaller();
        _mintAuthority = newAuthority;
    }

    /// @notice Updates the owner Factory
    function updateOwner(address newOwner) external {
        if (msg.sender != owner) revert InvalidCaller();
        owner = newOwner;
    }
}

