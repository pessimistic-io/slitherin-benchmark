// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ERC20.sol";
import {Initializable} from "./Initializable.sol";
import "./IController.sol";
import "./Constants.sol";
import "./DeployStrategyTokenLogic.sol";

contract BaseStrategy is Initializable {
    struct HedgeStatus {
        uint256 lastHedgeTimestamp;
        uint256 lastHedgePrice;
        uint256 hedgeInterval;
        uint256 hedgeSqrtPriceThreshold;
    }

    struct Strategy {
        uint256 id;
        uint64 pairGroupId;
        uint64 pairId;
        uint256 vaultId;
        address marginToken;
        uint256 marginRoundedScaler;
        address strategyToken;
        HedgeStatus hedgeStatus;
    }

    struct MinPerValueLimit {
        uint256 lower;
        uint256 upper;
    }

    IController internal controller;

    mapping(uint256 => Strategy) public strategies;

    uint256 public strategyCount;

    MinPerValueLimit internal minPerValueLimit;

    address public operator;

    event OperatorUpdated(address operator);
    event StrategyAdded(uint256 strategyId, uint256 pairId);

    modifier onlyOperator() {
        require(operator == msg.sender, "BaseStrategy: caller is not operator");
        _;
    }

    constructor() {}

    function initialize(address _controller, MinPerValueLimit memory _minPerValueLimit) internal onlyInitializing {
        controller = IController(_controller);

        minPerValueLimit = _minPerValueLimit;

        operator = msg.sender;

        strategyCount = 1;
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;

        emit OperatorUpdated(_newOperator);
    }

    function addOrGetStrategy(uint256 _strategyId, uint64 _pairId) internal returns (Strategy storage strategy) {
        if (_strategyId == 0) {
            uint256 strategyId = addStrategy(_pairId);

            strategy = strategies[strategyId];
        } else {
            strategy = strategies[_strategyId];
        }
    }

    function addStrategy(uint64 _pairId) internal returns (uint256 strategyId) {
        strategyId = strategyCount;

        DataType.PairStatus memory pair = controller.getAsset(_pairId);
        DataType.PairGroup memory pairGroup = controller.getPairGroup(pair.pairGroupId);

        strategies[strategyId] = Strategy(
            strategyId,
            uint64(pairGroup.id),
            _pairId,
            0,
            pairGroup.stableTokenAddress,
            10 ** pairGroup.marginRoundedDecimal,
            DeployStrategyTokenLogic.deployStrategyToken(pairGroup.stableTokenAddress, pair.underlyingPool.token),
            HedgeStatus(
                block.timestamp,
                // square root of 7.5% scaled by 1e18
                controller.getSqrtPrice(_pairId),
                2 days,
                // square root of 7.5% scaled by 1e18
                10368220676 * 1e8
            )
        );

        emit StrategyAdded(strategyId, _pairId);

        strategyCount++;
    }

    function validateStrategyId(uint256 _strategyId) internal view {
        require(0 < _strategyId && _strategyId < strategyCount, "STID");
    }
}

