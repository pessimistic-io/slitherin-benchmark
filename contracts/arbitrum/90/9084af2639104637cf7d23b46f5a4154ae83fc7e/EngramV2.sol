// SPDX-License-Identifier: MIT
// bali.xyz
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./ERC721NonTransferrableUpgradeable.sol";
import "./Errors.sol";
import "./ERC2771ContextUpgradeable.sol";
import "./IERC721.sol";

contract GapStorageV2 {
    uint256[500] private __gap;
}

contract EngramV2 is
    GapStorageV2,
    ERC721NonTransferrableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ERC2771ContextUpgradeable
{
    using ECDSAUpgradeable for bytes32;

    IMetadataContract public metadataContract;
    address public signatureVerifier;
    uint256 public tokenCount;
    mapping(address => bool) public addressHasMinted;
    mapping(address => uint256) public addressToTokenId;
    mapping(address => bool) public authorized;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder) ERC2771ContextUpgradeable(trustedForwarder) {}

    function initialize() public initializer {
        authorized[msg.sender] = true;
        __ERC721_init("Engram", "ENGRAM");
        __Pausable_init();
        __UUPSUpgradeable_init();
        _pause();
    }

    // a modifier which utilises `isTrustedForwarder` for security.
    modifier onlyTrustedForwarder() {
        if (!isTrustedForwarder(msg.sender) && !authorized[msg.sender]) revert OnlyTrustedForwarder();
        _;
    }

    modifier onlyAdmin() {
        if (!authorized[msg.sender]) revert OnlyAdmin();

        _;
    }

    modifier relayByAuthorizedEOA() {
        if (!authorized[_msgSender()]) revert RelayNotCalledByAdmin();

        _;
    }

    // _username is an optional parameter
    function mint(
        address _userAddress,
        bytes memory _encryptedEncryptedPrivateIdentifier,
        string memory _username
    ) public onlyTrustedForwarder relayByAuthorizedEOA whenNotPaused {
        if (addressHasMinted[_userAddress]) revert TokenAlreadyMinted();

        addressHasMinted[_userAddress] = true;
        addressToTokenId[_userAddress] = tokenCount;
        metadataContract.setTokenIdToEncryptedPrivateIdentifier(
            _userAddress,
            tokenCount,
            _encryptedEncryptedPrivateIdentifier
        );
        if (bytes(_username).length > 0) {
            metadataContract.setUsername(_userAddress, tokenCount, _username);
        }

        _mint(_userAddress, tokenCount);

        unchecked {
            tokenCount++;
        }
    }

    function claimUsername(
        address _userAddress,
        uint256 _tokenId,
        string memory _username
    ) public onlyTrustedForwarder whenNotPaused relayByAuthorizedEOA {
        if (_userAddress != ownerOf(_tokenId)) revert SenderDoesNotOwnToken();
        metadataContract.setUsername(_userAddress, _tokenId, _username);
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        if (id >= tokenCount) revert ("URIQueryForNonexistentToken");

        return metadataContract.getMetadata(id);
    }

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return super._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return super._msgData();
    }

    /* OWNER FUNCTIONS */
    function setMetdataContract(address _address) external onlyAdmin {
        metadataContract = IMetadataContract(_address);
    }

    function migrate(
        IERC721 _oldContract,
        uint256 totalSupply
    ) external onlyAdmin {
        for (uint256 i; i < totalSupply; i++) {
            address tokenHolder = _oldContract.ownerOf(i);
            addressHasMinted[tokenHolder] = true;
            addressToTokenId[tokenHolder] = tokenCount;
            _mint(tokenHolder, i);

            unchecked {
                tokenCount++;
            }
        }
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setAuthorized(address _address) external onlyAdmin {
        authorized[_address] = true;
    }

    function _authorizeUpgrade(address) internal override onlyAdmin {}
}

interface IMetadataContract {
    function setTokenIdToEncryptedPrivateIdentifier(
        address _address,
        uint256 _tokenId,
        bytes memory _encryptedEncryptedPrivateIdentifier
    ) external;

    function setUsername(
        address _address,
        uint256 _tokenId,
        string memory _name
    ) external;

    function getMetadata(
        uint256 _tokenId
    ) external view returns (string memory);
}

