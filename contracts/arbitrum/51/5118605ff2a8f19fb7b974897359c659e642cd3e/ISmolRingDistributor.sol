// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./MerkleProof.sol";
import "./Ownable.sol";

/**
 * @title  ISmolRingDistributor interface
 * @author Archethect
 * @notice This interface contains all functionalities for distributing Smol Rings following a whitelist.
 */
interface ISmolRingDistributor {
    function isClaimed(address account, uint256 epoch) external view returns (bool);

    function getCurrentEpoch() external view returns (uint256);

    function verifyAndClaim(
        address account,
        uint256 epochToClaim,
        uint256 index,
        uint256 amount,
        uint256[] calldata rings,
        bytes32[] calldata merkleProof
    ) external returns (bool);
}

