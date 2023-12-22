// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC721EnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./Utils.sol";
import "./PageRank.sol";

contract Cta is
    ERC721EnumerableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using Utils for Leaderboard;

    uint32 public minThreshold;
    uint32 public maxThreshold;
    uint256 public minTimeToReveal;
    uint256 public maxTimeToReveal;

    uint256 public tlpIterationsPerSecond;

    uint256 public totalPublicSupply;
    uint256 public totalPrivateSupply;

    address[] private allHunters;

    //CTA Mappings
    mapping(uint256 => Leaderboard) private tokenIdToLeaderboardMap;
    mapping(bytes32 => uint256) private hashToLeaderboardTokenIdMap;
    mapping(address => HunterLeaderboardIds) private hunterToLeaderboardsIdsMap;

    // CTA Events
    event HunterAddedToLeaderboard(
        address indexed hunter,
        uint256 indexed tokenId,
        bytes32 indexed hash
    );
    event NewLeaderboardMint(
        address indexed hunter,
        uint256 indexed tokenId,
        bytes32 indexed hash
    );
    event LeaderboardRevealed(
        address indexed hunter,
        uint256 indexed tokenId,
        bytes32 indexed hash,
        string reason
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //initialize the constructor with ERC721openzepplin name and symbol
    function initialize(
        uint32 initialMinThreshold,
        uint32 initialMaxThreshold,
        uint256 initialMinTimeToReveal,
        uint256 initialMaxTimeToReveal,
        uint256 initialTLPIterationsPerSecond
    ) public initializer {
        __ERC721_init("Capture The Alpha", "cta");
        __ERC721Enumerable_init();
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        minThreshold = initialMinThreshold;
        maxThreshold = initialMaxThreshold;
        minTimeToReveal = initialMinTimeToReveal;
        maxTimeToReveal = initialMaxTimeToReveal;
        tlpIterationsPerSecond = initialTLPIterationsPerSecond;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setThresholds(
        uint32 minThresholdToSet,
        uint32 maxThresholdToSet
    ) external onlyOwner {
        minThreshold = minThresholdToSet;
        maxThreshold = maxThresholdToSet;
    }

    function setRevealTimes(
        uint256 minTimeToRevealToSet,
        uint256 maxTimeToRevealToSet
    ) external onlyOwner {
        minTimeToReveal = minTimeToRevealToSet;
        maxTimeToReveal = maxTimeToRevealToSet;
    }

    function setTLPIterationsPerSecond(
        uint256 tlpIterationsPerSecondToSet
    ) external onlyOwner {
        tlpIterationsPerSecond = tlpIterationsPerSecondToSet;
    }

    /**
     * @notice CTA mint function
     * @dev mint a new leaderboard
     * @param mintData MintData
     */
    function mint(MintData memory mintData) external whenNotPaused {
        if (
            mintData.revealThreshold < minThreshold ||
            mintData.revealThreshold > maxThreshold
        ) {
            revert CTAThresholdOutOfBoundaries(
                mintData.revealThreshold,
                minThreshold,
                maxThreshold
            );
        }

        if (
            mintData.timeToAllowReveal < minTimeToReveal ||
            mintData.timeToAllowReveal > maxTimeToReveal
        ) {
            revert CTATimeToRevealOutOfBoundaries(
                mintData.timeToAllowReveal,
                minTimeToReveal,
                maxTimeToReveal
            );
        }

        if (
            mintData.timeLockPuzzleIterations !=
            mintData.timeToAllowReveal * tlpIterationsPerSecond
        ) {
            revert CTAInconsistentTLPIterations(
                mintData.timeLockPuzzleIterations
            );
        }

        if (mintData.verificatorsBytes.length != mintData.revealThreshold) {
            revert CTAInvalidVerificators(
                mintData.verificatorsBytes.length,
                mintData.revealThreshold
            );
        }

        bool validGenerator = Utils.vsssVerifyGeneratorOrder(
            mintData.generatorBytes
        );

        bool validBlindingGenerator = Utils.vsssVerifyGeneratorOrder(
            mintData.blindingGeneratorBytes
        );

        if (!validGenerator || !validBlindingGenerator) {
            revert CTAInvalidGenerator();
        }

        bool validShare = Utils.vsssVerifyShare(
            mintData.joinData,
            mintData.generatorBytes,
            mintData.blindingGeneratorBytes,
            mintData.verificatorsBytes
        );

        if (!validShare) {
            revert CTAInvalidShare();
        }

        uint256 supply = totalSupply();

        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[
            hashToLeaderboardTokenIdMap[mintData.joinData.secretHash]
        ];
        bool leaderboardExists = _leaderboard.shares.length >= 1;

        if (leaderboardExists) {
            revert CTACannotMintExistentLeaderboard();
        }

        uint256 newTokenId = supply + 1;

        // "Create" new leaderboard
        Leaderboard storage _newLeaderboard = tokenIdToLeaderboardMap[
            newTokenId
        ];
        _newLeaderboard.hash = mintData.joinData.secretHash;
        _newLeaderboard.shares.push(
            Share({
                hunter: msg.sender,
                index: mintData.joinData.indexBytes,
                evaluation: mintData.joinData.shareBytes,
                timeWhenJoined: block.timestamp
            })
        );
        _newLeaderboard.timeToAllowReveal = uint64(mintData.timeToAllowReveal);
        _newLeaderboard.revealThreshold = mintData.revealThreshold;
        _newLeaderboard.generator = mintData.generatorBytes;
        _newLeaderboard.blindingGenerator = mintData.blindingGeneratorBytes;
        _newLeaderboard.verificators = mintData.verificatorsBytes;
        _newLeaderboard.mintTimestamp = uint64(block.timestamp);
        _newLeaderboard.timeLockedKey = mintData.timeLockedKeyBytes;
        _newLeaderboard.timeLockPuzzleModulus = mintData
            .timeLockPuzzleModulusBytes;
        _newLeaderboard.timeLockPuzzleBase = mintData.timeLockPuzzleBaseBytes;
        _newLeaderboard.timeLockPuzzleIterations = mintData
            .timeLockPuzzleIterations;
        _newLeaderboard.encryptedSecretCiphertext = mintData.ciphertextBytes;
        _newLeaderboard.encryptedSecretIv = mintData.ivBytes;
        hashToLeaderboardTokenIdMap[mintData.joinData.secretHash] = newTokenId;

        totalPrivateSupply++;
        hunterToLeaderboardsIdsMap[msg.sender].tokenIds.push(newTokenId);
        hunterToLeaderboardsIdsMap[msg.sender].privateSupply++;

        registerHunter();

        emit NewLeaderboardMint(
            msg.sender,
            newTokenId,
            mintData.joinData.secretHash
        );
        _safeMint(msg.sender, newTokenId);
    }

    /**
     * @notice CTA join function
     * @dev joins an existent leaderboard
     * @param joinData JoinData
     */
    function join(JoinData memory joinData) external whenNotPaused {
        Leaderboard storage _leaderboard = Utils.checkAndGetExistentLeaderboard(
            joinData,
            tokenIdToLeaderboardMap,
            hashToLeaderboardTokenIdMap
        );

        if (_leaderboard.isRevealed()) {
            revert CTACanOnlyJoinLeaderboardThatIsNotRevealed();
        }

        if (_leaderboard.shares.length >= (_leaderboard.revealThreshold - 1)) {
            revert CTACanOnlyJoinLeaderboardThatIsNotReadyToReveal();
        }

        _leaderboard.shares.push(
            Share({
                hunter: msg.sender,
                index: joinData.indexBytes,
                evaluation: joinData.shareBytes,
                timeWhenJoined: block.timestamp
            })
        );

        hunterToLeaderboardsIdsMap[msg.sender].tokenIds.push(
            hashToLeaderboardTokenIdMap[joinData.secretHash]
        );
        hunterToLeaderboardsIdsMap[msg.sender].privateSupply++;

        registerHunter();

        emit HunterAddedToLeaderboard(
            msg.sender,
            hashToLeaderboardTokenIdMap[joinData.secretHash],
            joinData.secretHash
        );
    }

    /**
     * @notice CTA revealWithShare function
     * @dev reveals a leaderboard by adding the last share
     * @param revealData RevealData
     */
    function revealWithShare(
        RevealData memory revealData
    ) external whenNotPaused {
        Leaderboard storage _leaderboard = Utils.checkAndGetExistentLeaderboard(
            revealData.joinData,
            tokenIdToLeaderboardMap,
            hashToLeaderboardTokenIdMap
        );

        if (_leaderboard.isRevealed()) {
            revert CTACanOnlyRevealLeaderboardThatIsNotRevealed();
        }

        if (_leaderboard.shares.length != (_leaderboard.revealThreshold - 1)) {
            revert CTACannotRevealLeaderboardThatIsNotReadyToReveal();
        }

        _leaderboard.shares.push(
            Share({
                hunter: msg.sender,
                index: revealData.joinData.indexBytes,
                evaluation: revealData.joinData.shareBytes,
                timeWhenJoined: block.timestamp
            })
        );

        uint256 tokenId = hashToLeaderboardTokenIdMap[
            revealData.joinData.secretHash
        ];
        hunterToLeaderboardsIdsMap[msg.sender].tokenIds.push(tokenId);
        hunterToLeaderboardsIdsMap[msg.sender].privateSupply++;

        // Reveal leaderboard
        uint256 secret = Utils.vsssInterpolate(
            _leaderboard.shares,
            revealData.interpolationInverses
        );

        _leaderboard.secret = secret;

        updateSupplyCountsOnReveal(_leaderboard);

        emit LeaderboardRevealed(
            msg.sender,
            tokenId,
            revealData.joinData.secretHash,
            "share"
        );

        // The revealer gets the NFT
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
    }

    /**
     * @notice CTA revealWithTime function
     * @dev reveals a leaderboard by sending the secret after some time
     * @param secret uint256
     * @param blindingSecretBytes bytes
     * @param secretHash bytes32
     */
    function revealWithTime(
        uint256 secret,
        bytes memory blindingSecretBytes,
        bytes32 secretHash
    ) external whenNotPaused {
        uint256 tokenId = hashToLeaderboardTokenIdMap[secretHash];
        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[tokenId];
        bool leaderboardExists = _leaderboard.shares.length >= 1;

        if (!leaderboardExists) {
            revert CTACannotRevealNonexistentLeaderboard();
        }

        if (_leaderboard.isRevealed()) {
            revert CTACanOnlyRevealLeaderboardThatIsNotRevealed();
        }

        bool tooSoonToReveal = block.timestamp - _leaderboard.mintTimestamp <
            _leaderboard.timeToAllowReveal;
        if (tooSoonToReveal) {
            revert CTATooSoonToRevealLeaderboard();
        }

        if (
            !Utils.vsssValidateSecretIntegrity(
                secret,
                blindingSecretBytes,
                _leaderboard.verificators[0],
                _leaderboard.generator,
                _leaderboard.blindingGenerator
            )
        ) {
            revert CTASecretIsNotConsistentWithHash();
        }

        _leaderboard.secret = secret;

        updateSupplyCountsOnReveal(_leaderboard);

        emit LeaderboardRevealed(msg.sender, tokenId, secretHash, "time");

        // The revealer gets the NFT
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
    }

    /**
     * @notice CTA revealWithTLP function
     * @dev reveals a leaderboard by sending the TLP revealed secret, along with the factorization of the modulus
     * @param secret uint256
     * @param blindingSecretBytes bytes
     * @param secretHash bytes32
     * @param keyBytes bytes
     * @param pBytes bytes memory
     * @param qBytes bytes memory
     */
    function revealWithTLP(
        uint256 secret,
        bytes memory blindingSecretBytes,
        bytes32 secretHash,
        bytes memory keyBytes,
        bytes memory pBytes,
        bytes memory qBytes
    ) external whenNotPaused {
        uint256 tokenId = hashToLeaderboardTokenIdMap[secretHash];
        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[tokenId];
        bool leaderboardExists = _leaderboard.shares.length >= 1;

        if (!leaderboardExists) {
            revert CTACannotRevealNonexistentLeaderboard();
        }

        if (_leaderboard.isRevealed()) {
            revert CTACanOnlyRevealLeaderboardThatIsNotRevealed();
        }

        if (
            !Utils.vsssValidateSecretIntegrity(
                secret,
                blindingSecretBytes,
                _leaderboard.verificators[0],
                _leaderboard.generator,
                _leaderboard.blindingGenerator
            )
        ) {
            revert CTASecretIsNotConsistentWithHash();
        }

        if (
            !Utils.tlpValidateKeyIntegrity(
                keyBytes,
                pBytes,
                qBytes,
                _leaderboard.timeLockedKey,
                _leaderboard.timeLockPuzzleBase,
                _leaderboard.timeLockPuzzleModulus,
                _leaderboard.timeLockPuzzleIterations
            )
        ) {
            revert CTAEncryptionKeyIsNotConsistentWithTLP();
        }

        _leaderboard.secret = secret;

        updateSupplyCountsOnReveal(_leaderboard);

        emit LeaderboardRevealed(msg.sender, tokenId, secretHash, "TLP");

        // The revealer gets the NFT
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
    }

    /**
     * @notice CTA tokenURI function
     * generate the tokenURI from a given tokenId, it overrides the ERC721 tokenURI
     * @dev requires the tokenId exists
     * generates the json metadata of the nft
     * @param tokenId uint256
     * @return string memory
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) {
            revert ERC721MetadataURIQueryForNonexistentToken();
        }

        return Utils.tokenURI(tokenId, tokenIdToLeaderboardMap);
    }

    /**
     * @notice get leaderboard info by hash
     * @param hash bytes32
     * @return memory Leaderboard
     */
    function getLeaderboardByHash(
        bytes32 hash
    ) external view returns (GetLeaderboardQueryResult memory) {
        uint256 tokenId = hashToLeaderboardTokenIdMap[hash];

        return getLeaderboard(tokenId);
    }

    function getLeaderboardIdByHash(bytes32 hash) external view returns (uint) {
        uint256 tokenId = hashToLeaderboardTokenIdMap[hash];

        return tokenId;
    }

    function getLeaderboard(
        uint256 tokenId
    ) public view returns (GetLeaderboardQueryResult memory result) {
        if (!_exists(tokenId)) {
            revert CTANonexistentLeaderboard(tokenId);
        }
        Leaderboard storage _leaderboard = tokenIdToLeaderboardMap[tokenId];
        result.leaderboard = _leaderboard;
        result.revealed = _leaderboard.isRevealed();
        return result;
    }

    function computeGlobalScore()
        external
        view
        returns (address[] memory hunters, SD59x18[] memory scores)
    {
        // Find number of Hunters
        uint256 supply = totalSupply();

        if (supply == 0 || allHunters.length <= 1) {
            return (allHunters, scores);
        }

        uint256 nbHunters = allHunters.length;
        (int256[][] memory weightMatrix, uint256 publicSupply) = Utils
            .getAdjacencyMatrix(
                nbHunters,
                supply,
                tokenIdToLeaderboardMap,
                allHunters
            );

        if (publicSupply == 0) {
            return (allHunters, scores);
        }

        // Compute scores with the weighted PageRank algorithm
        (SD59x18[] memory scoreArray, bool hasConverged) = PageRank
            .weightedPagerank(weightMatrix, sd(0.85e18));

        if (!hasConverged) {
            revert CTAPageRankNotConverged();
        }

        return (allHunters, scoreArray);
    }

    function getHunterLeaderboardIds(
        address accountAddress
    ) external view returns (HunterLeaderboardIds memory) {
        return hunterToLeaderboardsIdsMap[accountAddress];
    }

    function updateSupplyCountsOnReveal(
        Leaderboard storage leaderboard_
    ) internal {
        totalPrivateSupply--;
        totalPublicSupply++;

        for (uint256 i = 0; i < leaderboard_.shares.length; i++) {
            hunterToLeaderboardsIdsMap[leaderboard_.shares[i].hunter]
                .privateSupply--;
            hunterToLeaderboardsIdsMap[leaderboard_.shares[i].hunter]
                .publicSupply++;
        }
    }

    /**
     * @notice CTA hunter registering
     * @dev registers a hunter in the list of hunters
     */
    function registerHunter() internal {
        bool isAlreadyRegistered = false;
        uint length = allHunters.length;
        for (uint256 index = 0; index < length; index++) {
            if (allHunters[index] == msg.sender) {
                isAlreadyRegistered = true;
                break;
            }
        }

        if (!isAlreadyRegistered) {
            allHunters.push(msg.sender);
        }
    }
}

