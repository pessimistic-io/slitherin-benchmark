// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC2981.sol";
import "./Ownable.sol";
import "./Base64.sol";
import "./console.sol";

contract PNFT is ERC721, ERC2981, ERC721Enumerable, Ownable {
    event MetadataChanged(uint256 indexed tokenId, string key, string oldValue, string newValue);
    event MetadataChanged(uint256 indexed tokenId, string key, string[] oldValue, string[] newValue);

    event MintNameAllowed(string name);
    event MintNameDisallowed(string name);
    event Minted(string indexed name);

    uint256 private _nextTokenId;

    struct TokenMetadata {
        string name;
        string imageUrl;
        string[] otherImageUrls;
        string description;
        string externalUrl;
    }

    mapping(uint256 => TokenMetadata) private _tokenMetadata;

    mapping(string => bool) private _allowMintName;

    uint256 private _mintAmount;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        // 5% royalty - where ERC2981::feeDenominator defaults to 10,000. So with number set to 500, you get 500 / 10,000, or 5%.
        _setDefaultRoyalty(address(this), 500);
    }

    /**
     * can only mint on a given 'name' once if it has been previously allowed via `allowName()`
     */
    function mint(address to, string calldata name) external payable {
        require(_allowMintName[name], "Provided name is not allowed");
        require(msg.value >= _mintAmount, "Insufficient eth provided for minting fee");

        _allowMintName[name] = false;

        uint256 tokenId = _nextTokenId++;
        _tokenMetadata[tokenId] = TokenMetadata(name, "", new string[](0), "", "");

        _safeMint(to, tokenId);
        emit Minted(name);
    }

    function setMintAmount(uint256 mintAmount) external onlyOwner {
        _mintAmount = mintAmount;
    }

    /**
     * @param feeNumerator Example: 500 for 5% royalty - where ERC2981::feeDenominator defaults to 10,000. So with number set to 500, you get 500 / 10,000, or 5%
     */
    function setDefaultRoyalty(uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(address(this), feeNumerator);
    }

    function allowMintName(string memory name) external onlyOwner {
        _allowMintName[name] = true;
        emit MintNameAllowed(name);
    }

    /**
     * Performed during mint impl (typical) or by owner/governance (to undo a prior action, should be infrequent)
     */
    function disallowMintName(string memory name) external onlyOwner {
        _allowMintName[name] = false;
        emit MintNameDisallowed(name);
    }

    function getName(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenMetadata[tokenId].name;
    }

    function getImageUrl(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenMetadata[tokenId].imageUrl;
    }

    function getOtherImageUrls(uint256 tokenId) external view returns (string[] memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenMetadata[tokenId].otherImageUrls;
    }

    function getDescription(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenMetadata[tokenId].description;
    }

    function getExternalUrl(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenMetadata[tokenId].externalUrl;
    }

    function setName(uint256 tokenId, string calldata value) external onlyOwner {
        require(_exists(tokenId), "ERC721: invalid token ID");
        string memory oldValue = _tokenMetadata[tokenId].name;
        _tokenMetadata[tokenId].name = value;
        emit MetadataChanged(tokenId, "name", oldValue, value);
    }

    function setExternalUrl(uint256 tokenId, string calldata value) external onlyOwner {
        require(_exists(tokenId), "ERC721: invalid token ID");
        string memory oldValue = _tokenMetadata[tokenId].externalUrl;
        _tokenMetadata[tokenId].externalUrl = value;
        emit MetadataChanged(tokenId, "externalUrl", oldValue, value);
    }

    function setImageUrl(uint256 tokenId, string calldata value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");
        string memory oldValue = _tokenMetadata[tokenId].imageUrl;
        _tokenMetadata[tokenId].imageUrl = value;
        emit MetadataChanged(tokenId, "imageUrl", oldValue, value);
    }

    /**
     * @dev Performs setImageUrl() and additionally adds the oldValue to otherImageUrls
     */
    function setImageUrlHist(uint256 tokenId, string calldata value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");
        string memory oldValue = _tokenMetadata[tokenId].imageUrl;
        _tokenMetadata[tokenId].imageUrl = value;
        _tokenMetadata[tokenId].otherImageUrls.push(oldValue);

        emit MetadataChanged(tokenId, "imageUrl", oldValue, value);
        emit MetadataChanged(tokenId, "addOtherImageUrls", "", oldValue);
    }

    function setDescription(uint256 tokenId, string calldata value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");

        string memory oldValue = _tokenMetadata[tokenId].description;
        _tokenMetadata[tokenId].description = value;
        emit MetadataChanged(tokenId, "description", oldValue, value);
    }

    /**
     *  Uses lots of gas, wish otherImageUrls could be calldata.  if so here's the compilation error:
     *
     *  Error: Unimplemented feature (/solidity/libsolidity/codegen/ArrayUtils.cpp:195):Copying nested calldata dynamic arrays to storage is not implemented in the old code generator.
     */
    function setOtherImageUrls(uint256 tokenId, string[] memory value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");
        string[] memory oldValue = _tokenMetadata[tokenId].otherImageUrls;
        _tokenMetadata[tokenId].otherImageUrls = value;
        emit MetadataChanged(tokenId, "otherImageUrls", oldValue, value);
    }

    function setOtherImageUrl(uint256 tokenId, uint256 index, string calldata value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");
        string memory oldValue = _tokenMetadata[tokenId].otherImageUrls[index];
        _tokenMetadata[tokenId].otherImageUrls[index] = value;
        emit MetadataChanged(tokenId, "setOtherImageUrl", oldValue, value);
    }

    function addOtherImageUrl(uint256 tokenId, string calldata value) external {
        require(_exists(tokenId), "ERC721: invalid token ID");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not NFT owner nor approved");
        _tokenMetadata[tokenId].otherImageUrls.push(value);
        emit MetadataChanged(tokenId, "addOtherImageUrl", "", value);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");

        TokenMetadata memory data = _tokenMetadata[tokenId];
        string memory json = "{";
        string memory separator = "";

        if (bytes(data.name).length > 0) {
            json = string(abi.encodePacked(json, separator, '"name":"', data.name, '"'));
            separator = ",";
        }

        if (bytes(data.imageUrl).length > 0) {
            json = string(abi.encodePacked(json, separator, '"imageUrl":"', data.imageUrl, '"'));
            separator = ",";
        }

        if (data.otherImageUrls.length > 0) {
            string memory otherImageUrls = "";

            for (uint256 i = 0; i < data.otherImageUrls.length; i++) {
                if (bytes(data.otherImageUrls[i]).length > 0) {
                    otherImageUrls =
                        string(abi.encodePacked(otherImageUrls, i != 0 ? ',"' : '"', data.otherImageUrls[i], '"'));
                }
            }

            json = string(abi.encodePacked(json, separator, '"otherImageUrls":[', otherImageUrls, "]"));
            separator = ",";
        }

        if (bytes(data.description).length > 0) {
            json = string(abi.encodePacked(json, separator, '"description":"', data.description, '"'));
            separator = ",";
        }

        if (bytes(data.externalUrl).length > 0) {
            json = string(abi.encodePacked(json, separator, '"externalUrl":"', data.externalUrl, '"'));
        }

        json = string(abi.encodePacked(json, "}"));

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // Multiple inheritance boilerplate
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}

