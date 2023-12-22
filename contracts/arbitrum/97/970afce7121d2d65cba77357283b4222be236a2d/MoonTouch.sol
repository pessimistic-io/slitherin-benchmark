// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./Math.sol";
import "./Strings.sol";
import "./IAccessor.sol";

contract MoonTouch is IAccessor, Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ERC721BurnableUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    string  public baseURL;

    uint public keepalive;
    uint public offset;
    uint public transferLimit;
    uint public mintLimit;
    uint public pageLimit;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenCounter;

    mapping(bytes => bool) private _usedSignatures;
    mapping(uint => string) private _metadatas;

    event NFTCreatedEvent(address to, uint tokenId, string dna);
    event setNFTDNAEvent(uint tokenId, string dna);

    modifier onlyMinter() {
        _checkRole(MINTER_ROLE, _msgSender());
        _;
    }

    modifier onlyUpgrader() {
        _checkRole(UPGRADER_ROLE, _msgSender());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        initialize();
    }

    function initialize() initializer public {
        __ERC721_init("Moon Touch", "MT");
        __ERC721Enumerable_init();
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();

        keepalive  = 7*24*60*60;
        offset     = 3*60;
        transferLimit = 10;
        mintLimit  = 10;
        pageLimit  = 8192;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
    }

    function hasRole(bytes32 role, address account)
        public 
        view 
        override(IAccessor, AccessControlUpgradeable)
        returns (bool)
    {
        return super.hasRole(role, account);
    }


    // The following functions are overrides required by Solidity.
    function _baseURI()
        internal 
        view 
        override 
        returns (string memory) 
    {
        return baseURL;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyUpgrader 
        override
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function pause() external onlyUpgrader {
        _pause();
    }

    function unpause() external onlyUpgrader {
        _unpause();
    }

    struct NFTAsset {
        uint tokenId;
        string dna;
    }
    
    function getAssets(address owner, uint page, uint number)
        external
        view
        returns (NFTAsset[] memory)
    {
        require(page > 0, "MT: wrong page count");
        require(number <= pageLimit, "MT: number too many");

        uint size = balanceOf(owner);
        uint begin = Math.min((page-1) * number, size);
        uint tail = Math.min(begin + number, size);
        NFTAsset[] memory assets = new NFTAsset[](tail-begin);
        for (uint i = begin; i < tail; i++) {
            NFTAsset memory asset;
            asset.tokenId = tokenOfOwnerByIndex(owner, i);
            asset.dna = _metadatas[asset.tokenId];
            assets[i-begin] = asset;
        }
        return assets;
    }

    function tokenIdListByOwner(address owner,uint256 page,uint256 number)
        external
        view
        returns (uint[] memory)
    {
        require(page > 0, "MT: wrong page count");
        require(number <= pageLimit, "MT: number too many");

        uint size = balanceOf(owner);
        uint begin = Math.min((page-1) * number, size);
        uint tail = Math.min(begin + number, size);
        uint[] memory tokenIdList = new uint[](tail-begin);
        for (uint i = begin; i < tail; i++) {
            tokenIdList[i-begin] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIdList;
    }

    function setDNA(uint tokenId, string calldata dna)
        external 
        whenNotPaused 
        onlyMinter
    {
        require(_exists(tokenId), "MT: nonexistent token");
        _metadatas[tokenId] = dna;
        emit setNFTDNAEvent(tokenId, dna);
    }

    function getDNA(uint[] calldata tokenIds)
        external 
        view 
        returns(string[] memory)
    {
        string[] memory dnaList = new string[](tokenIds.length);
        for (uint i = 0; i < tokenIds.length; i++) {
            require(_exists(tokenIds[i]), "MT: nonexistent token");
            dnaList[i] = _metadatas[tokenIds[i]];
        }
        return dnaList;
    }

    function mint(address to, string calldata dna)
        public 
        whenNotPaused
        onlyMinter
    {
        uint256 tokenId = _tokenCounter.current();
        _tokenCounter.increment();
        _mint(to, tokenId);
        _metadatas[tokenId] = dna;
        emit NFTCreatedEvent(to, tokenId, dna);
    }

    function mintBatch(address to, uint256 count, string[] calldata dnaList)
        external 
        whenNotPaused 
        onlyMinter
    {
        require(count <= mintLimit, "MT: count too many");
        require(dnaList.length == count, "MT: data length error");
        for (uint i = 0; i < count; i++) {
            mint(to, dnaList[i]);
        }
    }

    function batchTransferFrom(uint256[] memory tokenIds, address from, address to)
        external
        whenNotPaused
    {
        for (uint i = 0; i < tokenIds.length; i++) {
            transferFrom(from, to, tokenIds[i]);
        }
    }

    function setTransferLimit(uint newValue)
        external 
        onlyMinter
    {
        require(newValue > 1, "MT: failed to set transfer limit");
        transferLimit = newValue;
    }

    function setPageLimit(uint newValue)
        external 
        onlyMinter
    {
        require(newValue > 1, "MT: failed to set page limit");
        pageLimit = newValue;
    }

    function setMintLimit(uint newValue)
        external
        onlyMinter
    {
        require(newValue > 1, "MT: failed to set mint limit");
        mintLimit = newValue;
    }

    function setKeepalive(uint newValue)
        external
        onlyMinter
    {
        require(newValue > 1*60, "MT: failed to set signature keepalive");
        keepalive = newValue;
    }

    function setOffset(uint newValue)
        external 
        onlyMinter
    {
        require(newValue > 1*60, "MT: failed to set timestamp offset");
        offset = newValue;
    }
    
  
    function setBaseURL(string memory newValue)
        external 
        onlyMinter
    {
        baseURL = newValue;
    }

    function tokenURI(uint256 tokenId)
        public 
        view 
        override 
        returns (string memory)
    {
        require(_exists(tokenId), "MT: nonexistent token");
        return super.tokenURI(tokenId);
        // return string(
        //     abi.encodePacked(
        //         _baseURL, 
        //         "?tokenId=", tokenId, 
        //         "&metadata=", _metadatas[tokenId])
        //     )
        // ;
        //return string.concat(_baseURL, Strings.toString(tokenId));
    }

    function cancelSignature(address from, address to, uint[] calldata tokenIdList, uint chainId, uint timestamp, bytes calldata signature)
        external
        whenNotPaused
    {
        require(!_usedSignatures[signature], "MT: signature used.");

        bytes32 messageHash = getMessageHash(from, to, tokenIdList, chainId, timestamp);
        bytes32 signedMessageHash = getEthSignedMessageHash(messageHash);
        require(_msgSender() == recoverSigner(signedMessageHash, signature), "MT: signature is not from msg.sender");
        _usedSignatures[signature] = true;
    }

    function noGasTransfer(address from, address to, uint[] calldata tokenIdList, uint chainId, uint timestamp, bytes calldata signature)
        external 
        whenNotPaused
    {
        require(!_usedSignatures[signature], "MT: signature used.");
        require(timestamp + keepalive > block.timestamp && timestamp < block.timestamp+offset, "MT: signature is overtime");
        require(block.chainid == chainId, "MT: chain id error ");
        require(tokenIdList.length <= transferLimit, "MT: too many");

        bytes32 messageHash = getMessageHash(from, to, tokenIdList, chainId, timestamp);
        bytes32 signedMessageHash = getEthSignedMessageHash(messageHash);
        require(from == recoverSigner(signedMessageHash, signature), "MT: signature is not from signer");

        for (uint i; i < tokenIdList.length; i++) {
            _transfer(from, to, tokenIdList[i]);
        }
        _usedSignatures[signature] = true;
    }

    function getMessageHash(address from, address to, uint[] calldata tokenIdList, uint chainId, uint timestamp) 
        public 
        pure 
        returns(bytes32)
    {
        return keccak256(abi.encode(from, to, tokenIdList, chainId, timestamp));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) 
        public 
        pure 
        returns (bytes32)
    {
        /*
            Signature is produced by signing a keccak256 hash with the following format:
            "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        private
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        private
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "MT: invalid signature length");

        assembly {
            /*
                First 32 bytes stores the length of the signature

                add(sig, 32) = pointer of sig + 32
                effectively, skips first 32 bytes of signature

                mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

    }
}
