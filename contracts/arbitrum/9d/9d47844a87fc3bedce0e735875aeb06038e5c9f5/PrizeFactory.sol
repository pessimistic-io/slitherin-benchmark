// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./Counters.sol";
import "./IPrizeNFT.sol";
import "./PrizePool.sol";
import "./PrizeNFT.sol";

contract PrizeFactory is Ownable {
    using Counters for Counters.Counter;

    enum PoolType {
        ChosenOne,
        TenPercent,
        FiftyPercent
    }

    //round => PoolType => PrizePool
    mapping(uint256 => mapping(PoolType => address)) public allPrizePools;

    Counters.Counter private _roundCounter;

    uint256 public lastRound;

    event CreateNewRound(
        uint256 indexed round,
        uint256 _singleBet,
        uint256 _betDuration,
        address _treasury,
        uint64 _subscriptionId,
        address _coordinator,
        bytes32 _keyHash,
        uint256 _startTime
    );

    event CreatePrizePool(
        uint256 indexed roundId,
        uint256 indexed poolId,
        address prizeNFT,
        address prizePool
    );

    function createNewRound(
        uint256 _singleBet,
        uint256 _betDuration,
        address _treasury,
        uint64 _subscriptionId,
        address _coordinator,
        bytes32 _keyHash,
        uint256 _startTime,
        bool pool1Create,
        bool pool2Create,
        bool pool3Create
    ) public onlyOwner {
        _roundCounter.increment();
        lastRound = _roundCounter.current();

        require(pool1Create || pool2Create || pool3Create, "non create pool");
        if (pool1Create) {
            createPrizePool(
                lastRound,
                PoolType.ChosenOne,
                _singleBet,
                _betDuration,
                _treasury,
                _subscriptionId,
                _coordinator,
                _keyHash,
                _startTime
            );
        }
        if (pool2Create) {
            createPrizePool(
                lastRound,
                PoolType.TenPercent,
                _singleBet,
                _betDuration,
                _treasury,
                _subscriptionId,
                _coordinator,
                _keyHash,
                _startTime
            );
        }
        if (pool3Create) {
            createPrizePool(
                lastRound,
                PoolType.FiftyPercent,
                _singleBet,
                _betDuration,
                _treasury,
                _subscriptionId,
                _coordinator,
                _keyHash,
                _startTime
            );
        }
        emit CreateNewRound(
            lastRound,
            _singleBet,
            _betDuration,
            _treasury,
            _subscriptionId,
            _coordinator,
            _keyHash,
            _startTime
        );
    }

    function createPrizePool(
        uint256 round,
        PoolType poolType,
        uint256 _singleBet,
        uint256 _betDuration,
        address _treasury,
        uint64 _subscriptionId,
        address _coordinator,
        bytes32 _keyHash,
        uint256 startTime
    ) internal {
        //create NFT
        uint256 poolId;
        {
            if (poolType == PoolType.ChosenOne) {
                poolId = 1;
            } else if (poolType == PoolType.TenPercent) {
                poolId = 2;
            } else if (poolType == PoolType.FiftyPercent) {
                poolId = 3;
            }
        }
        PrizeNFT prizeNFT = new PrizeNFT(round, poolId);

        //create Pool
        PrizePool prizePool = new PrizePool(
            poolType,
            IPrizeNFT(prizeNFT),
            _singleBet,
            _betDuration,
            _treasury,
            _subscriptionId,
            _coordinator,
            _keyHash,
            startTime
        );

        prizeNFT.transferOwnership(address(prizePool));

        allPrizePools[round][poolType] = address(prizePool);
        emit CreatePrizePool(
            round,
            poolId,
            address(prizeNFT),
            address(prizePool)
        );
    }

    function claimAllRewards(uint256 roundId) public {
        address pool1Addr = allPrizePools[roundId][PoolType.ChosenOne];
        address pool2Addr = allPrizePools[roundId][PoolType.TenPercent];
        address pool3Addr = allPrizePools[roundId][PoolType.FiftyPercent];

        if(pool1Addr != address(0x0)) {
            PrizePool(payable(pool1Addr)).claimReward(msg.sender);
        }
        if(pool2Addr != address(0x0)) {
            PrizePool(payable(pool2Addr)).claimReward(msg.sender);
        }
        if(pool3Addr != address(0x0)) {
            PrizePool(payable(pool3Addr)).claimReward(msg.sender);
        }
    }
    
}

