// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./MerkleProof.sol";

import "./Token.sol";
import "./Withdrawable.sol";

contract Minter is Ownable, Withdrawable {
    Token public token;

    bytes32 public whitelistRoot;

    modifier onlyWhitelisted(uint256 tokenId, bytes32[] memory proof) {
        require(MerkleProof.verify(proof, whitelistRoot, keccak256(abi.encode(_msgSender(), tokenId))), "Minter: account mismatch");
        _;
    }

    /* Configuration
     ****************************************************************/

    function setToken(address token_) external onlyOwner {
        token = Token(token_);
    }

    function setWhitelistRoot(bytes32 whitelistRoot_) external onlyOwner {
        whitelistRoot = whitelistRoot_;
    }

    /* Domain
     ****************************************************************/

    function mint(uint256 tokenId, bytes32[] calldata proof) external onlyWhitelisted(tokenId, proof) {
        token.mint(tokenId, _msgSender());
    }
}

