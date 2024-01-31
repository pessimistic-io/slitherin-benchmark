// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721EnumerableUpgradeable} from "./ERC721EnumerableUpgradeable.sol";
import {IERC721Upgradeable, ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "./IERC721ReceiverUpgradeable.sol";
import {ERC2981Upgradeable} from "./ERC2981Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {UpdatableOperatorFiltererUpgradeable} from "./UpdatableOperatorFiltererUpgradeable.sol";

import {IByteContract} from "./IByteContract.sol";

import {NTConfig, NTComponent} from "./NTConfig.sol";
import {IComponent} from "./IComponent.sol";
import {IMintContract} from "./IMintContract.sol";

contract NTS2Citizen is
    Initializable,
    UUPSUpgradeable,
    ERC2981Upgradeable,
    ERC721EnumerableUpgradeable,
    IERC721ReceiverUpgradeable,
    UpdatableOperatorFiltererUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bool citizenMintActive;
    bool boughtIdentitiesActive;
    bool public femaleActive;
    bool public raceOverrideActive;
    uint16 currentId;

    address v1Contract;
    NTConfig config;

    uint72 public mintedIdentityCost;
    uint72 public changeGenderCost;
    uint72 public changeSpecialMessageCost;
    uint72 public humanRaceChangeCost;
    uint32 creationTime;

    address proxyRegistryAddress;

    // Every citizen information besides the special message & possibly reward rate
    // can be stored within 192 bits.
    // This does make SOME assumptions that might need to be corrected maybe a few
    // thousand years into the future.
    // 1) assumes 64-bit unsigned integer for timestamp (should be enough for our life time)
    // 2) 32-bit unsigned integers for identity, item cache, and land deeds. This would put a cap at around 4 billion...should be good for at least a few years.
    // 3) 16-bit unsigned integer for vaults. There is enough room for a 32-bit integer here, but vaults are capped at 2500. Max would be around 32,000.
    // 4) assumes human race override can fit within 256 values.
    // By storing it all in one mapping it reduces  the number of SSTORE calls,
    // which end up saving around ~100k gas. Using a struct vs int-packing ends up adding negligible extra costs.
    // There's likely some runtime overhead for reading & writing structs from/to storage.
    // But it's not an insanely high extra-cost so we're good to use a struct.
    // We do use bit-flags for migrated citizens and females however.
    mapping(uint256 => CitizenData) public citizenData;

    // Mapping for special messages uploaded when a citizen was created
    mapping(uint256 => string) private _specialMessageByCitizenId;

    // Flag used if
    uint8 constant FEMALE_FLAG = 0x01;
    uint8 constant MIGRATED_FLAG = 0x02;
    uint8 constant SPECIAL_MESSAGE_UPDATED = 0x04;

    CitizenData MIGRATED_CITIZEN;

    struct CitizenData {
        /* This gets packed into 1 storage slots  */
        // 32 + 32 + 32 + 16 + 64 + 8 + 8 = 192
        uint64 creationTime;
        /* uint32 has a maximum value of over 4.2 billion which should be more than enough */
        /* if it's not...well we can upgrade in a few centuries */
        uint32 identityId;
        uint32 itemCacheId;
        uint32 landDeedId;
        // vault supply is unchanging so can be converted to a uint16 (max of 32k)
        uint16 vaultId;
        uint8 humanRace;
        // One uint8 for flags such as migrated & female. We could probably squeeze human race
        // override into flags but for now i think it'll be easier to just keep it separate
        uint8 flags;
    }

    function initialize(
        uint16 currentId_,
        address config_,
        address registry,
        address subscriptionOrRegistrantToCopy
    ) external initializer {
        __ERC721_init("Neo Tokyo Outer Citizen V2", "NTOCTZN");
        __ERC2981_init();
        __ReentrancyGuard_init();
        __UpdatableOperatorFiltererUpgradeable_init(
            registry,
            subscriptionOrRegistrantToCopy,
            true
        );
        __Ownable_init();

        config = NTConfig(config_);
        currentId = currentId_;
        creationTime = uint32(block.timestamp);

        // mintedIdentityCost = 2000 ether;
        changeGenderCost = 25 ether;
        changeSpecialMessageCost = 10 ether;
        humanRaceChangeCost = 10 ether;
        MIGRATED_CITIZEN = CitizenData(0, 0, 0, 0, 0, 0, MIGRATED_FLAG);
    }

    function _packCitizenDataStruct(
        uint64 _creationTime,
        uint32 identityId,
        uint32 itemCacheId,
        uint32 landDeedId,
        uint8 humanRace,
        uint8 flags
    ) internal pure returns (CitizenData memory citizen) {
        citizen.creationTime = _creationTime;
        citizen.identityId = identityId;
        citizen.itemCacheId = itemCacheId;
        citizen.landDeedId = landDeedId;
        citizen.humanRace = humanRace;
        citizen.flags = flags;
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

    function getIdentityIdOfTokenId(
        uint256 citizenId
    ) public view returns (uint256) {
        CitizenData storage citizen = citizenData[citizenId];
        if (citizen.flags != 0) {
            return NTS2Citizen(v1Contract).getIdentityIdOfTokenId(citizenId);
        }
        return citizen.identityId;
    }

    function getItemCacheIdOfTokenId(
        uint256 citizenId
    ) public view returns (uint256) {
        CitizenData storage citizen = citizenData[citizenId];
        if (citizen.flags != 0) {
            return NTS2Citizen(v1Contract).getItemCacheIdOfTokenId(citizenId);
        }
        return citizen.itemCacheId;
    }

    function getLandDeedIdOfTokenId(
        uint256 citizenId
    ) public view returns (uint256) {
        CitizenData storage citizen = citizenData[citizenId];
        if (citizen.flags != 0) {
            return NTS2Citizen(v1Contract).getLandDeedIdOfTokenId(citizenId);
        }
        return citizen.landDeedId;
    }

    function getSpecialMessageOfTokenId(
        uint256 citizenId
    ) public view returns (string memory) {
        CitizenData storage citizen = citizenData[citizenId];
        if (hasFlag(citizen.flags, SPECIAL_MESSAGE_UPDATED)) {
            return _specialMessageByCitizenId[citizenId];
        } else if (hasFlag(citizen.flags, MIGRATED_FLAG)) {
            return
                NTS2Citizen(config.findComponent(NTComponent.S2_CITIZEN,false)).getSpecialMessageOfTokenId(citizenId);
        } else {
            return _specialMessageByCitizenId[citizenId];
        }
    }

    function getGenderOfTokenId(uint256 citizenId) public view returns (bool) {
        CitizenData storage citizen = citizenData[citizenId];
        return citizen.flags & FEMALE_FLAG != 0;
    }

    function getCitizenMigrated(uint256 citizenId) public view returns (bool) {
        CitizenData storage citizen = citizenData[citizenId];
        return citizen.flags & MIGRATED_FLAG != 0;
    }

    function hasFlag(uint8 flags, uint8 flag) internal pure returns (bool) {
        return flags & flag != 0;
    }

    function getHumanRaceOverride(
        uint256 citizenId
    ) public view returns (uint256) {
        CitizenData storage citizen = citizenData[citizenId];
        return citizen.humanRace;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        if (_msgSender() != address(config)) {
            return config.tokenURI(tokenId);
        }

        return config.generateURI(tokenId);
    }

    /*
     * A function to migrate a citizen from the old contract to the new one
     * To save on user gas fees only the citizen will be minted
     * The components will only get minted if the citizen is disassembled after migration
     */
    function migrateAsset(
        address sender,
        uint256 citizenId
    ) public nonReentrant {
        require(
            _msgSender() == NTConfig(config).migrator(),
            "msg.sender must be migrator"
        );

        NTS2Citizen oldContract = NTS2Citizen(
            config.findComponent(NTComponent.S2_CITIZEN, false)
        );
        require(
            oldContract.ownerOf(citizenId) == sender,
            "You do not own that citizen"
        );

        //Only the citizen NFT is required to be transferred as it will be locked away in this contract forever
        //This guarantees the V1 components can never leave the old citizen contract and be used again
        oldContract.transferFrom(sender, address(this), citizenId);

        // _identityDataByCitizenId[citizenId] = oldContract.getIdentityIdOfTokenId(citizenId);
        // _itemCacheDataByCitizenId[citizenId] = oldContract.getItemCacheIdOfTokenId(citizenId);
        // _landDeedDataByCitizenId[citizenId] = oldContract.getIdentityIdOfTokenId(citizenId);
        bool isFemale = oldContract.getGenderOfTokenId(citizenId);
        // _specialMessageByCitizenId[citizenId] = oldContract.getSpecialMessageOfTokenId(citizenId);
        // _citizenCreationTime[citizenId] = oldContract._citizenCreationTime(citizenId);

        _safeMint(sender, citizenId);

        citizenData[citizenId].flags = isFemale ? MIGRATED_FLAG | FEMALE_FLAG : MIGRATED_FLAG;
    }

    function createCitizen(
        uint256 identityId,
        uint256 itemCacheId,
        uint256 landDeedId,
        bool genderFemale,
        string memory specialMessage
    ) public nonReentrant {
        require(citizenMintActive, "Uploading is not currently active");
        require(
            identityValidated(identityId),
            "You are not the owner of that identity"
        );
        require(
            itemCacheValidated(itemCacheId),
            "You are not the owner of that item cache"
        );
        require(
            landDeedValidated(landDeedId),
            "You are not the owner of that land deed"
        );

        if (genderFemale) {
            require(femaleActive, "Females cannot be uploaded yet");
        }

        _safeMint(_msgSender(), ++currentId);

        //V2 no longer uses a separate bought identity contract
        IERC721Upgradeable _identityContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_IDENTITY, true)
        );
        _identityContract.transferFrom(_msgSender(), address(this), identityId);

        IERC721Upgradeable _itemContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_ITEM, true)
        );
        _itemContract.transferFrom(_msgSender(), address(this), itemCacheId);

        IERC721Upgradeable _landContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_LAND, true)
        );
        _landContract.transferFrom(_msgSender(), address(this), landDeedId);

        uint8 flags = 0;

        if (genderFemale) {
            flags |= FEMALE_FLAG;
        }

        if (bytes(specialMessage).length > 0) {
            _specialMessageByCitizenId[currentId] = specialMessage;
        }

        citizenData[currentId] = _packCitizenDataStruct(
            uint64(block.timestamp),
            uint32(identityId),
            uint32(itemCacheId),
            uint32(landDeedId),
            0,
            flags
        );
    }

    function disassembleCitizen(uint256 citizenId) public nonReentrant {
        require(_exists(citizenId), "Citizen does not exist");
        require(
            ownerOf(citizenId) == _msgSender(),
            "You do not own that citizen"
        );
        CitizenData storage citizen = citizenData[citizenId];

        if (hasFlag(citizen.flags, MIGRATED_FLAG)) {
            _unmintedDisassemble(citizenId);
        } else {
            _regularDisassemble(citizenId);
        }

        _burn(citizenId);

        delete _specialMessageByCitizenId[citizenId];
    }

    function _regularDisassemble(uint256 citizenId) private {
        CitizenData memory citizen = citizenData[citizenId];

        IERC721Upgradeable _identityContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_IDENTITY, true)
        );
        _identityContract.transferFrom(
            address(this),
            _msgSender(),
            citizen.identityId
        );

        IERC721Upgradeable _itemContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_ITEM, true)
        );
        _itemContract.transferFrom(
            address(this),
            _msgSender(),
            citizen.itemCacheId
        );

        IERC721Upgradeable _landContract = IERC721Upgradeable(
            config.findComponent(NTComponent.S2_LAND, true)
        );
        _landContract.transferFrom(
            address(this),
            _msgSender(),
            citizen.landDeedId
        );
    }

    function _unmintedDisassemble(uint256 citizenId) private {
        NTS2Citizen v2Citizen = NTS2Citizen(
            config.findComponent(NTComponent.S2_CITIZEN, false)
        );

        IComponent v2IdentityContract = IComponent(
            config.findComponent(NTComponent.S2_IDENTITY, true)
        );
        v2IdentityContract.adminClaim(
            v2Citizen.getIdentityIdOfTokenId(citizenId),
            _msgSender()
        );

        IComponent itemContract = IComponent(
            config.findComponent(NTComponent.S2_ITEM, true)
        );
        itemContract.adminClaim(
            v2Citizen.getItemCacheIdOfTokenId(citizenId),
            _msgSender()
        );

        IComponent landContract = IComponent(
            config.findComponent(NTComponent.S2_LAND, true)
        );
        landContract.adminClaim(
            v2Citizen.getLandDeedIdOfTokenId(citizenId),
            _msgSender()
        );
    }

    function changeGender(uint256 tokenId) public nonReentrant {
        require(femaleActive, "Females cannot be uploaded yet");
        require(
            ownerOf(tokenId) == _msgSender(),
            "You do not own that citizen"
        );

        IByteContract iBytes = IByteContract(NTConfig(config).bytesContract());
        iBytes.burn(_msgSender(), changeGenderCost);

        CitizenData storage citizen = citizenData[tokenId];
        citizen.flags ^= FEMALE_FLAG;
    }

    function changeSpecialMessage(
        uint256 tokenId,
        string memory _message
    ) public nonReentrant {
        require(
            ownerOf(tokenId) == _msgSender(),
            "You do not own that citizen"
        );

        IByteContract iBytes = IByteContract(NTConfig(config).bytesContract());
        iBytes.burn(_msgSender(), changeSpecialMessageCost);
        _specialMessageByCitizenId[tokenId] = _message;

        if (hasFlag(citizenData[tokenId].flags, MIGRATED_FLAG)) {
            citizenData[tokenId].flags |= SPECIAL_MESSAGE_UPDATED;
        }
    }

    /// This function only works for citizens with the human race
    /// Set the `raceOverride` to `0` to reset to randomized human race.
    /// A `raceOverride` index will correspond to the races in the mint contract.
    /// Any `raceOverride` index larger than the last race index available will default to the last race index
    function changeHumanRace(
        uint256 tokenId,
        uint256 raceOverride
    ) public nonReentrant {
        require(
            ownerOf(tokenId) == _msgSender(),
            "You do not own that citizen"
        );
        require(raceOverrideActive, "Human race override is not active yet");
        IByteContract iBytes = IByteContract(NTConfig(config).bytesContract());
        iBytes.burn(_msgSender(), humanRaceChangeCost);

        citizenData[tokenId].humanRace = uint8(raceOverride);
    }

    function setChangeGenderCost(uint72 _cost) external onlyOwner {
        changeGenderCost = _cost;
    }

    function setChangeHumanRaceCost(uint72 _cost) external onlyOwner {
        humanRaceChangeCost = _cost;
    }

    function setChangeMessageCost(uint72 _cost) external onlyOwner {
        changeSpecialMessageCost = _cost;
    }

    function setMintedIdentityCost(uint72 _cost) public onlyOwner {
        mintedIdentityCost = _cost;
    }

    function setV1Contract(address _contract) external onlyOwner {
        v1Contract = _contract;
    }

    function identityValidated(
        uint256 identityId
    ) internal view returns (bool) {
        IERC721Enumerable identityEnumerable = IERC721Enumerable(
            config.findComponent(NTComponent.S2_IDENTITY, true)
        );
        return (identityEnumerable.ownerOf(identityId) == _msgSender());
    }

    function itemCacheValidated(
        uint256 itemCacheId
    ) internal view returns (bool) {
        IERC721Enumerable itemCacheEnumerable = IERC721Enumerable(
            config.findComponent(NTComponent.S2_ITEM, true)
        );
        return (itemCacheEnumerable.ownerOf(itemCacheId) == _msgSender());
    }

    function landDeedValidated(
        uint256 landDeedId
    ) internal view returns (bool) {
        IERC721Enumerable landDeedEnumerable = IERC721Enumerable(
            config.findComponent(NTComponent.S2_LAND, true)
        );
        return (landDeedEnumerable.ownerOf(landDeedId) == _msgSender());
    }

    function setFemaleActive() public onlyOwner {
        femaleActive = !femaleActive;
    }

    function setCitizenMintActive() public onlyOwner {
        citizenMintActive = !citizenMintActive;
    }

    function setBoughtIdentitiesActive() public onlyOwner {
        boughtIdentitiesActive = !boughtIdentitiesActive;
    }

    function setRaceOverrideActive() public onlyOwner {
        raceOverrideActive = !raceOverrideActive;
    }

    //_newRoyalty is in basis points out of 10,000
    function adjustDefaultRoyalty(
        address _receiver,
        uint96 _newRoyalty
    ) public onlyOwner {
        _setDefaultRoyalty(_receiver, _newRoyalty);
    }

    //_newRoyalty is in basis points out of 10,000
    function adjustSingleTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _newRoyalty
    ) public onlyOwner {
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

    function setConfig(address config_) external onlyOwner {
        config = NTConfig(config_);
    }

    function owner()
        public
        view
        override(OwnableUpgradeable, UpdatableOperatorFiltererUpgradeable)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}

