// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;
pragma abicoder v2;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";

import "./IAccessManager.sol";
import "./IFeeManager.sol";
import "./DCATypes.sol";
import "./IFeeCollector.sol";
import "./IDCAStrategyManagerV3.sol";

contract DCAStrategyManagerV3ZyberSwap is
    IDCAStrategyManagerV3,
    Ownable,
    AccessControl
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 private constant ADDR_SIZE = 20;
    uint256 constant SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7;
    uint256 constant DENOMINATOR = 1000000;
    uint256 constant MAX_STRATEGY_FEE = 25000; // 2.5%  - percentage amount divided by DENOMINATOR
    address public feeCollector;
    uint256 public participateFee;
    ISwapRouter public swapV3Router;

    // user to strategyId to UserStrategyData mapping
    mapping(address => mapping(uint256 => DCATypes.UserStrategyData))
        private userStrategy;

    // strategyId to participants array
    mapping(uint256 => address[]) public strategyParticipants;

    // strategyId into StrategyDataV3 mapping
    mapping(uint256 => DCATypes.StrategyDataV3) private strategy;

    error InvalidAddress();
    error InvalidPath();
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
        bytes path,
        address fromAsset,
        address toAsset,
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
        address fromAsset,
        address toAsset,
        bytes path
    );

    function getStrategy(
        uint256 strategyId
    ) public view returns (DCATypes.StrategyDataV3 memory) {
        return strategy[strategyId];
    }

    function getUserStrategy(
        address user,
        uint256 strategyId
    ) public view returns (DCATypes.UserStrategyData memory) {
        return userStrategy[user][strategyId];
    }

    modifier strategyExists(uint256 id) {
        if (strategy[id].path.length == 0) {
            revert InvalidStrategyId();
        }
        _;
    }

    constructor(address feeCollector_, address swapV3Router_) {
        feeCollector = feeCollector_;
        swapV3Router = ISwapRouter(swapV3Router_);

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
        bytes memory path,
        address fromAsset,
        address toAsset,
        address accessManager,
        address feeManager,
        uint256 strategyFee,
        uint256 maxParticipants,
        uint256 minWeeklyAmount
    ) public onlyOwner {
        if (path.length == 0) {
            revert InvalidPath();
        }
        if (fromAsset == address(0)) {
            revert InvalidAddress();
        }
        if (toAsset == address(0)) {
            revert InvalidAddress();
        }
        if (_toAsset(path) != toAsset) {
            revert InvalidPath();
        }
        if (_fromAsset(path) != fromAsset) {
            revert InvalidPath();
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
        strategy[id] = DCATypes.StrategyDataV3({
            path: path,
            fromAsset: fromAsset,
            toAsset: toAsset,
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
            fromAsset,
            toAsset,
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
        DCATypes.StrategyDataV3 storage strategyDataV3 = strategy[id];
        strategyDataV3.strategyFee = strategyFee;
        strategyDataV3.maxParticipants = maxParticipants;
        strategyDataV3.minWeeklyAmount = minWeeklyAmount;
        strategyDataV3.accessManager = accessManager;
        strategyDataV3.feeManager = feeManager;

        emit StrategyUpdated(
            id,
            strategyDataV3.path,
            strategyDataV3.fromAsset,
            strategyDataV3.toAsset,
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
    ) external view returns (DCATypes.StrategyInfoResponseV3[] memory) {
        uint256 length = strategiesIds.length;
        DCATypes.StrategyInfoResponseV3[]
            memory response = new DCATypes.StrategyInfoResponseV3[](length);

        for (uint256 i = 0; i < length; i++) {
            response[i] = DCATypes.StrategyInfoResponseV3({
                path: strategy[strategiesIds[i]].path,
                fromAsset: strategy[strategiesIds[i]].fromAsset,
                toAsset: strategy[strategiesIds[i]].toAsset,
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
        DCATypes.StrategyDataV3 memory strategyDataV3 = strategy[id];
        if (strategyDataV3.executionData.isExecuting) {
            revert StrategyExecutionInProgress();
        }
        _removeFromStrategy(id, msg.sender);

        emit UserResigned(id, msg.sender);
    }

    function removeFromStrategy(uint256 id, address user) public onlyOwner {
        DCATypes.StrategyDataV3 memory strategyDataV3 = strategy[id];
        if (strategyDataV3.executionData.isExecuting) {
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
        DCATypes.StrategyDataV3 storage strategyDataV3 = strategy[strategyId];
        int256 participantsIndex = strategyDataV3.executionData.lastLoopIndex;
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
            uint256 toCollect = (((strategyDataV3.lastExecuted -
                userStrategyData.start) * userStrategyData.weeklyAmount) /
                SECONDS_IN_A_WEEK) -
                userStrategyData.totalCollectedFromAssetSinceStart;
            try
                IERC20(strategyDataV3.fromAsset).transferFrom(
                    participant,
                    address(this),
                    toCollect
                )
            {
                userStrategyData.totalCollectedFromAssetSinceStart += toCollect;
                userStrategyData.totalCollectedFromAsset += toCollect;

                uint256 fee = IFeeManager(strategyDataV3.feeManager)
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
            strategyDataV3.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .EXCHANGE;
            participantsIndex = 0;
        }
        strategyDataV3.executionData.lastLoopIndex = participantsIndex;
        strategyDataV3
            .executionData
            .totalCollectedToExchange += totalCollectedToExchange;
        strategyDataV3.executionData.totalCollectedFee += totalCollectedFee;
        return maxLoopIterations;
    }

    function _distributeTargetAsset(
        uint256 strategyId,
        uint32 maxLoopIterations
    ) internal {
        DCATypes.StrategyDataV3 storage strategyDataV3 = strategy[strategyId];
        int256 participantsIndex = strategyDataV3.executionData.lastLoopIndex;
        if (strategyDataV3.executionData.received > 0) {
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
                    strategyDataV3.executionData.received) /
                    strategyDataV3.executionData.totalCollectedToExchange;
                userStrategyData.totalReceivedToAsset += toSend;
                if (toSend > 0) {
                    IERC20(strategyDataV3.toAsset).transfer(
                        participant,
                        toSend
                    );
                }

                participantsIndex++;
            }
            if (
                uint256(participantsIndex) ==
                strategyParticipants[strategyId].length
            ) {
                strategyDataV3.executionData.currentPhase = DCATypes
                    .ExecutionPhase
                    .FINISH;
            }

            strategyDataV3.executionData.lastLoopIndex = participantsIndex;
        } else {
            strategyDataV3.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .FINISH;
        }
    }

    function executeDCA(
        uint256 strategyId,
        uint256 beliefPrice,
        uint32 maxLoopIterations
    ) public onlyRole(OPERATOR_ROLE) {
        DCATypes.StrategyDataV3 storage strategyDataV3 = strategy[strategyId];

        if (!strategyDataV3.executionData.isExecuting) {
            strategyDataV3.lastExecuted = block.timestamp;
            strategyDataV3.executionData = DCATypes.StrategyExecutionData({
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
            strategyDataV3.lastExecuted,
            strategyDataV3.fromAsset,
            strategyDataV3.toAsset,
            strategyDataV3.path
        );

        // 1. Collect "FromAsset" from all strategy participants based on their weeklyAmount
        if (
            strategyDataV3.executionData.currentPhase ==
            DCATypes.ExecutionPhase.COLLECT
        ) {
            maxLoopIterations = _collectFromAsset(
                strategyId,
                maxLoopIterations
            );
        }
        if (
            strategyDataV3.executionData.currentPhase ==
            DCATypes.ExecutionPhase.EXCHANGE
        ) {
            if (strategyDataV3.executionData.totalCollectedFee > 0) {
                IERC20(strategyDataV3.fromAsset).approve(
                    feeCollector,
                    strategyDataV3.executionData.totalCollectedFee
                );
                IFeeCollector(feeCollector).receiveToken(
                    strategyDataV3.fromAsset,
                    strategyDataV3.executionData.totalCollectedFee
                );
            }
            uint256 received = 0;
            if (strategyDataV3.executionData.totalCollectedToExchange > 0) {
                IERC20(strategyDataV3.fromAsset).approve(
                    address(swapV3Router),
                    strategyDataV3.executionData.totalCollectedToExchange
                );
                uint256 amountIn = strategyDataV3
                    .executionData
                    .totalCollectedToExchange;
                uint256 amountOutMin = (strategyDataV3
                    .executionData
                    .totalCollectedToExchange * beliefPrice) / DENOMINATOR;

                ISwapRouter.ExactInputParams memory params = ISwapRouter
                    .ExactInputParams({
                        path: strategyDataV3.path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amountIn,
                        amountOutMinimum: amountOutMin
                    });
                received = swapV3Router.exactInput(params);

                uint256 toAssetBalance = IERC20(strategyDataV3.toAsset)
                    .balanceOf(address(this));
                if (toAssetBalance < received) {
                    received = toAssetBalance;
                }
            }

            strategyDataV3.totalCollectedFromAsset +=
                strategyDataV3.executionData.totalCollectedToExchange +
                strategyDataV3.executionData.totalCollectedFee;
            strategyDataV3.totalReceivedToAsset += received;
            strategyDataV3.executionData.received = received;
            strategyDataV3.executionData.currentPhase = DCATypes
                .ExecutionPhase
                .DISTRIBUTE;
        }
        if (
            strategyDataV3.executionData.currentPhase ==
            DCATypes.ExecutionPhase.DISTRIBUTE
        ) {
            _distributeTargetAsset(strategyId, maxLoopIterations);
        }
        if (
            strategyDataV3.executionData.currentPhase ==
            DCATypes.ExecutionPhase.FINISH
        ) {
            strategyDataV3.executionData.isExecuting = false;
            emit Executed(
                strategyId,
                strategyDataV3.executionData.totalCollectedFee,
                strategyDataV3.executionData.totalCollectedToExchange,
                strategyDataV3.executionData.received
            );
        }
    }

    function _fromAsset(bytes memory _bytes) internal pure returns (address) {
        return _toAddress(_bytes, 0);
    }

    function _toAsset(bytes memory _bytes) internal pure returns (address) {
        return _toAddress(_bytes, _bytes.length - 20);
    }

    function _toAddress(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(
                mload(add(add(_bytes, 0x20), _start)),
                0x1000000000000000000000000
            )
        }

        return tempAddress;
    }
}

