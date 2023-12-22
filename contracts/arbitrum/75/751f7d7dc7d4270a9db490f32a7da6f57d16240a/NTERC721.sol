// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract NonTransferrableERC721 is ERC721, Ownable {
    string public baseURI;
    bytes32 public merkleRoot;
    uint256 public mintPrice;
    uint256 private _currentTokenId = 0;

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 merkleRoot_,
        string memory baseURI_,
        uint256 mintPrice_
    ) ERC721(name_, symbol_) {
        setMerkleRoot(merkleRoot_);
        setBaseURI(baseURI_);
        setMintPrice(mintPrice_);
    }

    function mint(bytes32[] calldata merkleProof) external payable {
        require(_isMinter(msg.sender, merkleProof), "Not a valid minter");
        require(balanceOf(msg.sender) == 0, "Only one token is allowed");
        require(msg.value >= mintPrice, "Insufficient payment for minting");

        __mint(msg.sender);

        // If the sender sent more than the required amount, refund the excess
        if (msg.value > mintPrice) {
            uint256 refundAmount = msg.value - mintPrice;
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Refund failed");
        }
    }

    function _isMinter(
        address minter,
        bytes32[] calldata merkleProof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(minter, 1)))
        );
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    function mintByOwner(address to) external onlyOwner {
        require(balanceOf(to) == 0, "Only one token is allowed");
        __mint(to);
    }

    function __mint(address to) private {
        uint256 newTokenId = _getNextTokenId();
        _safeMint(to, newTokenId);
        _incrementTokenId();
    }

    function burn(uint256 tokenId) external {
        require(
            msg.sender == owner() || msg.sender == ownerOf(tokenId),
            "Only contract owner or token owner can burn the token"
        );
        _burn(tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyOwner {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyOwner {
        super.safeTransferFrom(from, to, tokenId);
    }

    function withdraw() public onlyOwner {
        address payable owner = payable(owner());
        owner.transfer(address(this).balance);
    }

    function setMerkleRoot(bytes32 merkleRoot_) public onlyOwner {
        merkleRoot = merkleRoot_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return string(abi.encodePacked(super.tokenURI(tokenId), ".json"));
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setMintPrice(uint256 mintPrice_) public onlyOwner {
        mintPrice = mintPrice_;
    }

    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    function _incrementTokenId() private {
        _currentTokenId++;
    }
}

