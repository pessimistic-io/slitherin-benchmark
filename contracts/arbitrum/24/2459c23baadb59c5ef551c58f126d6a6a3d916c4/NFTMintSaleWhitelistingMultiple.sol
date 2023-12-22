// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./BoringBatchable.sol";
import "./MerkleProof.sol";
import "./NFTMintSaleMultiple.sol";

contract NFTMintSaleWhitelistingMultiple is NFTMintSaleMultiple, BoringBatchable {

    event LogInitUser(address indexed user, uint256 maxMintUser, uint256 tier);

    mapping(uint256 => bytes32) public merkleRoot;
    mapping(uint256 => string) public ipfsHash;

    struct UserAllowed {
        uint128 claimed;
        uint128 max;
    }

    mapping(uint256 => mapping(address => UserAllowed)) claimed;

    constructor (address masterNFT_, SimpleFactory vibeFactory_, IWETH WETH_) NFTMintSaleMultiple(masterNFT_, vibeFactory_, WETH_) {}

    function setMerkleRoot(bytes32[] memory _merkleRoot, string[] memory ipfsHash_) external onlyOwner{
        for(uint i; i < _merkleRoot.length; i++) {
            merkleRoot[i] = _merkleRoot[i];
            ipfsHash[i] = ipfsHash_[i];
        }
    }

    function _preBuyCheck(address recipient, uint256 tier) internal virtual override {
        require(claimed[tier][msg.sender].claimed < claimed[tier][msg.sender].max, "no allowance left");
        claimed[tier][msg.sender].claimed += 1;
    }

    function initUser(address user, bytes32[] calldata merkleProof, uint256 maxMintUser, uint256 tier)
        public payable
    {
        require(
            MerkleProof.verify(
                merkleProof,
                merkleRoot[tier],
                keccak256(abi.encodePacked(user, maxMintUser))
            ),
            "invalid merkle proof"
        );
        claimed[tier][user].max = uint128(maxMintUser);

        emit LogInitUser(user, maxMintUser, tier);
    }

}

