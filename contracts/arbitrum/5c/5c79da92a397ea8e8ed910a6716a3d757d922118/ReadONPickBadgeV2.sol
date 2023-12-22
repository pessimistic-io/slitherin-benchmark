// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./ECDSA.sol";
import "./Strings.sol";

contract ReadONPickBadgeV2 is Initializable, ERC721Upgradeable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC721_init("Pick", "Pick");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    struct PickInfo {
        uint256 contentId;
        string points;
        string rate;
    }

    using ECDSA for bytes32;
    //using Strings for uint256;

    address private signer;

    mapping(uint256 => PickInfo) private pickData;
    
    function getPickData(uint256 tokenId)external view returns (PickInfo memory pickInfo) {
        return pickData[tokenId];
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://readon-api.readon.me/v1/metadata/vote/";
    }

    function safeMint(uint256 tokenId,uint256 contentId,string memory points,string memory rate,string memory p4, bytes memory signature)
        public
    {
        require(verifySignature(p4,signature),"ReadON:invalid signature");
        _safeMint(msg.sender, tokenId);
        pickData[tokenId] = PickInfo(contentId,points,rate);
    }

    function setSigner(address _signer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function getSigner() external view returns (address) {
        return signer;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal whenNotPaused override {
        require(
            from == address(0),
            "ReadON: Token transfer not allowed"
        );
        super._beforeTokenTransfer(from, to, tokenId,batchSize);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function verifySignature(string memory message, bytes memory signature) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(message));
        bytes32 prefixedHash = messageHash.toEthSignedMessageHash();
        
        address recoveredSigner = prefixedHash.recover(signature);
        
        return (recoveredSigner == signer);
    }
}

