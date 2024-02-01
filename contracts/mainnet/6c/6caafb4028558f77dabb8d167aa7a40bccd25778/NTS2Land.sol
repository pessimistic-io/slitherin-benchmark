// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721EnumerableUpgradeable} from "./ERC721EnumerableUpgradeable.sol";
import {IERC721Upgradeable, ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "./ERC2981Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {UpdatableOperatorFiltererUpgradeable} from "./UpdatableOperatorFiltererUpgradeable.sol";

import {IByteContract} from "./IByteContract.sol";

import {NTConfig, NTComponent} from "./NTConfig.sol";


contract NTS2Land is
    Initializable,
    UUPSUpgradeable,
    ERC2981Upgradeable,
    ERC721EnumerableUpgradeable,
    UpdatableOperatorFiltererUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
 {
    mapping(address => bool) public admins;
    bool landMintActive;
    uint16 boughtLandOffset;
    uint16 currentId;

    // TODO: use config
    address identityContract;
    address bytesContract;

    address v1OuterLandContract;
    NTConfig config;
    uint256 landCost;

    bytes32[] _rootHash;


    // Mapping for identity tokenIds that have previously claimed
    mapping(uint256 => uint256) private _identityClaims;

    // Mapping to look up what identity minted a specific token
    mapping(uint256 => uint256) private _tokenMintedByIdentity;

    function initialize(uint16 boughtLandOffset_, address config_, address registry, address subscriptionOrRegistrantToCopy) external initializer
    {
        __ERC721_init("Neo Tokyo Outer Land Deeds V2", "NTOLD");
        __ERC2981_init();
        __ReentrancyGuard_init();
        __UpdatableOperatorFiltererUpgradeable_init(
            registry,
            subscriptionOrRegistrantToCopy,
            true
        );
        __Ownable_init();

        config = NTConfig(config_);
        boughtLandOffset = boughtLandOffset_;
        landCost = 500 ether;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC2981Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            ERC2981Upgradeable.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    function getLocation(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory output;

        output = config.getLocation(tokenId);

        return output;
    }

    function getTokenClaimedByIdentityTokenId(uint256 identityTokenId) public view returns (uint256) {
        uint256 token = NTS2Land(v1OuterLandContract).getTokenClaimedByIdentityTokenId(identityTokenId);

        if(token > 0){
            return token;
        }
        return _identityClaims[identityTokenId];
    }

    function getClaimantIdentityIdByTokenId(uint256 tokenId) public view returns (uint256) {
        uint256 claimant = NTS2Land(v1OuterLandContract).getClaimantIdentityIdByTokenId(tokenId);
        
        if(claimant > 0){
            return claimant;
        }
        return _tokenMintedByIdentity[tokenId];
    }

    function setV1OuterLandContract(address _address) external onlyOwner {
        v1OuterLandContract = _address;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory output;

        output = config.tokenURI(tokenId);

        return output;
    }

    function landClaim(
        uint256 identityTokenId,
        uint256 spotOnLeaderboard,
        uint256 spotInWhitelist,
        bytes32[] memory proof
    ) public nonReentrant {
        require(landMintActive, "Minting is not currently active");
        require(
            whitelistValidated(identityTokenId, spotOnLeaderboard, spotInWhitelist, proof),
            "That identity cannot claim that land"
        );
        require(identityValidated(identityTokenId), "You are not the owner of that identity");

        _safeMint(_msgSender(), spotOnLeaderboard);

        //Set the _identityClaims value to spotOnLeaderboard for this identity so the identity cannot mint again
        _identityClaims[identityTokenId] = spotOnLeaderboard;

        //Set the identity that minted this token for reverse lookup
        _tokenMintedByIdentity[spotOnLeaderboard] = identityTokenId;
    }

    function buyLand() public nonReentrant {
        IByteContract bytes_ = IByteContract(config.bytesContract());
        require(address(bytes_) != address(0), "Bytes contract not set");
        require(landMintActive, "Land cannot be bought yet");
        bytes_.burn(_msgSender(), landCost);
        _safeMint(_msgSender(), ++currentId + boughtLandOffset);
    }

    function migrateAsset(address sender, uint256 tokenId) public nonReentrant {
        require(_msgSender() == config.migrator(), "msg.sender must be migrator");

        IERC721Upgradeable v1Contract = IERC721Upgradeable(config.findComponent(NTComponent.S2_LAND, false));
        require(v1Contract.ownerOf(tokenId) == sender, "You do not own this token");

        v1Contract.transferFrom(sender, address(this), tokenId);
        _safeMint(sender, tokenId);
    }

    function adminClaim(uint256 tokenId, address receiver) public nonReentrant {
        require(admins[msg.sender], "Only admins can adminClaim");
        require(!_exists(tokenId), "Token already exists");
        _safeMint(receiver, tokenId);
    }

    function toggleAdmin(address adminToToggle) public onlyOwner {
        admins[adminToToggle] = !admins[adminToToggle];
    }

    function identityValidated(uint256 identityId) internal view returns (bool) {
        require(getTokenClaimedByIdentityTokenId(identityId) == 0, "This identity has minted");
        IERC721Enumerable identityEnumerable = IERC721Enumerable(identityContract);
        return (identityEnumerable.ownerOf(identityId) == _msgSender());
    }

    function whitelistValidated(uint256 identityTokenId, uint256 leaderboardSpot, uint256 index, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        // Compute the merkle root
        bytes32 node = keccak256(abi.encodePacked(index, identityTokenId, leaderboardSpot));
        uint256 path = index;
        for (uint16 i = 0; i < proof.length; i++) {
            if ((path & 0x01) == 1) {
                node = keccak256(abi.encodePacked(proof[i], node));
            } else {
                node = keccak256(abi.encodePacked(node, proof[i]));
            }
            path /= 2;
        }

        // Check the merkle proof against the root hash array
        for (uint256 i = 0; i < _rootHash.length; i++) {
            if (node == _rootHash[i]) {
                return true;
            }
        }

        return false;
    }

    function setLandMintActive() public onlyOwner {
        landMintActive = !landMintActive;
    }

    function setLandCost(uint256 _cost) public onlyOwner {
        landCost = _cost;
    }

    function setIdentityContract(address contractAddress) public onlyOwner {
        identityContract = contractAddress;
    }

    function setBytesAddress(address contractAddress) public onlyOwner {
        bytesContract = contractAddress;
    }

    //_newRoyalty is in basis points out of 10,000
    function adjustDefaultRoyalty(address _receiver, uint96 _newRoyalty) public onlyOwner {
        _setDefaultRoyalty(_receiver, _newRoyalty);
    }

    //_newRoyalty is in basis points out of 10,000
    function adjustSingleTokenRoyalty(uint256 _tokenId, address _receiver, uint96 _newRoyalty) public onlyOwner {
        _setTokenRoyalty(_tokenId, _receiver, _newRoyalty);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    )
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    )
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    )
        public
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function setConfig(address config_) external onlyOwner {
        config = NTConfig(config_);
    }

    function owner() public view override(OwnableUpgradeable, UpdatableOperatorFiltererUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }

}

