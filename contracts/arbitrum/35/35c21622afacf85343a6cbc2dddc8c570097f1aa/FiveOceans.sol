// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./Sharks.sol";
import "./Teeth.sol";

contract FiveOceans is Ownable {
    uint256 public immutable EPOCH_DURATION_IN_SECONDS = 86400;
    uint public immutable OCEANS_COUNT = 5;

    Teeth public immutable teeth;
    Sharks public immutable sharks;

    event Commited(uint256 indexed epochId, uint256 sharkId);
    event Revealed(uint256 indexed epochId, uint256 sharkId, uint256 oceanId);
    event EpochSettled(uint256 indexed epochId);
    event PayoutProcessed(uint256 indexed epochId, address to, uint256 amount);
    event TeethRewardsPerEpochChanged(uint256 teethRewardsPerEpoch);
    event BucketSizePercentageChanged(uint256 bucketSizePercentage);
    event RewardsRateByOceanRankChanged(uint256 rank1, uint256 rank2, uint256 rank3, uint256 rank4, uint256 rank5);

    struct Epoch {
        uint32 id;
        uint32 commitsCount;
        uint256 teethRewards;
        uint256 payouts;
        mapping(uint32 => Ocean) oceans;
        mapping(uint32 => bytes32) commits; // sharkId => commit
        mapping(uint32 => uint32) reveals; // sharkId => oceanId
        mapping (uint32 => uint32) rewardsRateByOceanRank; // oceanRank => rate
        mapping (address => uint256) payoutsByAddress;
    }

    struct Ocean {
        uint32 totalSharksCount;
        uint32 rank;

        uint256 points;
        uint256 totalSharksSize;

        mapping (address => uint256) sharksSizeByAddress;
        mapping (address => uint32[]) sharksIdsByAddress;
        mapping (address => uint256) payoutsByAddress;
    }

    mapping (uint32 => Epoch) epochs;
    mapping (address => uint32[]) epochIdsWithPendingPayoutsByAddress;

    uint256 public immutable genesisTimestamp;
    uint32 public bucketSizePercentage;

    uint256 public teethRewardsPerEpoch;


    mapping (uint32 => uint32) public rewardsRateByOceanRank;

    constructor(address teeth_, address sharks_, uint256 genesisTimestamp_) {
        teeth = Teeth(teeth_);
        sharks = Sharks(sharks_);

        genesisTimestamp = genesisTimestamp_;

        setTeethRewardsPerEpoch(10000 ether);

        setRewardsRateByOceanRank(60, 20, 10, 7, 3);

        setBucketSizePercentage(5);
    }

    function setTeethRewardsPerEpoch(uint256 teethRewardsPerEpoch_) public onlyOwner {
        teethRewardsPerEpoch = teethRewardsPerEpoch_;

        emit TeethRewardsPerEpochChanged(teethRewardsPerEpoch);
    }

    function setBucketSizePercentage(uint32 bucketSizePercentage_) public onlyOwner {
        require(bucketSizePercentage_ > 0 && bucketSizePercentage_ <= 100, "FiveOceans: invalid percentage");

        bucketSizePercentage = bucketSizePercentage_;

        emit BucketSizePercentageChanged(bucketSizePercentage);
    }


    function setRewardsRateByOceanRank(uint32 rank1, uint32 rank2, uint32 rank3, uint32 rank4, uint32 rank5) public onlyOwner {
        require(rank1 + rank2 + rank3 + rank4 + rank5 == 100, "FiveOceans: rates should amount to 100");

        rewardsRateByOceanRank[1] = rank1;
        rewardsRateByOceanRank[2] = rank2;
        rewardsRateByOceanRank[3] = rank3;
        rewardsRateByOceanRank[4] = rank4;
        rewardsRateByOceanRank[5] = rank5;

        emit RewardsRateByOceanRankChanged(rank1, rank2, rank3, rank4, rank5);
    }

    function getCurrentEpochId() public view returns(uint32) {
        return uint32(((block.timestamp - genesisTimestamp) / EPOCH_DURATION_IN_SECONDS) + 1);
    }

    function epochMedianTimestamp(uint32 epochId) public view returns(uint256) {
        uint256 epochStartedAt = genesisTimestamp + (epochId * EPOCH_DURATION_IN_SECONDS) - EPOCH_DURATION_IN_SECONDS;

        return epochStartedAt + EPOCH_DURATION_IN_SECONDS/2;
    }

    function canCommitInEpoch(uint32 epochId) public view returns (bool) {
        return (epochId == getCurrentEpochId() && block.timestamp < epochMedianTimestamp(epochId));
    }

    function canRevealInEpoch(uint32 epochId) public view returns (bool) {
        return (epochId == getCurrentEpochId() && block.timestamp >= epochMedianTimestamp(epochId));
    }

    function commit(uint32 epochId, uint32[] memory sharksIds, bytes32[] memory commits) public {
        require(canCommitInEpoch(epochId) == true, "FiveOceans: cannot commit in this epoch");

        Epoch storage epoch = epochs[epochId];

        if (epoch.teethRewards == 0) {
            // Cache these values because they might change in later epochs
            epoch.teethRewards = teethRewardsPerEpoch;
            for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
                epoch.rewardsRateByOceanRank[oceanId] = rewardsRateByOceanRank[oceanId];
            }
        }

        for (uint i = 0; i < sharksIds.length; i++) {
            uint32 sharkId = sharksIds[i];
            require(sharks.ownerOf(sharkId) == msg.sender, "FiveOceans: not your shark");

            epoch.commits[sharkId] = commits[i];
            epoch.commitsCount += 1;
            emit Commited(epochId, sharkId);
        }
    }

    function reveal(
        uint32 epochId,
        uint32[] memory sharksIds,
        uint32[] memory oceansIds,
        bytes32 secret
    ) public {
        require(canRevealInEpoch(epochId) == true, "FiveOceans: cannot reveal in this epoch");

        Epoch storage epoch = epochs[epochId];

        epochIdsWithPendingPayoutsByAddress[msg.sender].push(epochId);

        for (uint i = 0; i < sharksIds.length; i++) {
            uint32 sharkId = sharksIds[i];
            uint32 oceanId = oceansIds[i];

            require(epoch.reveals[sharkId] == 0, "FiveOceans: shark already revealed");
            require(sharks.ownerOf(sharkId) == msg.sender, "FiveOceans: not your shark");
            require(
                epoch.commits[sharkId] == convertRevealToCommit(msg.sender, oceanId, sharkId, secret),
                "FiveOceans: wrong secret"
            );


            uint256 sharkSize = sharks.size(sharkId);
            require(sharkSize != 0, "FiveOceans: shark is not revealed");

            epoch.reveals[sharkId] = oceanId;

            Ocean storage ocean = epoch.oceans[oceanId];
            ocean.totalSharksSize += sharkSize;
            ocean.totalSharksCount += 1;
            ocean.sharksSizeByAddress[msg.sender] += sharkSize;
            ocean.sharksIdsByAddress[msg.sender].push(sharkId);

            emit Revealed(epochId, sharkId, oceanId);
        }
    }


    function convertRevealToCommit(address address_, uint32 oceanId, uint32 sharkId, bytes32 secret) pure public returns (bytes32) {
        return keccak256(abi.encodePacked(address_, oceanId, sharkId, secret));
    }

    function settleEpoch(uint32 epochId) public {
        require(epochId < getCurrentEpochId(), "FiveOceans: cannot settle epoch yet");
        require(epochs[epochId].oceans[1].rank == 0, "FiveOceans: has already been settled");

        // group into buckets
        uint256 bucket = getTotalSharksSizeInEpoch(epochId) * bucketSizePercentage / 100;
        if (bucket == 0) {
            bucket = 1;
        }

        for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            epochs[epochId].oceans[oceanId].points = epochs[epochId].oceans[oceanId].totalSharksSize / bucket;
            epochs[epochId].oceans[oceanId].rank = 1;
        }

        for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            Ocean storage ocean = epochs[epochId].oceans[oceanId];
            for (uint32 comparedOceanId = oceanId + 1; comparedOceanId <= OCEANS_COUNT; comparedOceanId++) {
                Ocean storage comparedOcean = epochs[epochId].oceans[comparedOceanId];

                if (ocean.points <= comparedOcean.points) {
                    comparedOcean.rank++;
                } else {
                    ocean.rank++;
                }
            }
        }

        emit EpochSettled(epochId);
    }

    function getRewardsForOcean(uint32 epochId, uint32 oceanId) public view returns (uint256) {
        uint32 oceanRank = getOceanRankInEpoch(epochId, oceanId);
        return epochs[epochId].teethRewards * rewardsRateByOceanRank[oceanRank] / 100;
    }

    function getOceanBySharkIdInEpoch(uint32 sharkId, uint32 epochId) public view returns (uint32) {
        return epochs[epochId].reveals[sharkId];
    }
    function getCommitForSharkInEpoch(uint32 sharkId, uint32 epochId) public view returns (bytes32) {
        return epochs[epochId].commits[sharkId];
    }

    function getSharksIdsInOceanInEpochForAddress(uint32 oceanId, uint32 epochId, address address_) public view returns (uint32[] memory) {
        return epochs[epochId].oceans[oceanId].sharksIdsByAddress[address_];
    }

    function getPendingPayoutInEpochForAddress(uint32 epochId, address to) public view returns (uint256) {
        uint256 _pendingPayout = 0;

        for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            _pendingPayout += getPendingPayoutFromOceanInEpochForAddress(epochId, oceanId, to);
        }

        return _pendingPayout;
    }

    function getClaimedPayoutInEpochForAddress(uint32 epochId, address to) public view returns (uint256) {
        return epochs[epochId].payoutsByAddress[to];
    }


    function getPendingPayoutFromOceanInEpochForAddress(uint32 epochId, uint32 oceanId, address to) public view returns (uint256) {
        Ocean storage ocean = epochs[epochId].oceans[oceanId];

        if (ocean.payoutsByAddress[to] > 0) {
            return 0;
        }

        if (ocean.totalSharksSize == 0 || ocean.sharksSizeByAddress[to] == 0) {
            return 0;
        }

        return getPayoutFromOceanInEpochForAddress(epochId, oceanId, to);
    }

    function getPayoutFromOceanInEpochForAddress(uint32 epochId, uint32 oceanId, address to) public view returns (uint256) {
        Ocean storage ocean = epochs[epochId].oceans[oceanId];

        uint256 payout = (getRewardsForOcean(epochId, oceanId) * ocean.sharksSizeByAddress[to]) / ocean.totalSharksSize;

        return payout;
    }


    function processPayoutsForAddress(address to) public {
        for (uint i; i < epochIdsWithPendingPayoutsByAddress[to].length; i++) {
            uint32 epochId = epochIdsWithPendingPayoutsByAddress[to][i];

            processPayoutInEpochForAddress(epochId, to);
        }

        delete epochIdsWithPendingPayoutsByAddress[to];
    }

    function processPayoutInEpochForAddress(uint32 epochId, address to) public returns (uint256) {
        Epoch storage epoch = epochs[epochId];

        // Using if and not require because there might be duplicate
        // epochIds in epochIdsWithPendingPayoutsByAddress if someone reveals twice

        if(epoch.payoutsByAddress[to] > 0) {
            return 0;
        }

        uint256 _totalPayout = 0;

        for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            uint256 payout = getPendingPayoutFromOceanInEpochForAddress(epochId, oceanId, to);
            epochs[epochId].oceans[oceanId].payoutsByAddress[to] = payout;
            _totalPayout += payout;
        }

        epoch.payoutsByAddress[to] = _totalPayout;
        epoch.payouts += _totalPayout;

        require(epoch.payouts <= epoch.teethRewards, "wut"); // sanity check, should not ever happen

        teeth.mint(to, _totalPayout);
        emit PayoutProcessed(epochId, to, _totalPayout);

        return _totalPayout;
    }

    function getOceanInEpoch(uint32 epochId, uint32 oceanId) public view returns (uint256, uint32, uint32, uint256) {
        Ocean storage ocean = epochs[epochId].oceans[oceanId];
        return (ocean.totalSharksSize, ocean.totalSharksCount, ocean.rank, ocean.points);
    }

    function getOceanRankInEpoch(uint32 epochId, uint32 oceanId) public view returns (uint32) {
        return epochs[epochId].oceans[oceanId].rank;
    }

    function getOceanPointsInEpoch(uint32 epochId, uint32 oceanId) public view returns (uint256) {
        return epochs[epochId].oceans[oceanId].points;
    }


    function getTotalSharksSizeInEpoch(uint32 epochId) public view returns (uint256) {
        uint256 count = 0;

        for (uint32 oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            count += epochs[epochId].oceans[oceanId].totalSharksSize;
        }

        return count;
    }


}
