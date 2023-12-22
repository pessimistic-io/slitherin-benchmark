// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC20.sol";

import "./Sharks.sol";

contract Airdrop is Ownable {
    bytes32 public merkleRoot;
    Sharks public immutable sharks;
    ERC20 public immutable magic;

    uint256 public minimumMagicBalance;

    mapping(address => uint256) public addressHasMinted;

    event Claimed(address indexed to, uint256 count);

    constructor(address sharksAddress_, address magicAddress_) {
        sharks = Sharks(sharksAddress_);
        magic = ERC20(magicAddress_);
        minimumMagicBalance = 20 ether;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        merkleRoot = merkleRoot_;
    }

    function claim(
        address to_,
        uint256 count_,
        bytes32[] calldata merkleProof
    ) public {
        require(merkleRoot != 0, "merkleRoot not set");
        require(addressHasMinted[to_] == 0, "already claimed");
        require(magic.balanceOf(to_) >= minimumMagicBalance, "not enough MAGIC");

        bytes32 node = keccak256(abi.encodePacked(to_, count_));

        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "MerkleDistributor: Invalid proof"
        );

        addressHasMinted[to_] = count_;
        sharks.mint(to_, count_);
        emit Claimed(to_, count_);
    }
}
