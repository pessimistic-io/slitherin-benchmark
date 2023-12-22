// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";

import "./console.sol";
import "./IAccessManager.sol";
import "./DCATypes.sol";
import "./IFeeCollector.sol";

contract DCAStrategy is Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 constant SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7;

    uint256 public maxPoolFee; // percentage amount divided by 1000000
    address public feeCollector;
    uint256 public participateFee;
    ISwapRouter public uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    error PoolAlreadyRegistered();
    error MaxParticipantsInPool();
    error InvalidPool();
    error Unauthorized();
    error MaxPoolFeeExceeded();
    error WeeklyInvestmentTooLow();
    error UserNotParticipating();
    error StrategyExecutionInProgress();
    error ParticipateFeeTooLow();

    event PoolUpdated(
        uint256 indexed id,
        address indexed investingAsset,
        address indexed targetAsset,
        address accessManager,
        uint256 poolFee,
        uint24 uniswapFeeTier,
        uint256 maxParticipants,
        uint256 minWeeklyInvestment
    );
    event PoolParticipantRemoved(
        uint256 indexed id,
        address indexed userRemoved
    );
    event UserParticipate(
        uint256 indexed id,
        address indexed user,
        uint256 weeklyInvestment
    );
    event UserResigned(uint256 indexed id, address indexed user);
    event Executed(
        uint256 indexed id,
        uint256 fee,
        uint256 amountIn,
        uint256 amountOut
    );

    // poolId into PoolData mapping
    mapping(uint256 => DCATypes.PoolData) public pool;

    function getPool(uint256 poolId)
        public
        view
        returns (DCATypes.PoolData memory)
    {
        return pool[poolId];
    }

    // user to poolId to UserPoolData mapping
    mapping(address => mapping(uint256 => DCATypes.UserPoolData))
        public userPool;

    function getUserPool(address user, uint256 poolId)
        public
        view
        returns (DCATypes.UserPoolData memory)
    {
        return userPool[user][poolId];
    }

    // poolId to participants array
    mapping(uint256 => address[]) public poolParticipants;

    constructor(
        uint256 maxPoolFee_,
        address feeCollector_,
        address uniswapV3Router_
    ) {
        maxPoolFee = maxPoolFee_;
        feeCollector = feeCollector_;
        uniswapV3Router = ISwapRouter(uniswapV3Router_);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setFeeCollector(address feeCollector_) public onlyOwner {
        feeCollector = feeCollector_;
    }

    function setParticipateFee(uint256 participateFee_) public onlyOwner {
        participateFee = participateFee_;
    }

    function registerPool(
        uint256 id,
        address investingAsset,
        address targetAsset,
        address accessManager,
        uint256 poolFee,
        uint24 uniswapFeeTier,
        uint256 maxParticipants,
        uint256 minWeeklyInvestment
    ) public onlyOwner {
        if (pool[id].targetAsset != address(0)) {
            revert PoolAlreadyRegistered();
        }
        if (poolFee > maxPoolFee) {
            revert MaxPoolFeeExceeded();
        }
        pool[id] = DCATypes.PoolData({
            investingAsset: investingAsset,
            targetAsset: targetAsset,
            accessManager: accessManager,
            investedAmount: 0,
            accumulatedAmount: 0,
            poolFee: poolFee,
            uniswapFeeTier: uniswapFeeTier,
            maxParticipants: maxParticipants,
            minWeeklyInvestment: minWeeklyInvestment,
            lastExecuted: 0,
            executionData: DCATypes.PoolExecutionData({
                isExecuting: false,
                currentPhase: DCATypes.ExecutionPhase.FINISH,
                lastLoopIndex: 0,
                totalCollectedToExchange: 0,
                totalCollectedFee: 0,
                received: 0
            })
        });

        emit PoolUpdated(
            id,
            investingAsset,
            targetAsset,
            accessManager,
            poolFee,
            uniswapFeeTier,
            maxParticipants,
            minWeeklyInvestment
        );
    }

    function updatePool(
        uint256 id,
        uint256 poolFee,
        uint24 uniswapFeeTier,
        uint256 maxParticipants,
        uint256 minWeeklyInvestment,
        address accessManager
    ) public onlyOwner {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }
        if (poolFee > maxPoolFee) {
            revert MaxPoolFeeExceeded();
        }
        DCATypes.PoolData storage poolData = pool[id];
        poolData.poolFee = poolFee;
        poolData.uniswapFeeTier = uniswapFeeTier;
        poolData.maxParticipants = maxParticipants;
        poolData.minWeeklyInvestment = minWeeklyInvestment;
        poolData.accessManager = accessManager;

        emit PoolUpdated(
            id,
            poolData.investingAsset,
            poolData.targetAsset,
            accessManager,
            poolFee,
            uniswapFeeTier,
            maxParticipants,
            minWeeklyInvestment
        );
    }

    function getPoolsInfo(uint256[] memory poolIds, address user)
        external
        view
        returns (DCATypes.GetPoolsInfoResponse[] memory)
    {
        uint256 length = poolIds.length;
        DCATypes.GetPoolsInfoResponse[]
            memory response = new DCATypes.GetPoolsInfoResponse[](length);

        for (uint256 i = 0; i < length; i++) {
            DCATypes.GetPoolsInfoResponse memory item = DCATypes
                .GetPoolsInfoResponse({
                    investingAsset: pool[poolIds[i]].investingAsset,
                    targetAsset: pool[poolIds[i]].targetAsset,
                    investedAmount: pool[poolIds[i]].investedAmount,
                    accumulatedAmount: pool[poolIds[i]].accumulatedAmount,
                    poolFee: pool[poolIds[i]].poolFee,
                    uniswapFeeTier: pool[poolIds[i]].uniswapFeeTier,
                    maxParticipants: pool[poolIds[i]].maxParticipants,
                    minWeeklyInvestment: pool[poolIds[i]].minWeeklyInvestment,
                    lastExecuted: pool[poolIds[i]].lastExecuted,
                    isExecuting: pool[poolIds[i]].executionData.isExecuting,
                    participantsAmount: poolParticipants[poolIds[i]].length,
                    userPoolData: userPool[user][poolIds[i]]
                });

            response[i] = item;
        }

        return response;
    }

    function participate(uint256 id, uint256 weeklyInvestment) public payable {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }

        if (msg.value < participateFee) {
            revert ParticipateFeeTooLow();
        }

        IAccessManager(pool[id].accessManager).participate(
            id,
            msg.sender,
            weeklyInvestment
        );

        DCATypes.UserPoolData storage userPoolData = userPool[msg.sender][id];
        if (!userPoolData.participating) {
            poolParticipants[id].push(msg.sender);
            userPoolData.participantsIndex = poolParticipants[id].length - 1;
            userPoolData.participating = true;
        }
        userPoolData.start = block.timestamp;
        userPoolData.investedAmountSinceStart = 0;
        userPoolData.weeklyInvestment = weeklyInvestment;
        userPoolData.lastExchangeAmount = 0;
        IFeeCollector(feeCollector).receiveNative{value: msg.value}();
        emit UserParticipate(id, msg.sender, weeklyInvestment);
    }

    function _removeFromPool(uint256 id, address user) internal {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }

        DCATypes.UserPoolData storage userPoolData = userPool[user][id];
        if (!userPoolData.participating) {
            revert UserNotParticipating();
        }
        userPoolData.participating = false;
        userPoolData.weeklyInvestment = 0;
        // remove from pool participants

        uint256 lastParticipantIndex = poolParticipants[id].length - 1;
        address lastParticipant = poolParticipants[id][lastParticipantIndex];
        poolParticipants[id][userPoolData.participantsIndex] = lastParticipant;
        userPool[lastParticipant][id].participantsIndex = userPoolData
            .participantsIndex;
        poolParticipants[id].pop();
    }

    function resign(uint256 id) public {
        DCATypes.PoolData memory poolData = pool[id];
        if (poolData.executionData.isExecuting) {
            revert StrategyExecutionInProgress();
        }
        _removeFromPool(id, msg.sender);

        emit UserResigned(id, msg.sender);
    }

    function calculateInvestingAssetAmountForNextPoolExecute(uint256 poolId)
        public
        view
        returns (uint256)
    {
        if (pool[poolId].targetAsset == address(0)) {
            revert InvalidPool();
        }
        IERC20 investingAsset = IERC20(pool[poolId].investingAsset);
        uint256 totalCollectedToExchange = 0;
        for (
            int256 i = int256(poolParticipants[poolId].length) - 1;
            i >= 0;
            i--
        ) {
            address participant = poolParticipants[poolId][uint256(i)];
            DCATypes.UserPoolData memory userPoolData = userPool[participant][
                poolId
            ];
            uint256 toInvest = (((block.timestamp - userPoolData.start) *
                userPoolData.weeklyInvestment) / SECONDS_IN_A_WEEK) -
                userPoolData.investedAmountSinceStart;
            uint256 participantBalance = investingAsset.balanceOf(participant);
            uint256 participantAllowance = investingAsset.allowance(
                participant,
                address(this)
            );
            if (
                participantBalance >= toInvest &&
                participantAllowance >= toInvest
            ) {
                totalCollectedToExchange += toInvest;
            }
        }
        return totalCollectedToExchange;
    }

    function getPoolParticipantsLength(uint256 poolId)
        public
        view
        returns (uint256)
    {
        return poolParticipants[poolId].length;
    }

    function _collectInvestingAsset(uint256 poolId, uint32 maxLoopIterations)
        internal
        returns (uint32)
    {
        DCATypes.PoolData storage poolData = pool[poolId];
        int256 participantsIndex = poolData.executionData.lastLoopIndex;
        uint256 totalCollectedToExchange = 0;
        uint256 totalCollectedFee = 0;
        while (participantsIndex >= 0 && maxLoopIterations > 0) {
            maxLoopIterations--;

            address participant = poolParticipants[poolId][
                uint256(participantsIndex)
            ];
            DCATypes.UserPoolData storage userPoolData = userPool[participant][
                poolId
            ];
            uint256 toInvest = (((poolData.lastExecuted - userPoolData.start) *
                userPoolData.weeklyInvestment) / SECONDS_IN_A_WEEK) -
                userPoolData.investedAmountSinceStart;
            try
                IERC20(poolData.investingAsset).transferFrom(
                    participant,
                    address(this),
                    toInvest
                )
            {
                userPoolData.investedAmountSinceStart += toInvest;
                userPoolData.investedAmount += toInvest;

                // TODO: query feeManager about fee size;
                uint256 fee = (toInvest * poolData.poolFee) / 1000000;
                totalCollectedFee += fee;
                totalCollectedToExchange += toInvest - fee;

                userPoolData.lastExchangeAmount = toInvest - fee;
            } catch {
                // remove pool participant and correct collectedAmounts
                _removeFromPool(poolId, participant);
                emit PoolParticipantRemoved(poolId, participant);
            }

            participantsIndex--;
        }

        if (participantsIndex < 0) {
            poolData.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .EXCHANGE;
            participantsIndex = 0;
        }
        poolData.executionData.lastLoopIndex = participantsIndex;
        poolData
            .executionData
            .totalCollectedToExchange += totalCollectedToExchange;
        poolData.executionData.totalCollectedFee += totalCollectedFee;
        return maxLoopIterations;
    }

    function _distributeTargetAsset(uint256 poolId, uint32 maxLoopIterations)
        internal
    {
        DCATypes.PoolData storage poolData = pool[poolId];
        int256 participantsIndex = poolData.executionData.lastLoopIndex;
        if (poolData.executionData.received > 0) {
            while (
                uint256(participantsIndex) < poolParticipants[poolId].length &&
                maxLoopIterations > 0
            ) {
                maxLoopIterations--;

                address participant = poolParticipants[poolId][
                    uint256(participantsIndex)
                ];
                DCATypes.UserPoolData storage userPoolData = userPool[
                    participant
                ][poolId];

                uint256 toSend = (userPoolData.lastExchangeAmount *
                    poolData.executionData.received) /
                    poolData.executionData.totalCollectedToExchange;
                userPoolData.receivedAmount += toSend;
                if (toSend > 0) {
                    IERC20(poolData.targetAsset).transfer(participant, toSend);
                }

                participantsIndex++;
            }
            if (uint256(participantsIndex) == poolParticipants[poolId].length) {
                poolData.executionData.currentPhase = DCATypes
                    .ExecutionPhase
                    .FINISH;
            }

            poolData.executionData.lastLoopIndex = participantsIndex;
        } else {
            poolData.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .FINISH;
        }
    }

    function executeDCA(
        uint256 poolId,
        uint256 beliefPrice,
        uint32 maxLoopIterations
    ) public onlyRole(OPERATOR_ROLE) {
        DCATypes.PoolData storage poolData = pool[poolId];
        if (!poolData.executionData.isExecuting) {
            poolData.lastExecuted = block.timestamp;
            poolData.executionData = DCATypes.PoolExecutionData({
                isExecuting: true,
                currentPhase: DCATypes.ExecutionPhase.COLLECT,
                lastLoopIndex: int256(poolParticipants[poolId].length) - 1,
                totalCollectedToExchange: 0,
                totalCollectedFee: 0,
                received: 0
            });
        }

        // 1. Collect investingAsset from all pool participants based on their weeklyInvestment
        if (
            poolData.executionData.currentPhase ==
            DCATypes.ExecutionPhase.COLLECT
        ) {
            maxLoopIterations = _collectInvestingAsset(
                poolId,
                maxLoopIterations
            );
        }
        if (
            poolData.executionData.currentPhase ==
            DCATypes.ExecutionPhase.EXCHANGE
        ) {
            if (poolData.executionData.totalCollectedFee > 0) {
                IERC20(poolData.investingAsset).approve(
                    feeCollector,
                    poolData.executionData.totalCollectedFee
                );
                IFeeCollector(feeCollector).receiveToken(
                    poolData.investingAsset,
                    poolData.executionData.totalCollectedFee
                );
            }
            uint256 received;
            if (poolData.executionData.totalCollectedToExchange > 0) {
                IERC20(poolData.investingAsset).approve(
                    address(uniswapV3Router),
                    poolData.executionData.totalCollectedToExchange
                );
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: poolData.investingAsset,
                        tokenOut: poolData.targetAsset,
                        fee: poolData.uniswapFeeTier,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: poolData
                            .executionData
                            .totalCollectedToExchange,
                        amountOutMinimum: (poolData
                            .executionData
                            .totalCollectedToExchange * beliefPrice) / 1000000,
                        sqrtPriceLimitX96: 0
                    });
                received = uniswapV3Router.exactInputSingle(params);
            }

            poolData.investedAmount +=
                poolData.executionData.totalCollectedToExchange +
                poolData.executionData.totalCollectedFee;
            poolData.accumulatedAmount += received;
            poolData.executionData.received = received;
            poolData.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .DISTRIBUTE;
        }
        if (
            poolData.executionData.currentPhase ==
            DCATypes.ExecutionPhase.DISTRIBUTE
        ) {
            _distributeTargetAsset(poolId, maxLoopIterations);
        }
        if (
            poolData.executionData.currentPhase ==
            DCATypes.ExecutionPhase.FINISH
        ) {
            poolData.executionData.isExecuting = false;
            emit Executed(
                poolId,
                poolData.executionData.totalCollectedFee,
                poolData.executionData.totalCollectedToExchange,
                poolData.executionData.received
            );
        }
    }
}

