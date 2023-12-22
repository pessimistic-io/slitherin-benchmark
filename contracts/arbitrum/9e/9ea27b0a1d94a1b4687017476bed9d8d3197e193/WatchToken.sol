// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;
import "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Pausable.sol";
import "./ERC2981.sol";
import "./DefaultOperatorFilterer.sol";

contract WatchToken is
    ERC721,
    Ownable,
    DefaultOperatorFilterer,
    Pausable,
    ERC2981
{
    struct TokenInfo {
        uint256 tokenId;
        string tokenURI;
        address owner;
    }

    string public baseURI;

    mapping(uint256 => string) private _tokenURIs;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    bytes32 public DOMAIN_SEPARATOR;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        address multisigAddress,
        address splitAddress,
        uint96 _royaltyFeesInBips
    ) ERC721(_name, _symbol) {
        baseURI = _baseURI;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        Ownable.transferOwnership(multisigAddress);

        ERC2981._setDefaultRoyalty(splitAddress, _royaltyFeesInBips);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC2981, ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Pausable
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    // DefaultOperatorFilterer

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
        whenNotPaused
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override
        onlyAllowedOperatorApproval(operator)
        whenNotPaused
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) whenNotPaused {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) whenNotPaused {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) public override onlyAllowedOperator(from) whenNotPaused {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // ERC-721

    function safeMint(address to, string memory tokenURI_) external onlyOwner {
        _safeMint(to, _tokenIds.current());
        _setTokenURI(_tokenIds.current(), tokenURI_);
        _tokenIds.increment();
    }

    function _checkSignature(
        bytes32 hashedData,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private view {
        require(deadline >= block.timestamp, "Watch Token: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        keccak256("Msg(bytes32 hashedData,uint256 deadline)"),
                        hashedData,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == msg.sender,
            "Watch Token: INVALID_SIGNATURE"
        );
    }

    function burn(uint256 tokenId) external onlyOwner {
        require(
            _ownerOf[tokenId] == Ownable.owner(),
            "Watch Token: TOKEN_OWNER_NOT_CONTRACT_OWNER"
        );
        _burn(tokenId);
    }

    function transferToContractOwner(
        bytes32 hashedData,
        uint256 deadline,
        uint256 tokenId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _checkSignature(hashedData, deadline, v, r, s);
        super.transferFrom(msg.sender, Ownable.owner(), tokenId);
    }

    function setTokenURI(uint256 tokenId, string memory tokenURI_)
        external
        onlyOwner
    {
        _setTokenURI(tokenId, tokenURI_);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) private {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return ownerOf(tokenId) != address(0);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI query for nonexistent token"
        );

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(baseURI).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        return string(abi.encodePacked(baseURI, _tokenURI));
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current();
    }

    function tokenInfo(uint256 tokenId) public view returns (TokenInfo memory) {
        address tokenOwner = ownerOf(tokenId);
        string memory tokenUri = tokenURI(tokenId);
        return TokenInfo(tokenId, tokenUri, tokenOwner);
    }
}

