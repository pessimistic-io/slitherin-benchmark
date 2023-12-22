// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import { IERC20, SafeERC20 } from "./SafeERC20.sol";
import { MerkleProof } from "./MerkleProof.sol";
import { IMerkleDistributor } from "./IMerkleDistributor.sol";
import { GovernanceInitiationData } from "./GovernanceInitiationData.sol";

error AlreadyClaimed();
error InvalidProof();

/**
 * @title MerkleDistributor
 * @author Cora Dev Team
 * @notice This contract is used to airdrop tokens to users based on a merkle root.
 * @dev Modified version of Uniswap's merkle distributor https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
 * It accepts a GovernanceInitiationData as parameter to get the token address.
 */
contract MerkleDistributor is IMerkleDistributor {
  using SafeERC20 for IERC20;

  address public immutable override token;
  bytes32 public immutable override merkleRoot;

  GovernanceInitiationData internal immutable initiationData;

  // This is a packed array of booleans.
  mapping(uint256 => uint256) private claimedBitMap;

  constructor(GovernanceInitiationData _initiationData, bytes32 _merkleRoot) {
    merkleRoot = _merkleRoot;
    initiationData = _initiationData;
    token = _initiationData.tokenAddress();
  }

  function isClaimed(uint256 index) public view override returns (bool) {
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimedBitMap[claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  function _setClaimed(uint256 index) private {
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
  }

  function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof)
    public
    virtual
    override
  {
    if (isClaimed(index)) revert AlreadyClaimed();

    // Verify the merkle proof.
    bytes32 node = keccak256(abi.encodePacked(index, account, amount));
    if (!MerkleProof.verify(merkleProof, merkleRoot, node)) {
      revert InvalidProof();
    }

    // Mark it claimed and send the token.
    _setClaimed(index);

    IERC20(token).safeTransfer(account, amount);

    emit Claimed(index, account, amount);
  }
}

