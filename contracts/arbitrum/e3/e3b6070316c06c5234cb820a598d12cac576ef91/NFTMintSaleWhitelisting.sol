// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./BoringBatchable.sol";
import "./MerkleProof.sol";
import "./NFTMintSale.sol";

contract NFTMintSaleWhitelisting is NFTMintSale, BoringBatchable {

    bytes32 public merkleRoot;
    string public ipfsHash;

    struct UserAllowed {
        uint128 claimed;
        uint128 max;
    }

    mapping(address => UserAllowed) claimed;

    constructor (address masterNFT_, SimpleFactory vibeFactory_) NFTMintSale(masterNFT_, vibeFactory_) {}

    function setMerkleRoot(bytes32 merkleRoot_, string memory ipfsHash_) public onlyOwner {
        merkleRoot = merkleRoot_;
        ipfsHash = ipfsHash_;
    }

    function _preBuyCheck(address recipient) internal virtual override {
        require(claimed[msg.sender].claimed < claimed[msg.sender].max, "no allowance left");
        claimed[msg.sender].claimed += 1;
    }

    function initUser(bytes32[] calldata merkleProof, uint256 maxMintUser)
        public
    {
        require(
            MerkleProof.verify(
                merkleProof,
                merkleRoot,
                keccak256(bytes.concat(keccak256(abi.encode(msg.sender, maxMintUser))))
            ),
            "invalid merkle proof"
        );
        claimed[msg.sender].max = uint128(maxMintUser);
    }

}

