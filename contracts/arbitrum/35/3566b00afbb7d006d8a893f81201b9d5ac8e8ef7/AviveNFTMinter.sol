// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC721.sol";
import "./IERC20.sol";

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";
import "./AviveGenesisNFT.sol";

contract AviveNFTMinter is AviveGenesisNFT, ReentrancyGuard {
    struct MintRound {
        uint32 id;
        uint64 startTime;
        uint64 endTime;
        uint64 fee;
        uint64 total;
        uint64 mintedCount;
        uint256 startId;
        uint256 reserve;
    }

    struct RewardRoud {
        uint32 id;
        uint64 startTime;
        uint64 endTime;
        uint64 winnerCount;
        uint64 claimedCount;
        uint256 prizePool;
    }

    address public verifier;

    // used to generate random number
    uint256 private recentMintTime;

    uint32 public latestRoundId;

    // roundRecords for each round, key is mintRoundId
    mapping(uint32 => MintRound) public mintRounds;
    mapping(uint32 => RewardRoud) public rewardRounds;

    // mintHistory for each wallet, key is mintRoundId, then wallet address
    mapping(uint32 => mapping(address => bool)) public mintWalletHistory;
    // mintHistory for each wallet, key is mintRoundId, then aviveId
    mapping(uint32 => mapping(uint256 => bool)) public mintAviveHistory;

    // claimHistory for each winner, key is mintRoundId, then nft address
    mapping(uint32 => mapping(uint256 => bool)) public claimHistory;

    // winnerMap for each winner, key is mintRoundId, then nft address
    mapping(uint32 => mapping(uint256 => bool)) public winnerMap;

    // events
    // setup mint round
    event LogMintRoundSetup(
        uint32 indexed roundId,
        uint64 startTime,
        uint64 endTime,
        uint64 fee,
        uint64 total,
        uint256 startId
    );
    // setup reward round
    event LogRewardRoundSetup(
        uint32 indexed roundId,
        uint64 startTime,
        uint64 endTime,
        uint32 winnerCount,
        uint256 prizePool
    );
    // generate winnerNFT list
    event LogWinnerGenerated(uint32 indexed roundId, uint256[] winnerList);

    // user mint genesis nft
    event LogGenesisMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 indexed aviveId
    );

    // genesis complete
    event LogGenesisMintCompleted(uint32 indexed roundId);

    // winner claim prize
    event LogClaimed(
        address indexed to,
        uint32 indexed roundId,
        uint256 indexed nftId,
        uint256 prizeValue
    );

    // claim complete
    event LogClaimCompleted(uint32 indexed roundId);

    event LogVerifierChanged(address indexed verifier, address oldVerifier);

    modifier isNFTOwner(uint nftID) {
        require(ERC721.ownerOf(nftID) == msg.sender, 'not owner');
        _;
    }

    constructor(
        address verifier_,
        string memory baseuri_
    ) AviveGenesisNFT(baseuri_) {
        verifier = verifier_;
    }

    function setVerifier(address verifier_) external onlyOwner {
        address oldVerifier = verifier;
        verifier = verifier_;

        emit LogVerifierChanged(verifier_, oldVerifier);
    }

    function verifySignature(
        uint32 roundId,
        uint256 aviveId,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(roundId, aviveId, verifier))
        );
        require(
            ECDSA.recover(message, signature) == verifier,
            '!INVALID_SIGNATURE!'
        );
        return true;
    }

    function isMintRoundEnded(uint32 roundId) public view returns (bool) {
        require(roundId <= latestRoundId, 'roundId not setup');
        return
            mintRounds[roundId].endTime < block.timestamp ||
            mintRounds[roundId].mintedCount >= mintRounds[roundId].total;
    }

    function isRewardRoundEnded(uint32 roundId) public view returns (bool) {
        require(roundId <= latestRoundId, 'roundId not setup');
        return
            rewardRounds[roundId].endTime < block.timestamp ||
            rewardRounds[roundId].claimedCount >=
            rewardRounds[roundId].winnerCount;
    }

    function setupMintRound(
        uint32 roundId,
        uint64 startTime,
        uint64 endTime,
        uint64 fee,
        uint64 total,
        uint256 startId
    ) external onlyOwner {
        if (latestRoundId != 0) {
            // latest mint round must be ended
            require(
                isMintRoundEnded(latestRoundId) == true,
                'last mint round not ended'
            );
            // latest reward round must be setup
            require(
                rewardRounds[latestRoundId].id != 0,
                'last reward round not setup'
            );

            // latest reward round must be ended
            require(
                isRewardRoundEnded(latestRoundId) == true,
                'last reward round not ended'
            );
        }

        require(roundId == latestRoundId + 1, 'roundId not match');
        require(startTime > block.timestamp, 'already started');
        require(endTime > startTime, 'time invalid');

        MintRound storage mintRound = mintRounds[roundId];
        mintRound.id = roundId;
        mintRound.startTime = startTime;
        mintRound.endTime = endTime;
        mintRound.fee = fee;
        mintRound.total = total;
        mintRound.startId = startId;

        latestRoundId = roundId;

        emit LogMintRoundSetup(
            roundId,
            startTime,
            endTime,
            fee,
            total,
            startId
        );
    }

    function setupRewardRound(
        uint32 roundId,
        uint64 startTime,
        uint64 endTime,
        uint32 winnerCount,
        uint256 prizePool
    ) external onlyOwner {
        // require msg.sender is EOA, not smart contract. no robot, more fair
        require(msg.sender == tx.origin, 'only EOA');

        // roundId and latestRoundId must be matched
        require(roundId == latestRoundId, 'roundId not match');
        MintRound memory mintRound = mintRounds[roundId];

        // mintRound must be ended
        require(isMintRoundEnded(latestRoundId) == true, 'mintRound not ended');
        require(startTime > block.timestamp, 'already started');
        require(endTime > startTime, 'time invalid');

        // winnerCount must be less than mintCount
        require(
            winnerCount > 0 && winnerCount <= mintRound.mintedCount,
            'winnerCount invalid'
        );

        // prizePool must be less than reserve
        require(prizePool <= mintRound.reserve, 'prizePool invalid');

        RewardRoud storage rewardRound = rewardRounds[roundId];
        require(rewardRound.id == 0, 'round already setup');

        rewardRound.id = roundId;
        rewardRound.startTime = startTime;
        rewardRound.endTime = endTime;
        rewardRound.winnerCount = winnerCount;
        rewardRound.prizePool = prizePool;
        emit LogRewardRoundSetup(
            roundId,
            startTime,
            endTime,
            winnerCount,
            prizePool
        );
        // seed is secure because _shuffle is called by owner.
        // and can't be called by smart contract
        bytes32 seed = keccak256(
            abi.encodePacked(blockhash(block.number - 1), recentMintTime)
        );

        uint256[] memory winnerList = shuffle(
            mintRound.mintedCount,
            rewardRound.winnerCount,
            mintRound.startId,
            seed
        );

        emit LogWinnerGenerated(roundId, winnerList);

        for (uint256 i = 0; i < winnerList.length; i++) {
            winnerMap[roundId][winnerList[i]] = true;
        }
    }

    function shuffle(
        uint64 mintCount,
        uint64 winnerCount,
        uint256 startId,
        bytes32 seed
    ) public pure returns (uint256[] memory) {
        uint256[] memory nftList = new uint256[](mintCount);
        uint256[] memory shuffled = new uint256[](winnerCount);

        for (uint256 i = 0; i < winnerCount; i++) {
            uint256 j = uint256(keccak256(abi.encodePacked(seed, i))) %
                (mintCount - i);

            uint256 target = nftList[i + j];
            uint256 current = nftList[i];
            shuffled[i] = target != 0 ? target : startId + i + j;
            nftList[i + j] = current != 0 ? current : startId + i;
        }
        return shuffled;
    }

    function genesisMint(
        uint32 roundId,
        uint256 aviveId,
        bytes memory signature
    ) external payable nonReentrant {
        // roundId and latestRoundId must be matched
        require(roundId == latestRoundId, 'roundId not match');
        verifySignature(roundId, aviveId, signature);

        MintRound storage mintRound = mintRounds[roundId];
        require(block.timestamp > mintRound.startTime, 'mint not started');
        require(block.timestamp <= mintRound.endTime, 'mint ended');
        require(msg.value >= mintRound.fee, 'not enough fee');
        require(
            mintWalletHistory[roundId][_msgSender()] == false &&
                mintAviveHistory[roundId][aviveId] == false,
            'already minted'
        );
        require(
            mintRound.mintedCount < mintRound.total,
            'reach max mint count'
        );
        uint256 nftId = mintRound.startId + mintRound.mintedCount;
        _safeMint(_msgSender(), nftId);
        mintRound.reserve += mintRound.fee;
        mintRound.mintedCount += 1; // current round count
        mintWalletHistory[roundId][_msgSender()] = true;
        mintAviveHistory[roundId][aviveId] = true;
        recentMintTime = block.timestamp;
        emit LogGenesisMinted(msg.sender, nftId, aviveId);
        if (mintRound.mintedCount == mintRound.total) {
            emit LogGenesisMintCompleted(roundId);
        }
    }

    function claim(
        uint32 roundId,
        uint256 nftId
    ) external nonReentrant isNFTOwner(nftId) {
        RewardRoud storage rewardRound = rewardRounds[roundId];
        require(block.timestamp > rewardRound.startTime, 'reward not started');
        require(block.timestamp <= rewardRound.endTime, 'reward ended');
        require(winnerMap[roundId][nftId] == true, 'not winner');
        require(claimHistory[roundId][nftId] == false, 'already claimed');

        uint prizeValue = rewardRound.prizePool / rewardRound.winnerCount;
        claimHistory[roundId][nftId] = true;
        rewardRound.claimedCount += 1;
        payable(msg.sender).transfer(prizeValue);

        emit LogClaimed(msg.sender, roundId, nftId, prizeValue);
        if (rewardRound.claimedCount == rewardRound.winnerCount) {
            emit LogClaimCompleted(roundId);
        }
    }

    function withdraw(uint256 amount) external onlyOwner {
        // mint round must be ended
        require(
            isMintRoundEnded(latestRoundId) == true,
            'last mint round not ended'
        );
        // latest reward round must be ended
        require(
            isRewardRoundEnded(latestRoundId) == true,
            'last reward round not ended'
        );
        uint256 balance = address(this).balance;
        require(balance >= amount, 'not enough balance');
        payable(msg.sender).transfer(amount);
    }

    function withdrawToken(
        address token,
        uint256 amount
    ) external nonReentrant onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, 'not enough balance');
        IERC20(token).transfer(msg.sender, amount);
    }

    receive() external payable {}
}

