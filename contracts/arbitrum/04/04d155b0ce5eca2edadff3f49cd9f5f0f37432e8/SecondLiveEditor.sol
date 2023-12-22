pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./ERC2981.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";
import "./AccessControl.sol";
import "./ISecondLiveEditor.sol";

contract SecondLiveEditor is
    AccessControl,
    ERC721Enumerable,
    ISecondLiveEditor,
    ERC2981,
    Ownable,
    ReentrancyGuard
{
    using Strings for uint256;

    bool private initialized;
    string private baseURI;

    uint256 private _tokenId;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    mapping(uint256 => Attribute) public attributes;

    string constant ROLE_MINTER_STR = "ROLE_MINTER";
    
    // 0xaeaef46186eb59f884e36929b6d682a6ae35e1e43d8f05f058dcefb92b601461
    bytes32 constant ROLE_MINTER = keccak256(bytes(ROLE_MINTER_STR));

    string constant ROLE_MINTER_ADMIN_STR = "ROLE_MINTER_ADMIN";

    // 0xc30b6f1bcbf41750053d221187e3d61595d548191e1ee1cab3dd3ae1dc469c0a
    bytes32 constant ROLE_MINTER_ADMIN =
        keccak256(bytes(ROLE_MINTER_ADMIN_STR));

    event SecondLiveAvatarMint(
        address indexed account,
        uint256 indexed tokenId,
        Attribute attribute
    );

    event UpdateAttribute(uint256 indexed tokenId, Attribute attribute);

    event URIPrefix(string indexed baseURI);

    event SetMinterAdmin(bytes32 role, bytes32 adminRole, address admin);

    event DefaultRoyalty(address indexed receiver, uint96 indexed feeNumerator);

    event UpdateTokenRoyalty(
        uint256 indexed tokenId,
        address receiver,
        uint96 feeNumerator
    );

    event SetTokenURI(uint256 indexed tokenId, string uri);

    constructor() ERC721("BASICAVATAR.SECONDLIVE", "BASICAVATAR") {
    }

    function initialize(address _owner) external {
        require(!initialized, "initialize: Already initialized!");
        _transferOwnership(_owner);
        baseURI = "https://api.secondlive.world/api/v1/erc721/metadata/v2/editor_avatar_arb/arbOne/";
        _setRoleAdmin(ROLE_MINTER, ROLE_MINTER_ADMIN);
        _setupRole(ROLE_MINTER_ADMIN, _owner);
        
        initialized = true;
    }


    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC2981, ERC721Enumerable, IERC165, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setMinterAdmin(address factory) external onlyOwner {
        _setupRole(ROLE_MINTER_ADMIN, factory);
        emit SetMinterAdmin(ROLE_MINTER, ROLE_MINTER_ADMIN, factory);
    }

    function mint(
        address to,
        Attribute calldata attribute
    ) external override nonReentrant returns (uint256) {
        require(
            hasRole(ROLE_MINTER, msg.sender),
            "SecondLiveEditor: Caller is not a minter"
        );

        _tokenId++;
        attributes[_tokenId] = attribute;
        _mint(to, _tokenId);

        emit SecondLiveAvatarMint(to, _tokenId, attribute);

        return _tokenId;
    }

    function burn(uint256 _id) external {
        require(
            _isApprovedOrOwner(_msgSender(), _id),
            "ERC721: burn caller is not owner nor approved"
        );
        _burn(_id);

        _resetTokenRoyalty(_id);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[_id]).length != 0) {
            delete _tokenURIs[_id];
        }
    }

    function updateAttribute(
        uint256 tokenId,
        Attribute memory attribute
    ) external onlyOwner {
        require(_exists(tokenId), "SecondLiveEditor: nonexistent token");
        attributes[tokenId] = attribute;
        emit UpdateAttribute(tokenId, attribute);
    }

    function getAttribute(
        uint256 id
    ) external view override returns (Attribute memory attribute) {
        require(_exists(id), "SecondLiveEditor: nonexistent token");
        attribute = attributes[id];
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
        emit DefaultRoyalty(address(0), 0);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external override {
        require(
            (owner() == _msgSender() || hasRole(ROLE_MINTER, _msgSender())),
            "SecondLiveEditor: caller no permission!!!"
        );
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit UpdateTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
        emit UpdateTokenRoyalty(tokenId, address(0), 0);
    }

    function updateURIPrefix(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit URIPrefix(baseURI);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function updateTokenURI(
        uint256 tokenId,
        string memory _uri
    ) public onlyOwner {
        _setTokenURI(tokenId, _uri);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) internal virtual {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
        emit SetTokenURI(tokenId, _tokenURI);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(
            _exists(tokenId),
            "SecondLiveEditor: URI query for nonexistent token"
        );
        string memory baseURI_ = _baseURI();
        // return string(abi.encodePacked(baseURI_, tokenId.toString()));

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(baseURI_).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(baseURI_, tokenId.toString()));
    }


    function name() public view virtual override returns (string memory) {
        return "BASICAVATAR.SECONDLIVE";
    }

    function symbol() public view virtual override returns (string memory) {
        return "BASICAVATAR";
    }
}

