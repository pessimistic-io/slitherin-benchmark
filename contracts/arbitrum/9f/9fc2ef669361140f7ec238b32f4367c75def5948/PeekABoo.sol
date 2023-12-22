// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./IPeekABoo.sol";
import "./PeekABooBase.sol";
import "./IBOO.sol";
import "./IStakeManager.sol";
import "./ITraits.sol";
import "./ILevel.sol";

contract PeekABoo is
    IPeekABoo,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    PeekABooBase
{
    using MerkleProofUpgradeable for bytes32[];

    bytes32 root;
    mapping(address => bool) claimedPhase1Mint;

    modifier onlyLevel() {
        require(_msgSender() == address(level));
        _;
    }

    modifier onlyInGame() {
        require(_msgSender() == address(ingame));
        _;
    }

    event PABMinted(
        bytes32 indexed requestId,
        uint256 amount,
        uint256 indexed result
    );

    function initialize(IBOO _boo) public initializer {
        __ERC721_init("PeekABoo", "PAB");
        __Ownable_init();
        __Pausable_init();

        boo = _boo;
        MAX_PHASE1_TOKENS = 10000;
        MAX_PHASE2_TOKENS = 10000;
        MAX_NUM_PHASE1_GHOSTS = 2500;
        DEV_AND_COMM_PHASE1_GHOSTS = 525;
        PHASE1_ENDED = false;
        MAX_NUM_PHASE1_BUSTERS = 7500;
        MAX_NUM_PHASE2_GHOSTS = 2500;
        MAX_NUM_PHASE2_BUSTERS = 7500;
        root = 0xdb75746519e2448a1597dc7a4a6ce0586a3a5f171378abdc3367f4a28b8a06f8;
    }

    function pseudoRandomizeCommonTraits(uint256 tokenId, uint256 tokenType)
        internal
    {
        uint256 randomizedCommon = uint256(
            keccak256(
                abi.encodePacked(
                    _msgSender(),
                    tokenId,
                    block.timestamp,
                    tokenType * 666,
                    block.difficulty
                )
            )
        );

        if (tokenType == 0) {
            tokenTraits[tokenId].isGhost = true;
            setTokenTraits(tokenId, 0, randomizedCommon % 7);
            setTokenTraits(tokenId, 1, randomizedCommon % 9);
            setTokenTraits(tokenId, 2, randomizedCommon % 8);
            setTokenTraits(tokenId, 3, randomizedCommon % 14);
            setTokenTraits(tokenId, 4, randomizedCommon % 13);
            setTokenTraits(tokenId, 5, randomizedCommon % 7);
            setTokenTraits(tokenId, 6, randomizedCommon % 7);
        } else {
            tokenTraits[tokenId].isGhost = false;
            setTokenTraits(tokenId, 0, randomizedCommon % 7);
            setTokenTraits(tokenId, 1, randomizedCommon % 5);
            setTokenTraits(tokenId, 2, randomizedCommon % 12);
            setTokenTraits(tokenId, 3, randomizedCommon % 10);
            setTokenTraits(tokenId, 4, randomizedCommon % 4);
            setTokenTraits(tokenId, 5, randomizedCommon % 2);
            tokenTraits[tokenId].revealShape = uint64(randomizedCommon) % 3;
        }

        tokenTraits[tokenId].level = 1;
        tokenTraits[tokenId].tier = 0;
    }

    function devMint(address _to, uint256[] memory types) external onlyOwner {
        require(
            phase1Minted + types.length <= MAX_PHASE1_TOKENS,
            "All Phase 1 tokens minted"
        );

        for (uint256 i = 0; i < types.length; i++) {
            _safeMint(_to, phase1Minted);
            stakeManager.initializeEnergy(phase1Minted);
            pseudoRandomizeCommonTraits(phase1Minted, types[i]);
            phase1Minted++;
        }
    }

    function mint(uint256[] calldata types, bytes32[] memory proof) external {
        require(tx.origin == _msgSender(), "Only EOA");
        require(!PHASE1_ENDED, "Phase1 whitelist mint is over");
        require(!paused(), "Paused");
        require(!claimedPhase1Mint[_msgSender()], "Already claimed");
        require(
            proof.verify(root, keccak256(abi.encodePacked(_msgSender()))),
            "Caller is not a claimer"
        );

        uint256 amount = 1;
        claimedPhase1Mint[_msgSender()] = true;
        require(
            phase1Minted + amount <= MAX_PHASE1_TOKENS,
            "All Phase 1 tokens minted"
        );
        require(
            amount == types.length,
            "length of types does not match amount"
        );

        _phase1Mint(_msgSender(), amount, types);
    }

    function publicMint(uint256[] calldata types) external payable {
        require(tx.origin == _msgSender(), "Only EOA");
        require(PHASE1_ENDED, "whitelist mint still going");
        require(!paused(), "Paused");
        require(types.length > 0, "Invalid types");
        require(
            msg.value >= PUBLIC_PRICE * types.length,
            "whitelist mint still going"
        );
        funds += msg.value;
        uint256 minted = publicMinted[_msgSender()];
        require(
            phase1Minted + minted <= MAX_PHASE1_TOKENS - 2500,
            "All Phase 1 tokens minted"
        );
        require(minted + types.length < 3, "exceeds max per address");

        publicMinted[_msgSender()] = publicMinted[_msgSender()] + types.length;
        _phase1Mint(_msgSender(), types.length, types);
    }

    function _phase1Mint(
        address _to,
        uint256 amount,
        uint256[] calldata types
    ) internal {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(_to, phase1Minted);
            stakeManager.initializeEnergy(phase1Minted);
            if (types[i] == 0) {
                require(
                    MINT_PHASE1_GHOSTS + DEV_AND_COMM_PHASE1_GHOSTS + 1 <
                        MAX_NUM_PHASE1_GHOSTS,
                    "All ghosts in phase1 already minted."
                );
                MINT_PHASE1_GHOSTS++;
            }
            pseudoRandomizeCommonTraits(phase1Minted, types[i]);
            phase1Minted++;
        }
    }

    function mintPhase2(
        uint256 tokenId,
        uint256[] memory types,
        uint256 amount,
        uint256 booAmount
    ) external {
        uint256 owed = 0;
        require(
            _msgSender() == ownerOf(tokenId),
            "Only owner can mint Phase 2"
        );
        require(phase1Minted == 10000, "phase1 not over");
        require(
            phase2Minted + amount <= MAX_PHASE2_TOKENS,
            "All Phase 2 tokens minted"
        );
        require(
            amount == types.length,
            "length of types does not match amount"
        );
        require(
            tokenTraits[tokenId].level % 10 == 0,
            "Phase 2 cannot be minted yet by this token"
        );
        require(
            amount <= tokenTraits[tokenId].level / 10,
            "Cannot mint this many at this level"
        );
        require(
            booAmount >= phase2Price * amount,
            "Not enough $IBOO to mint this many tokens"
        );
        require(
            tokenTraits[tokenId].level / 10 > tokenTraits[tokenId].tier,
            "Cannot mint after tier up"
        );

        tokenTraits[tokenId].level = tokenTraits[tokenId].level - 5;
        uint256 phase2Id;
        for (uint256 i = 0; i < amount; i++) {
            owed += (phase2Price + (phase2PriceRate * (phase2Minted / 1000)));
            phase2Id = 10000 + phase2Minted;
            _safeMint(_msgSender(), phase2Id);
            stakeManager.initializeEnergy(phase2Id);
            pseudoRandomizeCommonTraits(phase2Id, types[i]);
            phase2Minted++;
        }
        require(booAmount >= owed, "Not enough $IBOO to mint this many tokens");
        uint256 allowance = boo.allowance(msg.sender, address(this));
        require(allowance >= booAmount, "Check the token allowance");
        boo.transferFrom(msg.sender, address(this), booAmount);
    }

    function incrementTier(uint256 tokenId) external onlyInGame {
        tokenTraits[tokenId].tier++;
    }

    function incrementLevel(uint256 tokenId) external onlyLevel {
        tokenTraits[tokenId].level++;
    }

    function setTokenTraits(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) public {
        require(_msgSender() == ownerOf(tokenId), "Not owner");
        require(
            level.isUnlocked(tokenId, traitType, traitId),
            "This trait is not unlocked."
        );

        if (tokenTraits[tokenId].isGhost) {
            // Check if trait is common or is bought
            require(
                (traitId <= traits.getRarityIndex(0, traitType, 0)) ||
                    (ingame.isBoughtTrait(tokenId, traitType, traitId) == true),
                "cannot equip this trait"
            );
            if (traitType == 0) tokenTraits[tokenId].background = traitId;
            else if (traitType == 1) tokenTraits[tokenId].back = traitId;
            else if (traitType == 2) tokenTraits[tokenId].bodyColor = traitId;
            else if (traitType == 3)
                tokenTraits[tokenId].clothesOrHelmet = traitId;
            else if (traitType == 4) tokenTraits[tokenId].hat = traitId;
            else if (traitType == 5) tokenTraits[tokenId].face = traitId;
            else if (traitType == 6) tokenTraits[tokenId].hands = traitId;
        } else {
            // Check if trait is common or is bought
            require(
                (traitId <= traits.getRarityIndex(1, traitType, 0)) ||
                    (ingame.isBoughtTrait(tokenId, traitType, traitId) == true),
                "cannot equip this trait"
            );
            if (traitType == 0) tokenTraits[tokenId].background = traitId;
            else if (traitType == 1) tokenTraits[tokenId].back = traitId;
            else if (traitType == 2) tokenTraits[tokenId].bodyColor = traitId;
            else if (traitType == 3) tokenTraits[tokenId].hat = traitId;
            else if (traitType == 4) tokenTraits[tokenId].face = traitId;
            else if (traitType == 5)
                tokenTraits[tokenId].clothesOrHelmet = traitId;
        }
    }

    function setMultipleTokenTraits(
        uint256 tokenId,
        uint256[] calldata traitTypes,
        uint256[] calldata traitIds
    ) external {
        require(_msgSender() == ownerOf(tokenId), "Not owner");
        require(traitTypes.length == traitIds.length, "Incorrect lengths");
        for (uint256 i = 0; i < traitTypes.length; i++) {
            setTokenTraits(tokenId, traitTypes[i], traitIds[i]);
        }
    }

    function setAbility(uint256 tokenId, uint64 ability) external {
        require(_msgSender() == ownerOf(tokenId), "Not owner");
        require(
            ingame.isBoughtAbility(tokenId, ability),
            "You do have not unlocked this ability"
        );
        tokenTraits[tokenId].ability = ability;
    }

    function setRevealShape(uint256 tokenId, uint64 revealShape) external {
        require(_msgSender() == ownerOf(tokenId), "Not owner");
        require(revealShape < 3, "reveal shape does not exist");
        tokenTraits[tokenId].revealShape = revealShape;
    }

    function initializeGhostMap(uint256 tokenId, uint256 nonce) external {
        communityNonce += nonce;
        uint256 _cn = communityNonce;
        require(_msgSender() == ownerOf(tokenId), "Not owner");
        require(
            !ghostMaps[tokenId].initialized,
            "already initialized the map."
        );
        for (uint256 j = 0; j < 10; j++) {
            for (uint256 k = 0; k < 10; k++) {
                if (
                    uint256(keccak256(abi.encodePacked(tokenId, _cn, j, k))) %
                        10 ==
                    1
                ) {
                    ghostMaps[tokenId].grid[j][k] = 1;
                }
            }
        }
        ghostMaps[tokenId].gridSize = 8;
        ghostMaps[tokenId].difficulty = 0;
        ghostMaps[tokenId].initialized = true;
    }

    /** ADMIN */

    function getPhase1Minted() external view returns (uint256 result) {
        result = phase1Minted;
    }

    function getPhase2Minted() external view returns (uint256 result) {
        result = phase2Minted;
    }

    function setBOO(address _boo) external onlyOwner {
        boo = IBOO(_boo);
    }

    function setStakeManager(address _stakeManager) external onlyOwner {
        stakeManager = IStakeManager(_stakeManager);
    }

    function setTraits(address _traits) external onlyOwner {
        traits = ITraits(_traits);
    }

    function setLevel(address _level) external onlyOwner {
        level = ILevel(_level);
    }

    function setInGame(address _ingame) external onlyOwner {
        ingame = InGame(_ingame);
    }

    function setPhase2Price(uint256 _price) external onlyOwner {
        phase2Price = _price;
    }

    function setPhase2Rate(uint256 _rate) external onlyOwner {
        phase2PriceRate = _rate;
    }

    function setMagic(address _magic) external onlyOwner {
        magic = IERC20Upgradeable(_magic);
    }

    function endPhase1() external onlyOwner {
        PHASE1_ENDED = !PHASE1_ENDED;
    }

    function setPublicPrice(uint256 _PUBLIC_PRICE) external onlyOwner {
        PUBLIC_PRICE = _PUBLIC_PRICE;
    }

    function setPause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function setRoot(bytes32 newRoot) external onlyOwner {
        root = newRoot;
    }

    /** PUBLIC */

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return traits.tokenURI(tokenId);
    }

    function getTokenTraits(uint256 tokenId)
        public
        view
        returns (PeekABooTraits memory)
    {
        return tokenTraits[tokenId];
    }

    function getGhostMapGridFromTokenId(uint256 tokenId)
        external
        view
        returns (GhostMap memory)
    {
        return ghostMaps[tokenId];
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(funds);
        funds = 0;
    }
}

