// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./StorageInterfaceV5.sol";

contract GNSNftRewardsV6_4_1 is Initializable {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;

    // Params (constant)
    uint constant ROUND_LENGTH = 50;
    uint constant MIN_TRIGGER_TIMEOUT = 1;
    uint constant MIN_SAME_BLOCK_LIMIT = 5;
    uint constant MAX_SAME_BLOCK_LIMIT = 50;
    uint constant PRECISION = 1e10; // 10 decimals

    // Params (adjustable)
    uint public triggerTimeout; // blocks
    uint public sameBlockLimit; // bots

    // Custom data types
    struct TriggeredLimit {
        address first;
        address[] sameBlock;
        uint block;
        uint240 linkFee;
        uint16 sameBlockLimit;
    }
    struct TriggeredLimitId {
        address trader;
        uint pairIndex;
        uint index;
        StorageInterfaceV5.LimitOrder order;
    }
    struct RoundDetails {
        uint240 tokens;
        uint16 totalEntries;
    }

    enum OpenLimitOrderType {
        LEGACY,
        REVERSAL,
        MOMENTUM
    }

    // State
    uint public currentOrder; // current order in round
    uint public currentRound; // current round (1 round = 50 orders)

    mapping(uint => RoundDetails) public roundTokens; // total token rewards and entries for a round
    mapping(address => mapping(uint => uint)) public roundOrdersToClaim; // orders to claim from a round (out of 50)

    mapping(address => uint) public tokensToClaim; // rewards other than pool (first & same block)

    mapping(address => mapping(uint => mapping(uint => mapping(StorageInterfaceV5.LimitOrder => TriggeredLimit))))
        public triggeredLimits; // limits being triggered

    mapping(address => mapping(uint => mapping(uint => OpenLimitOrderType))) public openLimitOrderTypes;
    bool public stateCopied;

    // Tracker to prevent multiple triggers from same address or same nft
    mapping(bytes32 => bool) public botInUse;

    // Statistics
    mapping(address => uint) public tokensClaimed; // 1e18
    uint public tokensClaimedTotal; // 1e18

    // Events
    event NumberUpdated(string name, uint value);

    event TriggeredFirst(TriggeredLimitId id, address bot, uint linkFee);
    event TriggeredSameBlock(TriggeredLimitId id, address bot, uint linkContribution);
    event TriggerUnregistered(TriggeredLimitId id);
    event TriggerRewarded(TriggeredLimitId id, address first, uint sameBlockCount, uint sameBlockLimit, uint reward);

    event PoolTokensClaimed(address bot, uint fromRound, uint toRound, uint tokens);
    event TokensClaimed(address bot, uint tokens);

    function initialize(StorageInterfaceV5 _storageT, uint _triggerTimeout, uint _sameBlockLimit) external initializer {
        require(
            address(_storageT) != address(0) &&
                _triggerTimeout >= MIN_TRIGGER_TIMEOUT &&
                _sameBlockLimit >= MIN_SAME_BLOCK_LIMIT &&
                _sameBlockLimit <= MAX_SAME_BLOCK_LIMIT,
            "WRONG_PARAMS"
        );

        storageT = _storageT;

        triggerTimeout = _triggerTimeout;
        sameBlockLimit = _sameBlockLimit;

        currentOrder = 1;
    }

    function initializeV2() external reinitializer(2) {
        // Force-ends current round which allows botters to claim pending rewards; would be stuck forever otherwise
        currentOrder = 1;
        currentRound++;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyTrading() {
        require(msg.sender == storageT.trading(), "TRADING_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    function copyOldLimitTypes(uint start, uint end) external onlyGov {
        require(!stateCopied, "COPY_DONE");
        require(start <= end, "START_AFTER_END");

        NftRewardsInterfaceV6_3_1 old;

        if (block.chainid == 137) {
            // Polygon Mainnet
            old = NftRewardsInterfaceV6_3_1(0x3470756E5B490a974Bc25FeEeEb24c11102f5268);
        } else if (block.chainid == 80001) {
            // Mumbai
            old = NftRewardsInterfaceV6_3_1(0x3982E3de77DAd60373C0c2c539fCb93Bd288D2f5);
        } else if (block.chainid == 42161) {
            // Arbitrum
            old = NftRewardsInterfaceV6_3_1(0xc2d107e870927E3fb1127E6c1a33De5C863505b8);
        } else {
            revert("UNKNOWN_CHAIN");
        }

        StorageInterfaceV5.OpenLimitOrder[] memory openLimitOrders = IStateCopyUtils(address(storageT))
            .getOpenLimitOrders();
        require(start < openLimitOrders.length, "START_TOO_BIG");

        if (end >= openLimitOrders.length) {
            end = openLimitOrders.length - 1;
        }

        for (uint i = start; i <= end; ) {
            StorageInterfaceV5.OpenLimitOrder memory o = openLimitOrders[i];
            openLimitOrderTypes[o.trader][o.pairIndex][o.index] = OpenLimitOrderType(
                uint(old.openLimitOrderTypes(o.trader, o.pairIndex, o.index))
            );
            ++i;
        }
    }

    function setStateCopyAsDone() external onlyGov {
        stateCopied = true;
    }

    // Manage params
    function updateTriggerTimeout(uint _triggerTimeout) external onlyGov {
        require(_triggerTimeout >= MIN_TRIGGER_TIMEOUT, "BELOW_MIN");
        triggerTimeout = _triggerTimeout;
        emit NumberUpdated("triggerTimeout", _triggerTimeout);
    }

    function updateSameBlockLimit(uint _sameBlockLimit) external onlyGov {
        require(_sameBlockLimit >= MIN_SAME_BLOCK_LIMIT, "BELOW_MIN");
        require(_sameBlockLimit <= MAX_SAME_BLOCK_LIMIT, "ABOVE_MAX");

        sameBlockLimit = _sameBlockLimit;

        emit NumberUpdated("sameBlockLimit", _sameBlockLimit);
    }

    // Triggers
    function storeFirstToTrigger(TriggeredLimitId calldata _id, address _bot, uint _linkFee) external onlyTrading {
        TriggeredLimit storage t = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];

        t.first = _bot;
        t.linkFee = uint240(_linkFee);
        t.sameBlockLimit = uint16(sameBlockLimit);

        delete t.sameBlock;
        t.block = block.number;
        t.sameBlock.push(_bot);

        emit TriggeredFirst(_id, _bot, _linkFee);
    }

    function storeTriggerSameBlock(TriggeredLimitId calldata _id, address _bot) external onlyTrading {
        TriggeredLimit storage t = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];

        require(t.block == block.number, "TOO_LATE");
        require(t.sameBlock.length < t.sameBlockLimit, "SAME_BLOCK_LIMIT");

        uint linkContribution = t.linkFee / t.sameBlockLimit;

        // transfer 1/N th of the trigger link cost in exchange for an equal share of reward
        storageT.linkErc677().transferFrom(_bot, t.first, linkContribution);

        t.sameBlock.push(_bot);

        emit TriggeredSameBlock(_id, _bot, linkContribution);
    }

    function unregisterTrigger(TriggeredLimitId calldata _id) external onlyCallbacks {
        delete triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];
        emit TriggerUnregistered(_id);
    }

    // Distribute rewards
    function distributeNftReward(
        TriggeredLimitId calldata _id,
        uint _reward,
        uint _tokenPriceDai
    ) external onlyCallbacks {
        TriggeredLimit memory t = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];

        require(t.block > 0, "NOT_TRIGGERED");

        uint nextRound = currentRound + 1;
        uint linkEquivalentRewards = linkToTokenRewards(t.linkFee, _tokenPriceDai); // amount of link spent in gns

        // if we've somehow ended up with an odd rate revert to using full rewards
        if (linkEquivalentRewards > _reward) linkEquivalentRewards = _reward;

        // rewards per trigger
        uint sameBlockReward = linkEquivalentRewards / t.sameBlockLimit;

        for (uint i = 0; i < t.sameBlock.length; i++) {
            address bot = t.sameBlock[i];

            tokensToClaim[bot] += sameBlockReward; // link refund
            roundOrdersToClaim[bot][nextRound]++; // next round pool entry
        }

        uint missingSameBlocks = t.sameBlockLimit - t.sameBlock.length;
        if (missingSameBlocks > 0) {
            // reward first trigger equivalent amount of missed link refunds in gns, but no extra entries into the pool
            tokensToClaim[t.first] += sameBlockReward * missingSameBlocks;
        }

        // REWARD POOLS ARE BLIND
        // when you trigger orders you earn entries for next round
        // next round tokens can't be predicted
        // rewards are added to current round and claimable by previous round (currentRound - 1) entrants

        roundTokens[currentRound].tokens += uint240(_reward - linkEquivalentRewards);
        roundTokens[nextRound].totalEntries += uint16(t.sameBlock.length);

        storageT.handleTokens(address(this), currentRound > 0 ? _reward : linkEquivalentRewards, true);

        if (currentOrder == ROUND_LENGTH) {
            currentOrder = 1;
            currentRound++;
        } else {
            currentOrder++;
        }

        emit TriggerRewarded(_id, t.first, t.sameBlock.length, t.sameBlockLimit, _reward);
    }

    // Claim rewards
    function claimPoolTokens(uint _fromRound, uint _toRound) external {
        require(_toRound >= _fromRound, "TO_BEFORE_FROM");
        require(_toRound < currentRound, "TOO_EARLY");

        uint tokens;

        // due to blind rewards round 0 will have 0 entries; r[0] rewards are effectively burned/never minted
        for (uint i = _fromRound; i <= _toRound; i++) {
            uint roundEntries = roundOrdersToClaim[msg.sender][i];

            if (roundEntries > 0) {
                RoundDetails memory roundDetails = roundTokens[i];
                tokens += (roundEntries * roundDetails.tokens) / roundDetails.totalEntries;
                roundOrdersToClaim[msg.sender][i] = 0;
            }
        }

        require(tokens > 0, "NOTHING_TO_CLAIM");
        storageT.token().transfer(msg.sender, tokens);

        tokensClaimed[msg.sender] += tokens;
        tokensClaimedTotal += tokens;

        emit PoolTokensClaimed(msg.sender, _fromRound, _toRound, tokens);
    }

    function claimTokens() external {
        uint tokens = tokensToClaim[msg.sender];
        require(tokens > 0, "NOTHING_TO_CLAIM");

        tokensToClaim[msg.sender] = 0;
        storageT.token().transfer(msg.sender, tokens);

        tokensClaimed[msg.sender] += tokens;
        tokensClaimedTotal += tokens;

        emit TokensClaimed(msg.sender, tokens);
    }

    // Manage open limit order types
    function setOpenLimitOrderType(
        address _trader,
        uint _pairIndex,
        uint _index,
        OpenLimitOrderType _type
    ) external onlyTrading {
        openLimitOrderTypes[_trader][_pairIndex][_index] = _type;
    }

    // Set bot address and NFT in use so it cannot be used in the same order twice
    function setNftBotInUse(bytes32 nftHash, bytes32 botHash) external onlyTrading {
        botInUse[nftHash] = true;
        botInUse[botHash] = true;
    }

    // Getters
    function triggered(TriggeredLimitId calldata _id) external view returns (bool) {
        TriggeredLimit memory t = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];
        return t.block > 0;
    }

    function timedOut(TriggeredLimitId calldata _id) external view returns (bool) {
        TriggeredLimit memory t = triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order];
        return t.block > 0 && block.number - t.block >= triggerTimeout;
    }

    function sameBlockTriggers(TriggeredLimitId calldata _id) external view returns (address[] memory) {
        return triggeredLimits[_id.trader][_id.pairIndex][_id.index][_id.order].sameBlock;
    }

    function getNftBotHashes(
        uint triggerBlock,
        address bot,
        uint nftId,
        address trader,
        uint pairIndex,
        uint index
    ) external pure returns (bytes32, bytes32) {
        return (
            keccak256(abi.encodePacked("N", triggerBlock, nftId, trader, pairIndex, index)),
            keccak256(abi.encodePacked("B", triggerBlock, bot, trader, pairIndex, index))
        );
    }

    function nftBotInUse(bytes32 nftHash, bytes32 botHash) external view returns (bool) {
        return botInUse[nftHash] || botInUse[botHash];
    }

    function linkToTokenRewards(uint linkFee, uint tokenPrice) public view returns (uint) {
        (, int linkPriceUsd, , , ) = storageT.priceAggregator().linkPriceFeed().latestRoundData();
        return (linkFee * uint(linkPriceUsd) * PRECISION) / tokenPrice / 1e8;
    }
}

