// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract ETFANS is ERC721A, Ownable {

    enum EPublicMintStatus {
        NOTACTIVE,
        ALLOWLIST_MINT,
        PUBLIC_MINT,
        CLOSED
    }

    EPublicMintStatus public publicMintStatus;

    string  public baseTokenURI = "https://ipfs.io/ipfs/bafkreichqggefk2uvvpganeuqtp6wgvkrrzwlfgstyxy6xmftbji4czvna";
    string  public defaultTokenURI;
    uint256 public maxSupply = 5000;
    uint256 public publicSalePrice = 0.0033 ether;
    uint256 public allowListSalePrice = 0 ether;

    address payable public payMent;
    mapping(address => uint256) public usermint;
    mapping(address => bool) public allowlistmint;

    bytes32 private _merkleRoot = 0x96c4906fe8b0416bde923df0fb99e2b3737cf34057dbe28317df8c6dceb4fad9;


    constructor() ERC721A ("ETFANS", "ETFANS") {
        payMent = payable(msg.sender);
        _safeMint(msg.sender, 1);
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }

    function mint(uint256 _quantity) external payable  {
        require(publicMintStatus == EPublicMintStatus.PUBLIC_MINT, "Public sale closed");
        require(_quantity <= 10, "Invalid quantity");
        require(totalSupply() + _quantity <= maxSupply, "Exceed supply");
        require(msg.value >= _quantity * publicSalePrice, "Ether is not enough");
        _safeMint(msg.sender, _quantity);
    }

    function allowListMint(bytes32[] calldata _merkleProof) external payable {
        require(publicMintStatus == EPublicMintStatus.ALLOWLIST_MINT || publicMintStatus == EPublicMintStatus.PUBLIC_MINT, "Allowlist sale closed");
        require(totalSupply() + 1 <= maxSupply, "Exceed supply");
        require(isWhitelistAddress(msg.sender, _merkleProof), "Caller is not in whitelist or invalid signature");
        require(!allowlistmint[msg.sender], "allowListMint Finished");
        allowlistmint[msg.sender] = true;
        _safeMint(msg.sender, 1);
    }

    function isWhitelistAddress(address _address, bytes32[] calldata _signature) public view returns (bool) {
        return MerkleProof.verify(_signature, _merkleRoot, keccak256(abi.encodePacked(_address)));
    }

    function airdrop(address[] memory marketmintaddress, uint256[] memory mintquantity) public payable onlyOwner {
        for (uint256 i = 0; i < marketmintaddress.length; i++) {
            require(totalSupply() + mintquantity[i] <= maxSupply, "Exceed supply");
            _safeMint(marketmintaddress[i], mintquantity[i]);
        }
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value : address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function getHoldTokenIdsByOwner(address _owner) public view returns (uint256[] memory) {
        uint256 index = 0;
        uint256 hasMinted = _totalMinted();
        uint256 tokenIdsLen = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](tokenIdsLen);
        for (uint256 tokenId = 1; index < tokenIdsLen && tokenId <= hasMinted; tokenId++) {
            if (_owner == ownerOf(tokenId)) {
                tokenIds[index] = tokenId;
                index++;
            }
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId), ".json")) : defaultTokenURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string calldata _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setDefaultURI(string calldata _defaultURI) external onlyOwner {
        defaultTokenURI = _defaultURI;
    }

    function setPublicPrice(uint256 mintprice) external onlyOwner {
        publicSalePrice = mintprice;
    }

    function setAllowlistPrice(uint256 mintprice) external onlyOwner {
        allowListSalePrice = mintprice;
    }

    function setPublicMintStatus(uint256 status) external onlyOwner {
        publicMintStatus = EPublicMintStatus(status);
    }

    function setMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _merkleRoot = merkleRoot;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
}
