// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

import "./IAccessManager.sol";
import "./IFeeManager.sol";
import "./DCATypes.sol";
import "./IFeeCollector.sol";
import "./IDCAStrategyManagerV2.sol";

contract DCAStrategyManagerV2 is IDCAStrategyManagerV2, Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 constant SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7;
    uint256 constant DENOMINATOR = 1000000;
    uint256 constant MAX_STRATEGY_FEE = 25000; // 2.5%  - percentage amount divided by DENOMINATOR
    address public feeCollector;
    uint256 public participateFee;
    IUniswapV2Router02 public uniswapV2Router;

    error InvalidAddress();
    error PathTooShort();
    error StrategyAlreadyRegistered();
    error MaxParticipantsInStrategy();
    error InvalidStrategyId();
    error Unauthorized();
    error MaxStrategyFeeExceeded();
    error WeeklyAmountTooLow();
    error UserNotParticipating();
    error StrategyExecutionInProgress();
    error ParticipateFeeTooLow();

    event StrategyUpdated(
        uint256 indexed id,
        address[] path,
        address accessManager,
        address feeManager,
        uint256 strategyFee,
        uint256 maxParticipants,
        uint256 minWeeklyAmount
    );
    event UserRemoved(uint256 indexed strategyId, address indexed user);
    event UserJoined(
        uint256 indexed strategyId,
        address indexed user,
        uint256 weeklyAmount
    );
    event UserResigned(uint256 indexed strategyId, address indexed user);
    event Executed(
        uint256 indexed strategyId,
        uint256 fee,
        uint256 amountIn,
        uint256 amountOut
    );
    event ExecuteDCA(
        uint256 indexed strategyId,
        uint256 indexed executionTimestamp,
        address[] path
    );

    // strategyId into StrategyDataV2 mapping
    mapping(uint256 => DCATypes.StrategyDataV2) private strategy;

    function getStrategy(
        uint256 strategyId
    ) public view returns (DCATypes.StrategyDataV2 memory) {
        return strategy[strategyId];
    }

    // user to strategyId to UserStrategyData mapping
    mapping(address => mapping(uint256 => DCATypes.UserStrategyData))
        private userStrategy;

    function getUserStrategy(
        address user,
        uint256 strategyId
    ) public view returns (DCATypes.UserStrategyData memory) {
        return userStrategy[user][strategyId];
    }

    // strategyId to participants array
    mapping(uint256 => address[]) public strategyParticipants;

    modifier strategyExists(uint256 id) {
        if (strategy[id].path.length == 0) {
            revert InvalidStrategyId();
        }
        _;
    }

    constructor(address feeCollector_, address uniswapV2Router_) {
        feeCollector = feeCollector_;
        uniswapV2Router = IUniswapV2Router02(uniswapV2Router_);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setFeeCollector(address feeCollector_) public onlyOwner {
        if (feeCollector_ == address(0)) {
            revert InvalidAddress();
        }
        feeCollector = feeCollector_;
    }

    function setParticipateFee(uint256 participateFee_) public onlyOwner {
        participateFee = participateFee_;
    }

    function registerStrategy(
        uint256 id,
        address[] memory path,
        address accessManager,
        address feeManager,
        uint256 strategyFee,
        uint256 maxParticipants,
        uint256 minWeeklyAmount
    ) public onlyOwner {
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) {
                revert InvalidAddress();
            }
        }
        if (path.length < 2) {
            revert PathTooShort();
        }
        if (accessManager == address(0)) {
            revert InvalidAddress();
        }
        if (feeManager == address(0)) {
            revert InvalidAddress();
        }
        if (strategy[id].path.length != 0) {
            revert StrategyAlreadyRegistered();
        }
        if (strategyFee > MAX_STRATEGY_FEE) {
            revert MaxStrategyFeeExceeded();
        }
        strategy[id] = DCATypes.StrategyDataV2({
            path: path,
            accessManager: accessManager,
            feeManager: feeManager,
            totalCollectedFromAsset: 0,
            totalReceivedToAsset: 0,
            strategyFee: strategyFee,
            maxParticipants: maxParticipants,
            minWeeklyAmount: minWeeklyAmount,
            lastExecuted: 0,
            executionData: DCATypes.StrategyExecutionData({
                isExecuting: false,
                currentPhase: DCATypes.ExecutionPhase.FINISH,
                lastLoopIndex: 0,
                totalCollectedToExchange: 0,
                totalCollectedFee: 0,
                received: 0
            })
        });

        emit StrategyUpdated(
            id,
            path,
            accessManager,
            feeManager,
            strategyFee,
            maxParticipants,
            minWeeklyAmount
        );
    }

    function updateStrategy(
        uint256 id,
        uint256 strategyFee,
        uint256 maxParticipants,
        uint256 minWeeklyAmount,
        address accessManager,
        address feeManager
    ) public onlyOwner strategyExists(id) {
        if (strategyFee > MAX_STRATEGY_FEE) {
            revert MaxStrategyFeeExceeded();
        }
        if (accessManager == address(0)) {
            revert InvalidAddress();
        }

        if (feeManager == address(0)) {
            revert InvalidAddress();
        }
        DCATypes.StrategyDataV2 storage strategyDataV2 = strategy[id];
        strategyDataV2.strategyFee = strategyFee;
        strategyDataV2.maxParticipants = maxParticipants;
        strategyDataV2.minWeeklyAmount = minWeeklyAmount;
        strategyDataV2.accessManager = accessManager;
        strategyDataV2.feeManager = feeManager;

        emit StrategyUpdated(
            id,
            strategyDataV2.path,
            accessManager,
            feeManager,
            strategyFee,
            maxParticipants,
            minWeeklyAmount
        );
    }

    function getStrategiesInfo(
        uint256[] memory strategiesIds,
        address user
    ) external view returns (DCATypes.StrategyInfoResponseV2[] memory) {
        uint256 length = strategiesIds.length;
        DCATypes.StrategyInfoResponseV2[]
            memory response = new DCATypes.StrategyInfoResponseV2[](length);

        for (uint256 i = 0; i < length; i++) {
            response[i] = DCATypes.StrategyInfoResponseV2({
                path: strategy[strategiesIds[i]].path,
                accessManager: strategy[strategiesIds[i]].accessManager,
                feeManager: strategy[strategiesIds[i]].feeManager,
                totalCollectedFromAsset: strategy[strategiesIds[i]]
                    .totalCollectedFromAsset,
                totalReceivedToAsset: strategy[strategiesIds[i]]
                    .totalReceivedToAsset,
                strategyFee: strategy[strategiesIds[i]].strategyFee,
                maxParticipants: strategy[strategiesIds[i]].maxParticipants,
                minWeeklyAmount: strategy[strategiesIds[i]].minWeeklyAmount,
                lastExecuted: strategy[strategiesIds[i]].lastExecuted,
                isExecuting: strategy[strategiesIds[i]]
                    .executionData
                    .isExecuting,
                participantsAmount: strategyParticipants[strategiesIds[i]]
                    .length,
                userStrategyData: userStrategy[user][strategiesIds[i]]
            });
        }

        return response;
    }

    function participate(
        uint256 id,
        uint256 weeklyAmount
    ) public payable strategyExists(id) {
        DCATypes.UserStrategyData storage userStrategyData = userStrategy[
            msg.sender
        ][id];

        if (!userStrategyData.participating && msg.value != participateFee) {
            revert ParticipateFeeTooLow();
        }

        IAccessManager(strategy[id].accessManager).participate(
            id,
            msg.sender,
            weeklyAmount
        );

        if (!userStrategyData.participating) {
            strategyParticipants[id].push(msg.sender);
            userStrategyData.participantsIndex =
                strategyParticipants[id].length -
                1;
            userStrategyData.participating = true;
        }
        userStrategyData.start = block.timestamp;
        userStrategyData.totalCollectedFromAssetSinceStart = 0;
        userStrategyData.weeklyAmount = weeklyAmount;
        userStrategyData.lastCollectedFromAssetAmount = 0;
        if (msg.value > 0) {
            IFeeCollector(feeCollector).receiveNative{value: msg.value}();
        }
        emit UserJoined(id, msg.sender, weeklyAmount);
    }

    function _removeFromStrategy(
        uint256 id,
        address user
    ) internal strategyExists(id) {
        DCATypes.UserStrategyData storage userStrategyData = userStrategy[user][
            id
        ];
        if (!userStrategyData.participating) {
            revert UserNotParticipating();
        }
        userStrategyData.participating = false;
        userStrategyData.weeklyAmount = 0;
        // remove from strategy participants

        uint256 lastParticipantIndex = strategyParticipants[id].length - 1;
        address lastParticipant = strategyParticipants[id][
            lastParticipantIndex
        ];
        strategyParticipants[id][
            userStrategyData.participantsIndex
        ] = lastParticipant;
        userStrategy[lastParticipant][id].participantsIndex = userStrategyData
            .participantsIndex;
        strategyParticipants[id].pop();
    }

    function resign(uint256 id) public {
        DCATypes.StrategyDataV2 memory strategyDataV2 = strategy[id];
        if (strategyDataV2.executionData.isExecuting) {
            revert StrategyExecutionInProgress();
        }
        _removeFromStrategy(id, msg.sender);

        emit UserResigned(id, msg.sender);
    }

    function removeFromStrategy(uint256 id, address user) public onlyOwner {
        DCATypes.StrategyDataV2 memory strategyDataV2 = strategy[id];
        if (strategyDataV2.executionData.isExecuting) {
            revert StrategyExecutionInProgress();
        }
        _removeFromStrategy(id, msg.sender);

        emit UserRemoved(id, user);
    }

    function getStrategyParticipantsLength(
        uint256 strategyId
    ) public view returns (uint256) {
        return strategyParticipants[strategyId].length;
    }

    function _collectFromAsset(
        uint256 strategyId,
        uint32 maxLoopIterations
    ) internal returns (uint32) {
        DCATypes.StrategyDataV2 storage strategyDataV2 = strategy[strategyId];
        int256 participantsIndex = strategyDataV2.executionData.lastLoopIndex;
        uint256 totalCollectedToExchange = 0;
        uint256 totalCollectedFee = 0;
        while (participantsIndex >= 0 && maxLoopIterations > 0) {
            maxLoopIterations--;

            address participant = strategyParticipants[strategyId][
                uint256(participantsIndex)
            ];
            DCATypes.UserStrategyData storage userStrategyData = userStrategy[
                participant
            ][strategyId];
            uint256 toCollect = (((strategyDataV2.lastExecuted -
                userStrategyData.start) * userStrategyData.weeklyAmount) /
                SECONDS_IN_A_WEEK) -
                userStrategyData.totalCollectedFromAssetSinceStart;
            try
                IERC20(strategyDataV2.path[0]).transferFrom(
                    participant,
                    address(this),
                    toCollect
                )
            {
                userStrategyData.totalCollectedFromAssetSinceStart += toCollect;
                userStrategyData.totalCollectedFromAsset += toCollect;

                uint256 fee = IFeeManager(strategyDataV2.feeManager)
                    .calculateFee(strategyId, msg.sender, toCollect);
                if ((fee * DENOMINATOR) / toCollect > MAX_STRATEGY_FEE) {
                    revert MaxStrategyFeeExceeded();
                }

                totalCollectedFee += fee;
                totalCollectedToExchange += toCollect - fee;

                userStrategyData.lastCollectedFromAssetAmount = toCollect - fee;
            } catch {
                // remove strategy participant
                _removeFromStrategy(strategyId, participant);
                emit UserRemoved(strategyId, participant);
            }

            participantsIndex--;
        }

        if (participantsIndex < 0) {
            strategyDataV2.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .EXCHANGE;
            participantsIndex = 0;
        }
        strategyDataV2.executionData.lastLoopIndex = participantsIndex;
        strategyDataV2
            .executionData
            .totalCollectedToExchange += totalCollectedToExchange;
        strategyDataV2.executionData.totalCollectedFee += totalCollectedFee;
        return maxLoopIterations;
    }

    function _distributeTargetAsset(
        uint256 strategyId,
        uint32 maxLoopIterations
    ) internal {
        DCATypes.StrategyDataV2 storage strategyDataV2 = strategy[strategyId];
        int256 participantsIndex = strategyDataV2.executionData.lastLoopIndex;
        if (strategyDataV2.executionData.received > 0) {
            while (
                uint256(participantsIndex) <
                strategyParticipants[strategyId].length &&
                maxLoopIterations > 0
            ) {
                maxLoopIterations--;

                address participant = strategyParticipants[strategyId][
                    uint256(participantsIndex)
                ];
                DCATypes.UserStrategyData
                    storage userStrategyData = userStrategy[participant][
                        strategyId
                    ];

                uint256 toSend = (userStrategyData
                    .lastCollectedFromAssetAmount *
                    strategyDataV2.executionData.received) /
                    strategyDataV2.executionData.totalCollectedToExchange;
                userStrategyData.totalReceivedToAsset += toSend;
                if (toSend > 0) {
                    IERC20(strategyDataV2.path[strategyDataV2.path.length - 1])
                        .transfer(participant, toSend);
                }

                participantsIndex++;
            }
            if (
                uint256(participantsIndex) ==
                strategyParticipants[strategyId].length
            ) {
                strategyDataV2.executionData.currentPhase = DCATypes
                    .ExecutionPhase
                    .FINISH;
            }

            strategyDataV2.executionData.lastLoopIndex = participantsIndex;
        } else {
            strategyDataV2.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .FINISH;
        }
    }

    function executeDCA(
        uint256 strategyId,
        uint256 beliefPrice,
        uint32 maxLoopIterations
    ) public onlyRole(OPERATOR_ROLE) {
        DCATypes.StrategyDataV2 storage strategyDataV2 = strategy[strategyId];
        if (!strategyDataV2.executionData.isExecuting) {
            strategyDataV2.lastExecuted = block.timestamp;
            strategyDataV2.executionData = DCATypes.StrategyExecutionData({
                isExecuting: true,
                currentPhase: DCATypes.ExecutionPhase.COLLECT,
                lastLoopIndex: int256(strategyParticipants[strategyId].length) -
                    1,
                totalCollectedToExchange: 0,
                totalCollectedFee: 0,
                received: 0
            });
        }
        emit ExecuteDCA(
            strategyId,
            strategyDataV2.lastExecuted,
            strategyDataV2.path
        );

        // 1. Collect "FromAsset" from all strategy participants based on their weeklyAmount
        if (
            strategyDataV2.executionData.currentPhase ==
            DCATypes.ExecutionPhase.COLLECT
        ) {
            maxLoopIterations = _collectFromAsset(
                strategyId,
                maxLoopIterations
            );
        }
        if (
            strategyDataV2.executionData.currentPhase ==
            DCATypes.ExecutionPhase.EXCHANGE
        ) {
            if (strategyDataV2.executionData.totalCollectedFee > 0) {
                IERC20(strategyDataV2.path[0]).approve(
                    feeCollector,
                    strategyDataV2.executionData.totalCollectedFee
                );
                IFeeCollector(feeCollector).receiveToken(
                    strategyDataV2.path[0],
                    strategyDataV2.executionData.totalCollectedFee
                );
            }
            uint256 received = 0;
            if (strategyDataV2.executionData.totalCollectedToExchange > 0) {
                IERC20(strategyDataV2.path[0]).approve(
                    address(uniswapV2Router),
                    strategyDataV2.executionData.totalCollectedToExchange
                );
                uint256 amountIn = strategyDataV2
                    .executionData
                    .totalCollectedToExchange;
                uint256 amountOutMin = (strategyDataV2
                    .executionData
                    .totalCollectedToExchange * beliefPrice) / DENOMINATOR;
                uint256[] memory amounts = uniswapV2Router
                    .swapExactTokensForTokens(
                        amountIn,
                        amountOutMin,
                        strategyDataV2.path,
                        address(this),
                        block.timestamp
                    );
                received = amounts[amounts.length - 1];
                uint256 toAssetBalance = IERC20(
                    strategyDataV2.path[strategyDataV2.path.length - 1]
                ).balanceOf(address(this));
                if (toAssetBalance < received) {
                    received = toAssetBalance;
                }
            }

            strategyDataV2.totalCollectedFromAsset +=
                strategyDataV2.executionData.totalCollectedToExchange +
                strategyDataV2.executionData.totalCollectedFee;
            strategyDataV2.totalReceivedToAsset += received;
            strategyDataV2.executionData.received = received;
            strategyDataV2.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .DISTRIBUTE;
        }
        if (
            strategyDataV2.executionData.currentPhase ==
            DCATypes.ExecutionPhase.DISTRIBUTE
        ) {
            _distributeTargetAsset(strategyId, maxLoopIterations);
        }
        if (
            strategyDataV2.executionData.currentPhase ==
            DCATypes.ExecutionPhase.FINISH
        ) {
            strategyDataV2.executionData.isExecuting = false;
            emit Executed(
                strategyId,
                strategyDataV2.executionData.totalCollectedFee,
                strategyDataV2.executionData.totalCollectedToExchange,
                strategyDataV2.executionData.received
            );
        }
    }
}

