// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Erc721LockRegistry.sol";
import "./DefaultOperatorFiltererUpgradeable.sol";
import "./IPotatoz.sol";
import "./ICaptainz.sol";

// WIP

contract CaptainzV2 is ERC721x, DefaultOperatorFiltererUpgradeable, ICaptainz {

    string public baseTokenURI;
    string public tokenURISuffix;
    string public tokenURIOverride;

    uint256 public MAX_SUPPLY;

    event QuestStarted(uint256 indexed tokenId, uint256 questStartedAt, uint256[] crews);
    event QuestEdited(uint256 indexed tokenId, uint256 questStartedAt, uint256[] crews, uint256 questEditedAt);
    event QuestStopped(
        uint256 indexed tokenId,
        uint256 questStartedAt,
        uint256 questStoppedAt
    );

    event ChestRevealed(uint256 indexed tokenId);

    IPotatoz public potatozContract;

    uint256 public MAX_CREWS;
    bool public canQuest;
    mapping(uint256 => uint256) public tokensLastQuestedAt; // captainz tokenId => timestamp
    mapping(uint256 => uint256[]) public questCrews; // captainz tokenId => potatoz tokenIds
    mapping(uint256 => uint256[]) public potatozCrew; // potatoz tokenId => captainz tokenId [array of 1 uint256]
    mapping(uint256 => bool) public revealed; // captains tokenId => revealed



    function initialize(string memory baseURI) public initializer {
        DefaultOperatorFiltererUpgradeable.__DefaultOperatorFilterer_init();
        ERC721x.__ERC721x_init("Captainz", "Captainz");
        baseTokenURI = baseURI;
        MAX_SUPPLY = 9999;
        MAX_CREWS = 3;
    }

    function safeMint(address receiver, uint256 quantity) internal {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "exceed MAX_SUPPLY");
        _mint(receiver, quantity);
    }

    // =============== Airdrop ===============

    function airdrop(address[] memory receivers) external onlyOwner {
        require(receivers.length >= 1, "at least 1 receiver");
        for (uint256 i; i < receivers.length; i++) {
            address receiver = receivers[i];
            safeMint(receiver, 1);
        }
    }

    function airdropWithAmounts(
        address[] memory receivers,
        uint256[] memory amounts
    ) external onlyOwner {
        require(receivers.length >= 1, "at least 1 receiver");
        for (uint256 i; i < receivers.length; i++) {
            address receiver = receivers[i];
            safeMint(receiver, amounts[i]);
        }
    }

    // =============== URI ===============

    function compareStrings(string memory a, string memory b)
        public
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (bytes(tokenURIOverride).length > 0) {
            return tokenURIOverride;
        }
        return string.concat(super.tokenURI(_tokenId), tokenURISuffix);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        baseTokenURI = baseURI;
    }

    function setTokenURISuffix(string calldata _tokenURISuffix)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURISuffix, "!empty!")) {
            tokenURISuffix = "";
        } else {
            tokenURISuffix = _tokenURISuffix;
        }
    }

    function setTokenURIOverride(string calldata _tokenURIOverride)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURIOverride, "!empty!")) {
            tokenURIOverride = "";
        } else {
            tokenURIOverride = _tokenURIOverride;
        }
    }

    // =============== Stake + MARKETPLACE CONTROL ===============

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721x) onlyAllowedOperator(from) {
        require(
            tokensLastQuestedAt[tokenId] == 0,
            "Cannot transfer questing token"
        );
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override(ERC721x) onlyAllowedOperator(from) {
        require(
            tokensLastQuestedAt[tokenId] == 0,
            "Cannot transfer questing token"
        );
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    // =============== Questing ===============

    struct QuestInfo {
        uint256 tokenId;
        uint256[] potatozTokenIds;
    }

    function batchStartQuest(QuestInfo[] calldata questInfos) external {
        for (uint256 i = 0; i < questInfos.length; i++) {
            startQuest(questInfos[i].tokenId, questInfos[i].potatozTokenIds);
        }
    }

    function batchEditQuest(QuestInfo[] calldata questInfos) external {
        require(canQuest, "questing not open");
        require(address(potatozContract) != address(0), "potatozContract not set");

        for (uint256 i = 0; i < questInfos.length; i++) {
            uint256 tokenId = questInfos[i].tokenId;

            require(msg.sender == ownerOf(tokenId), "not owner of [captainz tokenId]");
            require(tokensLastQuestedAt[tokenId] > 0, "quested not started for [captainz tokenId]");

            _resetCrew(tokenId);
        }

        for (uint256 i = 0; i < questInfos.length; i++) {
            uint256 tokenId = questInfos[i].tokenId;
            uint256[] calldata potatozTokenIds = questInfos[i].potatozTokenIds;

            require(potatozTokenIds.length <= MAX_CREWS, "too many crews [potatozTokenIds]");

            _addCrew(tokenId, potatozTokenIds);
            emit QuestEdited(tokenId, tokensLastQuestedAt[tokenId], potatozTokenIds, block.timestamp);
        }
    }

    function batchStopQuest(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            stopQuest(tokenIds[i]);
        }
    }

    function startQuest(uint256 tokenId, uint256[] calldata potatozTokenIds) public {
        require(canQuest, "questing not open");
        require(address(potatozContract) != address(0), "potatozContract not set");

        require(msg.sender == ownerOf(tokenId), "not owner of [captainz tokenId]");
        require(tokensLastQuestedAt[tokenId] == 0, "quested already started for [captainz tokenId]");
        require(potatozTokenIds.length <= MAX_CREWS, "too many crews [potatozTokenIds]");

        _addCrew(tokenId, potatozTokenIds);

        tokensLastQuestedAt[tokenId] = block.timestamp;
        emit QuestStarted(tokenId, block.timestamp, potatozTokenIds);

        if (!revealed[tokenId]) {
            revealed[tokenId] = true;
            emit ChestRevealed(tokenId);
        }
    }

    function editQuest(uint256 tokenId, uint256[] calldata potatozTokenIds) public {
        require(canQuest, "questing not open");
        require(address(potatozContract) != address(0), "potatozContract not set");

        require(msg.sender == ownerOf(tokenId), "not owner of [captainz tokenId]");
        require(tokensLastQuestedAt[tokenId] > 0, "quested not started for [captainz tokenId]");
        require(potatozTokenIds.length <= MAX_CREWS, "too many crews [potatozTokenIds]");

        _resetCrew(tokenId);
        _addCrew(tokenId, potatozTokenIds);

        emit QuestEdited(tokenId, tokensLastQuestedAt[tokenId], potatozTokenIds, block.timestamp);
    }

    function _addCrew(uint256 tokenId, uint256[] calldata potatozTokenIds) private {
        if (potatozTokenIds.length >= 1) {
            uint256[] memory wrapper = new uint256[](1);
            wrapper[0] = tokenId;
            for (uint256 i = 0; i < potatozTokenIds.length; i++) {
                uint256 pTokenId = potatozTokenIds[i];
                require(potatozContract.nftOwnerOf(pTokenId) == msg.sender, "not owner of [potatoz tokenId]");
                if (!potatozContract.isPotatozStaking(pTokenId)) {
                    potatozContract.stakeExternal(pTokenId);
                }
                uint256[] storage existCheck = potatozCrew[pTokenId];
                require(existCheck.length == 0, "Duplicate [potatozTokenIds]");
                potatozCrew[pTokenId] = wrapper;
            }
            questCrews[tokenId] = potatozTokenIds;
        }
    }

    function _resetCrew(uint256 tokenId) private {
        uint256[] storage potatozTokenIds = questCrews[tokenId];
        if (potatozTokenIds.length >= 1) {
            uint256[] memory empty = new uint256[](0);
            for (uint256 i = 0; i < potatozTokenIds.length; i++) {
                uint256 pTokenId = potatozTokenIds[i];
                potatozCrew[pTokenId] = empty;
            }
            questCrews[tokenId] = empty;
        }
    }

    function stopQuest(uint256 tokenId) public {
        require(msg.sender == ownerOf(tokenId), "not owner of [captainz tokenId]");
        require(tokensLastQuestedAt[tokenId] > 0, "quested not started for [captainz tokenId]");

        _resetCrew(tokenId);

        uint256 tlqa = tokensLastQuestedAt[tokenId];
        tokensLastQuestedAt[tokenId] = 0;
        emit QuestStopped(tokenId, tlqa, block.timestamp);
    }

    function isPotatozQuesting(uint256 tokenId) external view returns (bool) {
        uint256[] storage existCheck = potatozCrew[tokenId];
        return existCheck.length > 0;
    }

    function getTokenInfo(uint256 tokenId) external view returns (uint256 lastQuestedAt, uint256[] memory crewTokenIds, bool hasRevealed) {
        return (tokensLastQuestedAt[tokenId], questCrews[tokenId], revealed[tokenId]);
    }

    function getActiveCrews(uint256 tokenId) external view returns (uint256[] memory) {
        require(address(potatozContract) != address(0), "potatozContract not set");
        address owner = ownerOf(tokenId);

        uint256[] memory pTokenIds = questCrews[tokenId];
        uint256 activeLength = pTokenIds.length;
        for (uint256 i = 0; i < pTokenIds.length; i++) {
            uint256 pTokenId = pTokenIds[i];
            if (potatozContract.nftOwnerOf(pTokenId) != owner || !potatozContract.isPotatozStaking(pTokenId)) {
                pTokenIds[i] = 0;
                activeLength--;
            }
        }

        uint256[] memory activeCrews = new uint256[](activeLength);
        uint256 activeIdx;
        for (uint256 i = 0; i < pTokenIds.length; i++) {
            if (pTokenIds[i] != 0) {
                activeCrews[activeIdx++] = pTokenIds[i];
            }
        }

        return activeCrews;
    }

    // =============== Admin ===============

    function setCanQuest(bool b) external onlyOwner {
        canQuest = b;
    }

    function setPotatozContract(address addr) external onlyOwner {
        potatozContract = IPotatoz(addr);
    }

}
