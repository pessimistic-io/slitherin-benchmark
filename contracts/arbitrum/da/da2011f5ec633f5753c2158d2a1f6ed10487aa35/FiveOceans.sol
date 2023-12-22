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
        uint256 id;
        uint256 teethRewards;
        uint256 payouts;
        mapping(uint256 => Ocean) oceans;
        mapping(uint256 => bytes32) commits; // sharkId => commit
        mapping(uint256 => uint256) reveals; // sharkId => oceanId
        mapping (uint256 => uint256) rewardsRateByOceanRank; // oceanRank => rate
        mapping (address => uint256) payoutsByAddress;
    }

    struct Ocean {
        uint256 totalSharksSize;
        uint256 points;
        uint256 rank;
        mapping (address => uint256) sharksSizeByAddress;
        mapping (address => uint256[]) sharksIdsByAddress;
        mapping (address => uint256) payoutsByAddress;
    }

    mapping (uint256 => Epoch) epochs;

    uint256 public genesisTimestamp;

    uint256 public teethRewardsPerEpoch;

    uint256 public bucketSizePercentage;

    mapping (uint256 => uint256) public rewardsRateByOceanRank;

    constructor(address teeth_, address sharks_) {
        teeth = Teeth(teeth_);
        sharks = Sharks(sharks_);

        genesisTimestamp = block.timestamp;

        setTeethRewardsPerEpoch(10000 ether);

        setRewardsRateByOceanRank(60, 20, 10, 7, 3);

        setBucketSizePercentage(5);
    }

    function setTeethRewardsPerEpoch(uint256 teethRewardsPerEpoch_) public onlyOwner {
        teethRewardsPerEpoch = teethRewardsPerEpoch_;

        emit TeethRewardsPerEpochChanged(teethRewardsPerEpoch);
    }

    function setBucketSizePercentage(uint256 bucketSizePercentage_) public onlyOwner {
        require(bucketSizePercentage_ > 0 && bucketSizePercentage_ <= 100, "FiveOceans: invalid percentage");

        bucketSizePercentage = bucketSizePercentage_;

        emit BucketSizePercentageChanged(bucketSizePercentage);
    }


    function setRewardsRateByOceanRank(uint256 rank1, uint256 rank2, uint256 rank3, uint256 rank4, uint256 rank5) public onlyOwner {
        require(rank1 + rank2 + rank3 + rank4 + rank5 == 100, "FiveOceans: rates should amount to 100");

        rewardsRateByOceanRank[1] = rank1;
        rewardsRateByOceanRank[2] = rank2;
        rewardsRateByOceanRank[3] = rank3;
        rewardsRateByOceanRank[4] = rank4;
        rewardsRateByOceanRank[5] = rank5;

        emit RewardsRateByOceanRankChanged(rank1, rank2, rank3, rank4, rank5);
    }

    function getCurrentEpochId() public view returns(uint256) {
        return ((block.timestamp - genesisTimestamp) / EPOCH_DURATION_IN_SECONDS) + 1;
    }

    function canCommitInEpoch(uint256 epochId) public view returns (bool) {
        return epochId == getCurrentEpochId();
    }

    function canRevealInEpoch(uint256 epochId) public view returns (bool) {
        return epochId == getCurrentEpochId() - 1;
    }

    function commit(uint256 epochId, uint256[] memory sharksIds, bytes32[] memory commits) public returns (uint256) {
        require(canCommitInEpoch(epochId) == true, "FiveOceans: cannot commit in this epoch");

        Epoch storage epoch = epochs[epochId];

        if (epoch.teethRewards == 0) {
            // Cache these values because they might change in later epochs
            epoch.teethRewards = teethRewardsPerEpoch;
            for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
                epoch.rewardsRateByOceanRank[oceanId] = rewardsRateByOceanRank[oceanId];
            }
        }

        for (uint8 i = 0; i < sharksIds.length; i++) {
            uint256 sharkId = sharksIds[i];
            uint256 sharkSize = sharks.size(sharkId);

            require(sharkSize != 0, "FiveOceans: shark is not active");
            require(sharks.ownerOf(sharkId) == msg.sender, "FiveOceans: not your shark");
            // require(epochs[epochId].commits[sharkId] == 0, "shark already commited");

            epoch.commits[sharkId] = commits[i];
            emit Commited(epochId, sharkId);
        }

        return epochId;
    }

    function reveal(
        uint256 epochId,
        uint256[] memory sharksIds,
        uint256[] memory oceansIds,
        bytes32 secret
    ) public returns (uint256) {
        require(canRevealInEpoch(epochId) == true, "FiveOceans: cannot reveal in this epoch");

        Epoch storage epoch = epochs[epochId];

        for (uint8 i = 0; i < sharksIds.length; i++) {
            uint256 sharkId = sharksIds[i];
            uint256 oceanId = oceansIds[i];
            uint256 sharkSize = sharks.size(sharkId);

            require(sharkSize != 0, "FiveOceans: shark is not active");
            require(sharks.ownerOf(sharkId) == msg.sender, "FiveOceans: not your shark");

            require(epoch.commits[sharkId] == convertRevealToCommit(msg.sender, oceanId, sharkId, secret), "FiveOceans: wrong secret");

            epoch.reveals[sharkId] = oceanId;

            Ocean storage ocean = epoch.oceans[oceanId];
            ocean.totalSharksSize += sharkSize;
            ocean.sharksSizeByAddress[msg.sender] += sharkSize;
            ocean.sharksIdsByAddress[msg.sender].push(sharkId);

            emit Revealed(epochId, sharkId, oceanId);
        }

        return epochId;
    }


    function convertRevealToCommit(address address_, uint256 oceanId, uint256 sharkId, bytes32 secret) pure public returns (bytes32) {
        return keccak256(abi.encodePacked(address_, oceanId, sharkId, secret));
    }

    function settleEpoch(uint256 epochId) public {
        require(epochId < getCurrentEpochId() - 1, "FiveOceans: cannot settle epoch yet");
        require(epochs[epochId].oceans[1].rank == 0, "FiveOceans: has already been settled");

        // group into buckets
        uint bucket = getTotalSharksSizeInEpoch(epochId) * bucketSizePercentage / 100;
        if (bucket == 0) {
            bucket = 1;
        }

        for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            epochs[epochId].oceans[oceanId].points = epochs[epochId].oceans[oceanId].totalSharksSize / bucket;
            epochs[epochId].oceans[oceanId].rank = 1;
        }

        for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            Ocean storage ocean = epochs[epochId].oceans[oceanId];
            for (uint comparedOceanId = oceanId + 1; comparedOceanId <= OCEANS_COUNT; comparedOceanId++) {
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

    function getRewardsForOcean(uint256 epochId, uint oceanId) public view returns (uint256) {
        uint256 oceanRank = getOceanRankInEpoch(epochId, oceanId);
        return epochs[epochId].teethRewards * rewardsRateByOceanRank[oceanRank] / 100;
    }

    function getOceanBySharkIdInEpoch(uint256 sharkId, uint256 epochId) public view returns (uint256) {
        return epochs[epochId].reveals[sharkId];
    }

    function getSharksIdsInOceanInEpochForAddress(uint256 oceanId, uint256 epochId, address address_) public view returns (uint256[] memory) {
        return epochs[epochId].oceans[oceanId].sharksIdsByAddress[address_];
    }

    function getPendingPayoutInEpochForAddress(uint256 epochId, address to) public view returns (uint256) {
        uint256 _pendingPayout = 0;

        for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            _pendingPayout += getPendingPayoutFromOceanInEpochForAddress(epochId, oceanId, to);
        }

        return _pendingPayout;
    }
    function getClaimedPayoutInEpochForAddress(uint256 epochId, address to) public view returns (uint256) {
        return epochs[epochId].payoutsByAddress[to];
    }


    function getPendingPayoutFromOceanInEpochForAddress(uint256 epochId, uint oceanId, address to) public view returns (uint256) {
        Ocean storage ocean = epochs[epochId].oceans[oceanId];

        if (ocean.payoutsByAddress[to] != 0 || ocean.totalSharksSize == 0 || ocean.sharksSizeByAddress[to] == 0) {
            return 0;
        }

        uint256 payout = (getRewardsForOcean(epochId, oceanId) * ocean.sharksSizeByAddress[to]) / ocean.totalSharksSize;

        return payout;
    }

    function processPayoutInEpochForAddress(uint256 epochId, address to) public returns (uint256) {
        Epoch storage epoch = epochs[epochId];

        require(epoch.payoutsByAddress[to] == 0, "FiveOceans: payouts have been processed");

        uint256 _totalPayout = 0;

        for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
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

    function getOceanInEpoch(uint256 epochId, uint oceanId) public view returns (uint256, uint256, uint256) {
        Ocean storage ocean = epochs[epochId].oceans[oceanId];
        return (ocean.totalSharksSize, ocean.rank, ocean.points);
    }

    function getOceanRankInEpoch(uint256 epochId, uint oceanId) public view returns (uint) {
        return epochs[epochId].oceans[oceanId].rank;
    }

    function getOceanPointsInEpoch(uint256 epochId, uint oceanId) public view returns (uint) {
        return epochs[epochId].oceans[oceanId].points;
    }


    function getTotalSharksSizeInEpoch(uint256 epochId) public view returns (uint256) {
        uint256 count = 0;

        for (uint oceanId = 1; oceanId <= OCEANS_COUNT; oceanId++) {
            count += epochs[epochId].oceans[oceanId].totalSharksSize;
        }

        return count;
    }


}
