// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./ECDSA.sol";
import "./ERC20.sol";

struct StartedProject {
    bool isStopped;
    address token;
    bytes32 hash;
    uint256 currentBalance;
    uint256 expectedBalance;
}

contract StakingPool {
    /// token, current, expected
    mapping(bytes32 => StartedProject) startedProjects;

    modifier onlySigner(bytes32 hash, bytes calldata signature) {
        address signer = ECDSA.recover(hash, signature);
        require(signer == msg.sender, "Not Signer");
        _;
    }

    function startProject(
        bytes32 hash,
        bytes calldata signature,
        address token,
        uint256 expectedAmount
    ) external onlySigner(hash, signature) {
        startedProjects[hash] = StartedProject(
            false,
            token,
            hash,
            0,
            expectedAmount
        );
    }

    function getProjectMetadata(bytes32 hash)
        external
        view
        returns (StartedProject memory)
    {
        return startedProjects[hash];
    }

    function stopProject(bytes32 hash, bytes calldata signature)
        external
        onlySigner(hash, signature)
    {
        startedProjects[hash].isStopped = true;
    }

    function donate(
        bytes32 projectId,
        address token,
        uint256 amount
    ) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);
        startedProjects[projectId].currentBalance += amount;
    }
}

