// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721A.sol";
import "./Ownable.sol";

contract Puppet is ERC721A, Ownable {
    enum EPublicMintStatus {
        NOTACTIVE,
        ALLOWLIST_MINT,
        PUBLIC_MINT,
        CLOSED
    }

    EPublicMintStatus public publicMintStatus;

    string public baseTokenURI = "ipfs://bafybeie4ftrooqaat2vqueh2qwdaw2pjvi24fp3houbg62p5ispfgrtrpa/";
    string public defaultTokenURI;
    uint256 public maxSupply = 2023;
    uint256 public publicSalePrice = 0 ether;
    address payable public payMent;

    mapping(address => uint256) public usermint;
    mapping(address => bool) public _blackNFTMarketList;

    constructor() ERC721A("Puppet", "Puppet") {
        payMent = payable(msg.sender);
        _safeMint(msg.sender, 1);
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }

    function mint(uint256 _quantity) external payable {
        require(_quantity <= 1, "Invalid quantity");
        require(totalSupply() + _quantity <= maxSupply, "Exceed supply");

        uint256 _remainFreeQuantity = 0;

        if (totalSupply() + _quantity <= 1000) {
            if (1 > usermint[msg.sender]) {
                _remainFreeQuantity = 1 - usermint[msg.sender];
            }
        }

        uint256 _needPayPrice = 0;
        if (_quantity > _remainFreeQuantity) {
            _needPayPrice = (_quantity - _remainFreeQuantity) * publicSalePrice;
        }

        require(msg.value >= _needPayPrice, "Ether is not enough");
        usermint[msg.sender] += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    function airdrop(
        address[] memory marketmintaddress,
        uint256[] memory mintquantity
    ) public payable onlyOwner {
        for (uint256 i = 0; i < marketmintaddress.length; i++) {
            require(
                totalSupply() + mintquantity[i] <= maxSupply,
                "Exceed supply"
            );
            _safeMint(marketmintaddress[i], mintquantity[i]);
        }
    }

    function airdropsingle(
        address[] memory marketmintaddress,
        uint256 mintquantity
    ) public payable onlyOwner {
        for (uint256 i = 0; i < marketmintaddress.length; i++) {
            require(
                totalSupply() + mintquantity <= maxSupply,
                "Exceed supply"
            );
            _safeMint(marketmintaddress[i], mintquantity);
        }
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value : address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function getHoldTokenIdsByOwner(address _owner)
    public
    view
    returns (uint256[] memory)
    {
        uint256 index = 0;
        uint256 hasMinted = _totalMinted();
        uint256 tokenIdsLen = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](tokenIdsLen);
        for (
            uint256 tokenId = 1;
            index < tokenIdsLen && tokenId <= hasMinted;
            tokenId++
        ) {
            if (_owner == ownerOf(tokenId)) {
                tokenIds[index] = tokenId;
                index++;
            }
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        string memory baseURI = _baseURI();
        return
        bytes(baseURI).length != 0
        ? string(abi.encodePacked(baseURI, _toString(tokenId), ".json"))
        : defaultTokenURI;
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

    function setPublicMintStatus(uint256 status) external onlyOwner {
        publicMintStatus = EPublicMintStatus(status);
    }


    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(!_blackNFTMarketList[operator], "Is BlackList");
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override {
        require(!_blackNFTMarketList[operator], "Is BlackList");
        super.approve(operator, tokenId);
    }

    function manage_bl(address[] calldata addresses, bool status) public onlyOwner {
        require(addresses.length < 201);
        for (uint256 i; i < addresses.length; ++i) {
            _blackNFTMarketList[addresses[i]] = status;
        }
    }

}

