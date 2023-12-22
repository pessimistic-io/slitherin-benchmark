// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Math.sol";
import "./Strings.sol";
import "./Base64.sol";

import "./AccessControl.sol";

import "./Sharks.sol";

contract Gangs is ERC721, ERC721Enumerable, AccessControl {
    bytes32 public constant GANG_MANAGER_ROLE = keccak256("GANG_MANAGER_ROLE");

    using Counters for Counters.Counter;
    Counters.Counter private tokenIdTracker;
    string public imageBaseURI;

    mapping (uint256 => Membership) public memberships; // sharkId => Membership
    mapping (uint256 => Dossier) public dossiers; // sharkId => Dossier

    Sharks public immutable sharks;
    uint256 public immutable MAX_SUPPLY;

    struct Dossier {
        string name;
        uint256 leaderId;
        uint256[] membersIds;
        uint256 leaderRarity;
        uint256 membersRarity;
        uint256 minSize;
        uint256 maxSize;
        uint256 joiningFee;
    }

    struct Membership {
        uint256 gangId;
        uint256 expiresAt;
    }

    event ImageBaseURIChanged(string imageBaseURI);
    event Minted(address indexed to, uint256 indexed tokenId);
    event MemberAdded(uint256 indexed gangId, uint256 indexed sharkId, uint256 expiresAt);
    event MemberRemoved(uint256 indexed gangId, uint256 indexed sharkId);
    event LeaderAdded(uint256 indexed gangId, uint256 indexed sharkId, uint256 expiresAt);
    event LeaderRemoved(uint256 indexed gangId, uint256 indexed sharkId);
    event MembershipChanged(uint256 indexed gangId, uint256 indexed sharkId, uint256 expiresAt);
    event NameChanged(uint256 indexed gangId, string name);
    event MinSizeChanged(uint256 indexed gangId, uint256 minSize);
    event MaxSizeChanged(uint256 indexed gangId, uint256 maxSize);
    event JoiningFeeChanged(uint256 indexed gangId, uint256 joiningFee);

    modifier onlyMinted(uint256 tokenId) {
        _requireMinted(tokenId);
        _;
    }

    constructor(
        address sharksAddress_,
        uint256 maxSupply_
    ) ERC721("Smol Sharks Gangs", "GANGS")
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(GANG_MANAGER_ROLE, _msgSender());

        MAX_SUPPLY = maxSupply_;

        sharks = Sharks(sharksAddress_);
    }

    // internal
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    function setImageBaseURI(string memory imageBaseURI_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        imageBaseURI = imageBaseURI_;
        emit ImageBaseURIChanged(imageBaseURI);
    }

    function mint(
        address to_,
        uint256 mintsCount_,
        uint256 leaderRarity_,
        uint256 membersRarity_,
        uint256 minSize_,
        uint256 maxSize_
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 _actualMintsCount = Math.min(mintsCount_, MAX_SUPPLY - tokenIdTracker.current());

        require(_actualMintsCount > 0, "MAX_SUPPLY reached");

        for (uint256 i = 0; i < _actualMintsCount; i++) {
            tokenIdTracker.increment();

            uint256 _tokenId = tokenIdTracker.current();

            require(_tokenId <= MAX_SUPPLY, "MAX_SUPPLY reached"); // sanity check, should not ever trigger

            _safeMint(to_, _tokenId);

            Dossier storage dossier = dossiers[_tokenId];
            dossier.leaderRarity = leaderRarity_;
            dossier.membersRarity = membersRarity_;
            dossier.minSize = minSize_;
            dossier.maxSize = maxSize_;

            emit Minted(to_, _tokenId);
        }
    }

    // only GANG_MANAGER_ROLE
    function addMembers(
        uint256 gangId_,
        uint256[] calldata addedSharksIds_,
        uint256 expiresAt_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        Dossier storage dossier = dossiers[gangId_];

        require(
            addedSharksIds_.length + dossier.membersIds.length <= dossier.maxSize,
            "Gangs: more members than maxSize allows"
        );

        for (uint256 i = 0; i < addedSharksIds_.length; i++) {
            uint256 _sharkId = addedSharksIds_[i];
            require(memberships[_sharkId].gangId == 0, "Gangs: shark already in a gang");
            require(dossier.membersRarity == sharks.rarity(_sharkId), "Gangs: members rarity does not match");

            changeMembership(_sharkId, gangId_, expiresAt_);
            dossier.membersIds.push(_sharkId);
            emit MemberAdded(gangId_, _sharkId, expiresAt_);
        }

    }

    function removeMembers(
        uint256 gangId_,
        uint256[] calldata removedSharksIds_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        Dossier storage dossier = dossiers[gangId_];

        for (uint256 i = 0; i < removedSharksIds_.length; i++) {
            uint256 _removedSharkId = removedSharksIds_[i];
            require(memberships[_removedSharkId].gangId > 0, "Gangs: shark not in a gang");
            require(memberships[_removedSharkId].expiresAt <= block.timestamp, "Gangs: membership has not expired yet");

            changeMembership(_removedSharkId, 0, 0);
            emit MemberRemoved(gangId_, _removedSharkId);

            for (uint256 k = 0; k < dossier.membersIds.length; k++) {
                if (_removedSharkId == dossier.membersIds[k]) {
                    dossier.membersIds[k] = dossier.membersIds[dossier.membersIds.length-1];
                    dossier.membersIds.pop();
                    break;
                }
            }
        }

        require(dossier.membersIds.length <= dossier.maxSize, "Gangs: maxSize not met");
    }

    function addLeader(
        uint256 gangId_,
        uint256 newLeaderId_,
        uint256 expiresAt_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        require(memberships[newLeaderId_].gangId == 0, "Gangs: leader already in a gang");

        Dossier storage dossier = dossiers[gangId_];

        require(dossier.leaderId == 0, "Gangs: Gang already has a leader");
        require(dossier.leaderRarity == sharks.rarity(newLeaderId_), "Gangs: invalid leader rarity");

        dossier.leaderId = newLeaderId_;

        changeMembership(newLeaderId_, gangId_, expiresAt_);

        emit LeaderAdded(gangId_, newLeaderId_, expiresAt_);
    }

    function removeLeader(
        uint256 gangId_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        Dossier storage dossier = dossiers[gangId_];

        uint256 _removedLeaderId = dossier.leaderId;

        require(_removedLeaderId > 0, "Gangs: gang has no leader");
        require(memberships[_removedLeaderId].expiresAt <= block.timestamp, "Gangs: leader membership has not expired yet");

        dossier.leaderId = 0;

        changeMembership(_removedLeaderId, 0, 0);

        emit LeaderRemoved(gangId_, _removedLeaderId);
    }

    function changeMembership(
        uint256 sharkId_,
        uint256 gangId_,
        uint256 expiresAt_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
    {
        memberships[sharkId_].gangId = gangId_;
        memberships[sharkId_].expiresAt = expiresAt_;

        emit MembershipChanged(gangId_, sharkId_, expiresAt_);
    }

    function changeName(
        uint256 gangId_,
        string memory name_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        dossiers[gangId_].name = name_;

        emit NameChanged(gangId_, name_);
    }

    function changeMinSize(
        uint256 gangId_,
        uint256 minSize_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        dossiers[gangId_].minSize = minSize_;

        emit MinSizeChanged(gangId_, minSize_);
    }

    function changeMaxSize(
        uint256 gangId_,
        uint256 maxSize_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        dossiers[gangId_].maxSize = maxSize_;

        emit MaxSizeChanged(gangId_, maxSize_);
    }

    function changeJoiningFee(
        uint256 gangId_,
        uint256 joiningFee_
    )
        public
        onlyRole(GANG_MANAGER_ROLE)
        onlyMinted(gangId_)
    {
        dossiers[gangId_].joiningFee = joiningFee_;

        emit JoiningFeeChanged(gangId_, joiningFee_);
    }

    // Views

    function getLeaderId(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].leaderId;
    }

    function getMembersIds(uint256 gangId_) public view returns (uint256[] memory) {
        return dossiers[gangId_].membersIds;
    }

    function getMembersCount(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].membersIds.length;
    }

    function getLeaderRarity(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].leaderRarity;
    }

    function getMembersRarity(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].membersRarity;
    }

    function getName(uint256 gangId_) public view returns (string memory) {
        return dossiers[gangId_].name;
    }

    function getMinSize(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].minSize;
    }

    function getMaxSize(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].maxSize;
    }

    function getJoiningFee(uint256 gangId_) public view returns (uint256) {
        return dossiers[gangId_].joiningFee;
    }

    function getGangIdBySharkId(uint256 shark_) public view returns (uint256) {
        return memberships[shark_].gangId;
    }

    function getExpiresAtBySharkId(uint256 shark_) public view returns (uint256) {
        return memberships[shark_].expiresAt;
    }

    function isActive(uint256 gangId_) public view returns (bool) {
        return getLeaderId(gangId_) != 0 && getMembersCount(gangId_) >= getMinSize(gangId_);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function generateDataURI(uint256 tokenId)
        public
        view
        returns (string memory)
    {
        bytes memory attributes_1 = abi.encodePacked(
            '{"trait_type":"Leader","value":"', rarityToClass(getLeaderRarity(tokenId)) ,'"},',
            '{"trait_type":"Members","value":"', rarityToClass(getMembersRarity(tokenId)) ,'"},',
            '{"trait_type":"Min Size","value":', Strings.toString(getMinSize(tokenId)) ,'},'
        );
        bytes memory attributes_2 = abi.encodePacked(
            '{"trait_type":"Max Size","value":', Strings.toString(getMaxSize(tokenId)) ,'},',
            '{"trait_type":"Joining Fee","value":"', Strings.toString(getJoiningFee(tokenId)) ,'"},',
            '{"trait_type":"Active","value":', isActive(tokenId) ? 'true' : 'false' ,'}'
        );

        string memory customName = getName(tokenId);

        string memory name = bytes(customName).length != 0 ? customName : string(abi.encodePacked("Gang #", Strings.toString(tokenId)));

        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name":"', name, '",',
                '"image":"', abi.encodePacked(imageBaseURI), rarityToClass(getLeaderRarity(tokenId)), '.png",',
                '"attributes":[',
                    attributes_1,
                    attributes_2,
                ']',
            '}'
        );

        return Base64.encode(dataURI);

    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                generateDataURI(tokenId)
            )
        );

    }

    function rarityToClass(uint256 rarity) public pure returns (string memory) {
        if (rarity == 1)
            return 'Common';
        if (rarity == 10)
            return 'Robber';
        if (rarity == 25)
            return 'Astronaut';
        if (rarity == 100)
            return 'Pirate';
        if (rarity == 250)
            return 'Lady';
        if (rarity == 1500)
            return 'Mummy';
        if (rarity == 10000)
            return 'Alien';
        if (rarity == 25000)
            return 'Ghost';

        return '';
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 tokenId_)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from_, to_, tokenId_);
    }


}
