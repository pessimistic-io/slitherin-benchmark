// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.11;

import "./IERC20.sol";
import "./MerkleProof.sol";
import "./IMerkleDistributor.sol";
import "./Ownable.sol";

contract MerkleDistributor is IMerkleDistributor, Ownable {
    address public immutable override token;
    bytes32 public immutable override merkleRoot;
    uint public expirationDate;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(address token_, bytes32 merkleRoot_, address owner_, uint expirationDate_) public {
        token = token_;
        merkleRoot = merkleRoot_;
        setOwnerInternal(owner_);
        expirationDate = expirationDate_;
    }

    function withdrawAfterExpiration() external onlyOwner {
        require(now >= expirationDate, "The claim period has not expired yet.");
        uint amount = IERC20(token).balanceOf(address(this));
        require(IERC20(token).transfer(msg.sender, amount), 'MerkleDistributor: Transfer failed.');
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

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
        require(now < expirationDate, "Claim period has expired");
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(IERC20(token).transfer(account, amount), 'MerkleDistributor: Transfer failed.');

        emit Claimed(index, account, amount);
    }
}

