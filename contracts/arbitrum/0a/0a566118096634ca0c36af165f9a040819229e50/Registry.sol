// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./ECDSA.sol";

contract Registry {
    mapping(address => bytes32[]) projects;

    function selfRegisterProject(bytes32 hash, bytes calldata signature)
        external
    {
        address signer = ECDSA.recover(hash, signature);
        require(signer == msg.sender, "Not Signer");
        projects[signer].push(hash);
    }

    function getProjects(address creator)
        external
        view
        returns (bytes32[] memory)
    {
        return projects[creator];
    }
}

