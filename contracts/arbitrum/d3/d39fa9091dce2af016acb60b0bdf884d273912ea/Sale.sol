// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721Enumerable.sol";
import "./ERC721Holder.sol";
import "./MerkleProof.sol";
import "./ERC165Checker.sol";
import "./Ownable.sol";

contract Sale is ERC721Holder, Ownable {
    IERC721Enumerable public NFT;
    uint256 public price;
    bytes32 public merkleRoot;
    address operator;

    error BadInput();
    error BeepBoop();
    error Forbidden();
    error InvalidMerkleProof();
    error TokenOutOfStock();
    error Underpaid();

    constructor(
        address _nft,
        uint256 _price,
        address _operator
    ) {
        NFT = IERC721Enumerable(_nft);
        price = _price;
        operator = _operator;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setNFT(address _nft) external onlyOwner {
        if (
            !ERC165Checker.supportsInterface(
                _nft,
                type(IERC721Enumerable).interfaceId
            )
        ) revert BadInput();

        NFT = IERC721Enumerable(_nft);
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    modifier eoaOnly() {
        if (tx.origin != msg.sender) revert BeepBoop();
        _;
    }

    function drop(address to, uint256 quantity) external eoaOnly {
        if (msg.sender != operator) revert Forbidden();
        if (to == address(0)) revert BadInput();
        if (quantity > NFT.balanceOf(address(this))) revert TokenOutOfStock();

        deliver(to, quantity);
    }

    function purchase(bytes32[] calldata proof, uint256 quantity)
        external
        payable
        eoaOnly
    {
        if (msg.value < price * quantity) revert Underpaid();
        if (quantity > NFT.balanceOf(address(this))) revert TokenOutOfStock();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        if (!isValidLeaf) revert InvalidMerkleProof();

        deliver(msg.sender, quantity);

        if (msg.value > price * quantity) {
            payable(msg.sender).transfer(msg.value - price * quantity);
        }
    }

    function withdraw(address payable recipient, uint256 amount)
        external
        onlyOwner
    {
        recipient.transfer(amount);
    }

    function withdraw(
        address recipient,
        address erc20,
        uint256 amount
    ) external onlyOwner {
        IERC20(erc20).transfer(recipient, amount);
    }

    function deliver(address to, uint256 quantity) private {
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = NFT.tokenOfOwnerByIndex(
                address(this),
                NFT.balanceOf(address(this)) - 1
            );
            NFT.safeTransferFrom(address(this), to, tokenId);
        }
    }

    receive() external payable {}
}

