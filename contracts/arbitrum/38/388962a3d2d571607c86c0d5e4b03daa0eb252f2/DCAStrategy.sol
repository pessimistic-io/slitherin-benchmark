// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";

import "./console.sol";

contract DCAStrategy is Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 constant SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7;

    uint256 public maxPoolFee; // percentage amount divided by 1000000
    address public feeCollector;
    ISwapRouter public uniswapV3Router; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    error PoolAlreadyRegistered();
    error MaxParticipantsInPool();
    error InvalidPool();
    error MaxPoolFeeExceeded();
    error WeeklyInvestmentTooLow();
    error UserNotParticipating();

    event PoolUpdated(
        uint256 indexed id,
        address indexed investingAsset,
        address indexed targetAsset,
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

    struct PoolData {
        address investingAsset;
        address targetAsset;
        uint256 investedAmount;
        uint256 accumulatedAmount;
        uint256 poolFee; // percentage amount divided by 1000000
        uint24 uniswapFeeTier; // 3000 for 0.3% https://docs.uniswap.org/protocol/concepts/V3-overview/fees#pool-fees-tiers
        uint256 maxParticipants;
        uint256 minWeeklyInvestment;
        uint256 lastExecuted;
    }

    struct UserPoolData {
        uint256 investedAmount; // how much investingAsset already collected by this pool by this user in total
        uint256 receivedAmount; // how much targetAsset user has already received to his wallet
        uint256 investedAmountSinceStart; // how many investingAsset already collected by this pool since start timestamp
        uint256 start; // from when calculate toInvest amount
        uint256 weeklyInvestment; // how much targetAsset are you willing to invest within a week (7 days)
        bool participating; // is currently participating
        uint256 participantsIndex; // index in poolParticipants array
    }

    // poolId into PoolData mapping
    mapping(uint256 => PoolData) public pool;

    // user to poolId to UserPoolData mapping
    mapping(address => mapping(uint256 => UserPoolData)) public userPool;

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

    function registerPool(
        uint256 id,
        address investingAsset,
        address targetAsset,
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
        pool[id] = PoolData({
            investingAsset: investingAsset,
            targetAsset: targetAsset,
            investedAmount: 0,
            accumulatedAmount: 0,
            poolFee: poolFee,
            uniswapFeeTier: uniswapFeeTier,
            maxParticipants: maxParticipants,
            minWeeklyInvestment: minWeeklyInvestment,
            lastExecuted: 0
        });

        emit PoolUpdated(
            id,
            investingAsset,
            targetAsset,
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
        uint256 minWeeklyInvestment
    ) public onlyOwner {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }
        if (poolFee > maxPoolFee) {
            revert MaxPoolFeeExceeded();
        }
        PoolData storage poolData = pool[id];
        poolData.poolFee = poolFee;
        poolData.uniswapFeeTier = uniswapFeeTier;
        poolData.maxParticipants = maxParticipants;
        poolData.minWeeklyInvestment = minWeeklyInvestment;

        emit PoolUpdated(
            id,
            poolData.investingAsset,
            poolData.targetAsset,
            poolFee,
            uniswapFeeTier,
            maxParticipants,
            minWeeklyInvestment
        );
    }

    function participate(uint256 id, uint256 weeklyInvestment) public {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }

        UserPoolData storage userPoolData = userPool[msg.sender][id];
        if (!userPoolData.participating) {
            if (poolParticipants[id].length >= pool[id].maxParticipants) {
                revert MaxParticipantsInPool();
            }

            poolParticipants[id].push(msg.sender);
            userPoolData.participantsIndex = poolParticipants[id].length - 1;
            userPoolData.participating = true;
        }
        if (pool[id].minWeeklyInvestment > weeklyInvestment) {
            revert WeeklyInvestmentTooLow();
        }
        userPoolData.start = block.timestamp;
        userPoolData.investedAmountSinceStart = 0;
        userPoolData.weeklyInvestment = weeklyInvestment;

        emit UserParticipate(id, msg.sender, weeklyInvestment);
    }

    function resign(uint256 id) public {
        if (pool[id].targetAsset == address(0)) {
            revert InvalidPool();
        }
        UserPoolData storage userPoolData = userPool[msg.sender][id];
        if (!userPoolData.participating) {
            revert UserNotParticipating();
        }
        userPoolData.participating = false;

        // remove from pool participants

        uint256 lastParticipantIndex = poolParticipants[id].length - 1;
        address lastParticipant = poolParticipants[id][lastParticipantIndex];
        poolParticipants[id][userPoolData.participantsIndex] = lastParticipant;
        userPool[lastParticipant][id].participantsIndex = userPoolData
            .participantsIndex;
        poolParticipants[id].pop();

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
        uint256 totalCollectedAmount = 0;
        for (
            int256 i = int256(poolParticipants[poolId].length) - 1;
            i >= 0;
            i--
        ) {
            address participant = poolParticipants[poolId][uint256(i)];
            UserPoolData memory userPoolData = userPool[participant][poolId];
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
                totalCollectedAmount += toInvest;
            }
        }
        return totalCollectedAmount;
    }

    function getPoolParticipantsLength(uint256 poolId)
        public
        view
        returns (uint256)
    {
        return poolParticipants[poolId].length;
    }

    function executeDCA(uint256 poolId, uint256 beliefPrice)
        public
        onlyRole(OPERATOR_ROLE)
    {
        PoolData storage poolData = pool[poolId];
        poolData.lastExecuted = block.timestamp;


        // 1. Collect investingAsset from all pool participants based on their weeklyInvestment
        uint256[] memory collectedAmounts = new uint256[](
            poolParticipants[poolId].length
        );
        uint256 totalCollectedAmount = 0;
        for (
            int256 i = int256(poolParticipants[poolId].length) - 1;
            i >= 0;
            i--
        ) {
            address participant = poolParticipants[poolId][uint256(i)];
            UserPoolData storage userPoolData = userPool[participant][poolId];
            uint256 toInvest = (((block.timestamp - userPoolData.start) *
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
                collectedAmounts[uint256(i)] = toInvest;
                totalCollectedAmount += toInvest;
            } catch {
                // remove pool participant and correct collectedAmounts

                uint256 lastParticipantIndex = poolParticipants[poolId].length -
                    1;
                address lastParticipant = poolParticipants[poolId][
                    lastParticipantIndex
                ];
                address userRemoved = poolParticipants[poolId][uint256(i)];
                poolParticipants[poolId][uint256(i)] = lastParticipant;
                userPool[lastParticipant][poolId].participantsIndex = uint256(
                    i
                );
                collectedAmounts[uint256(i)] = collectedAmounts[
                    lastParticipantIndex
                ];
                collectedAmounts[lastParticipantIndex] = 0;
                poolParticipants[poolId].pop();

                emit PoolParticipantRemoved(poolId, userRemoved);
            }
        }

        // 2. Substract poolFee divided by 1000000 and send to feeCollector
        uint256 fee = (totalCollectedAmount * poolData.poolFee) / 1000000;
        uint256 toExchange = totalCollectedAmount - fee;

        IERC20(poolData.investingAsset).transfer(feeCollector, fee);

        // 3. Exchange investingAsset to pool.targetAsset on Router

        IERC20(poolData.investingAsset).approve(address(uniswapV3Router), toExchange);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: poolData.investingAsset,
                tokenOut: poolData.targetAsset,
                fee: poolData.uniswapFeeTier, 
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: toExchange,
                amountOutMinimum: (toExchange * beliefPrice) / 1000000,
                sqrtPriceLimitX96: 0
            });
        uint256 received = uniswapV3Router.exactInputSingle(params);

        poolData.investedAmount += toExchange;
        poolData.accumulatedAmount += received;

        // 4. Distribute targetAsset proportionaly to collected amounts

        for (uint256 i = 0; i < poolParticipants[poolId].length; i++) {
            address participant = poolParticipants[poolId][i];
            UserPoolData storage userPoolData = userPool[participant][poolId];

            uint256 result = (collectedAmounts[i] * received) /
                totalCollectedAmount;
            userPoolData.receivedAmount += result;
            IERC20(poolData.targetAsset).transfer(participant, result);
        }

        emit Executed(poolId, fee, toExchange, received);
    }
}

