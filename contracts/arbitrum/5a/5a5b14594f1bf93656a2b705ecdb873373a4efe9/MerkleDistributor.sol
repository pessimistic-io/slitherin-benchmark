// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.10;


import "./IERC1155.sol";
import "./ReentrancyGuard.sol";
import {MerkleProof} from "./MerkleProof.sol";

/** 
  @notice 
  Allows users to claim collab land tokens depending on merkel root verification.
  
  @dev
  Inherits from -
  IMerkleDistributor: This is a merkel distributor interface.
*/
contract MerkleDistributor is ReentrancyGuard {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error AlreadyClaimed();
    error InvalidProof();

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount);

    /** 
    @notice 
    ocean contract address.
    */
    address public immutable ocean;

    /** 
    @notice 
    wrapped collab erc1155 id.
    */
    uint256 public immutable collabOceanId;

    /** 
    @notice 
    merkel root.
    */
    bytes32 public immutable merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    /**
      @param ocean_ ocean contract address
      @param collabOceanId_ wrapped collab erc1155 id
      @param merkleRoot_ merkel root
    */
    constructor(address ocean_, uint256 collabOceanId_, bytes32 merkleRoot_) {
        ocean = ocean_;
        collabOceanId = collabOceanId_;
        merkleRoot = merkleRoot_;
    }

    /** 
    @notice Use bitmap to set claim status in storage
    */
    function _setClaimed(uint256 index) internal {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /** 
    @notice check claim status
    @param index proof index
    @return claim status
    */
    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    /** 
    @notice claim tokens depending on merkel root verification
    @param index proof index
    @param amount amount to claim
    @param merkleProof merkel proof to verify
    */
    function claim(uint256 index, uint256 amount, bytes32[] calldata merkleProof) public nonReentrant {
        if (isClaimed(index)) revert AlreadyClaimed();

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, amount));
        if (!MerkleProof.verify(merkleProof, merkleRoot, node)) revert InvalidProof();

        // Mark it claimed and send the wrapped token.
        _setClaimed(index);

        // transfer tokens
        IERC1155(ocean).safeTransferFrom(address(this), msg.sender, collabOceanId, amount, "");

        emit Claimed(index, msg.sender, amount);
    }
}
