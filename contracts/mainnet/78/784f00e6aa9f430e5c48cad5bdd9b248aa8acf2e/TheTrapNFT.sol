// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./draft-EIP712Upgradeable.sol";

import { IERC2981Upgradeable, IERC165Upgradeable } from "./IERC2981Upgradeable.sol";


contract TheTrapNFT is 
    Initializable,
    ERC721Upgradeable,
    EIP712Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    IERC2981Upgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    string private constant SIGNING_DOMAIN = "TheTrapNFTSigning";
    string private constant SIGNING_VERSION = "1";
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    CountersUpgradeable.Counter private _tokenIdCounter;

    uint256 public whiteListMintPrice;
    uint256 public publicMintPrice;

    bool public publicMintEnable;
    bool public whiteListMintEnable;

    uint256 public maxMintPerWallet;

    mapping(address => uint256) public mintedPerAddress;
    // Base URI
    string private _baseTokenURI;

    struct LazyTheTrapDatas {
        uint256 nonce;
        string[] uri;
        address to;
        bytes signature;
    }
    mapping(address => mapping(uint256 => bool)) private checkTxNonce;
    mapping(address => bool) private whiteList;

    event ItemCreated(uint256 _id, address _owner);
    event ItemsCreated(uint256[] _ids, address _owner);

    address public fundReceiver;
    address public royalties;

    function initialize() public initializer {
        __ERC721_init("TheTrapNFT", "TheTrapNFT");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __EIP712_init(SIGNING_DOMAIN, SIGNING_VERSION);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        whiteListMintPrice = 0;
        publicMintPrice = 0;
        maxMintPerWallet = 2;
        fundReceiver = 0x42E7f0BCA0bF3E0742Bb44949B762B2d8a19E947;
        royalties = 0x42E7f0BCA0bF3E0742Bb44949B762B2d8a19E947;
    }

    modifier onlyWhiteList() {
        require(whiteList[msg.sender], "TheTrapNFT: not in white list");
        _;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function isWhiteList(address _addr) public view returns (bool) {
        return whiteList[_addr];
    }

    function setRoyalties(address _royalties) public onlyRole(DEFAULT_ADMIN_ROLE) {
        royalties = _royalties;
    }

    function setWhiteList(address[] calldata _ads, bool _isWhiteList)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        for (uint256 i = 0; i < _ads.length; i++) {
            whiteList[_ads[i]] = _isWhiteList;
        }
        return _isWhiteList;
    }

    function setWhiteListMintPrice(uint256 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        whiteListMintPrice = _price;
    }

    function setPublicMintPrice(uint256 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        publicMintPrice = _price;
    }

    function setPublicMintEnable(bool _isEnable)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        publicMintEnable = _isEnable;
    }

    function setWhiteListMintEnable(bool _isEnable)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        whiteListMintEnable = _isEnable;
    }

    function setAddressFundReciver(address _addr)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        fundReceiver = _addr;
    }

    function setMaxMintPerWallet(uint256 _maxMintPerWallet) external onlyRole(DEFAULT_ADMIN_ROLE){
        maxMintPerWallet = _maxMintPerWallet;
    }

    function safeMint(address to, string memory uri)
        public
        onlyRole(MINTER_ROLE)
    {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function baseURI() public view returns (string memory) {
        return _baseURI();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseURI_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(tokenId);
    }

    function allTokenIdsOf(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function mint(LazyTheTrapDatas calldata lzdatas)
        external
        payable
        whenNotPaused
        returns (uint256[] memory)
    {
        address signer = _verify(lzdatas);
        
        require(
            hasRole(MINTER_ROLE, signer),
            "TheTrapNFT: Signature invalid or unauthorized"
        );

        require(
            checkTxNonce[lzdatas.to][lzdatas.nonce] == false,
            "TheTrapNFT: Replay attacks"
        );

        uint256 price;

        require(
            publicMintEnable || whiteListMintEnable,
            "TheTrapNFT: Not open for mint"
        );

        require(mintedPerAddress[msg.sender] < maxMintPerWallet, "TheTrapNFT: Minted enough NFT");

        if (whiteListMintEnable) {
            require(whiteList[msg.sender], "TheTrapNFT: Not in the whitelist");
            price = whiteListMintPrice;
        } else {
            price = publicMintPrice;
        }

        uint256 paymentAmount = lzdatas.uri.length * price;

        require(msg.value == paymentAmount, "TheTrapNFT: Money transfer error");

        if (paymentAmount > 0) {
            payable(fundReceiver).transfer(msg.value);
        }

        //Mint and store NFT data
        uint256[] memory ids = new uint256[](lzdatas.uri.length);
        for (uint256 i = 0; i < lzdatas.uri.length; i++) {
            require(mintedPerAddress[msg.sender] < maxMintPerWallet,"TheTrapNFT: Minted enough NFT");
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(lzdatas.to, tokenId);
            _setTokenURI(tokenId, lzdatas.uri[i]);
            ids[i] = tokenId;
            mintedPerAddress[msg.sender]++;
        }

        checkTxNonce[lzdatas.to][lzdatas.nonce] = true;

        emit ItemsCreated(ids, lzdatas.to);

        return ids;
    }

    function _hash(LazyTheTrapDatas calldata lzdatas)
        internal
        view
        returns (bytes32)
    {
        bytes32[] memory _array = new bytes32[](lzdatas.uri.length);
        for (uint256 i = 0; i < lzdatas.uri.length; i++) {
            _array[i] = keccak256(bytes(lzdatas.uri[i]));
        }
        bytes32 result = keccak256(abi.encodePacked(_array));

        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "LazyTheTrapDatas(uint256 nonce,string[] uri,address to)"
                        ),
                        lzdatas.nonce,
                        result,
                        lzdatas.to
                    )
                )
            );
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function _verify(LazyTheTrapDatas calldata lzdatas)
        internal
        view
        returns (address)
    {
        bytes32 digest = _hash(lzdatas);
        return ECDSAUpgradeable.recover(digest, lzdatas.signature);
    }

    receive() external payable {}

    function clearStuckBalance() external {
        payable(fundReceiver).transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, IERC165Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IERC2981Upgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    // IERC2981

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view override returns (address, uint256 royaltyAmount) {
        _tokenId; // silence solc warning
        royaltyAmount = (_salePrice / 100) * 5;
        return (royalties, royaltyAmount);
    }

}

