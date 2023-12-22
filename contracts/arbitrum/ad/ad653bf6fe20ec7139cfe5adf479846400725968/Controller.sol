// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IFundManagerVault.sol";
import "./IRescaleTickBoundaryCalculator.sol";
import "./IController.sol";
import "./IControllerEvent.sol";
import "./IStrategyInfo.sol";
import "./IStrategy.sol";
import "./IStrategySetter.sol";
import "./Constants.sol";
import "./LiquidityNftHelper.sol";
import "./ParameterVerificationHelper.sol";
import "./AccessControl.sol";
import "./SafeMath.sol";

/// @dev verified, private contract
/// @dev only owner or operator/backend callable
contract Controller is AccessControl, IControllerEvent, IController {
    using SafeMath for uint256;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    mapping(address => int24) public tickSpreadUpper; // strategy => tickSpreadUpper
    mapping(address => int24) public tickSpreadLower; // strategy => tickSpreadLower
    mapping(address => int24) public tickGapUpper; // strategy => tickGapUpper
    mapping(address => int24) public tickGapLower; // strategy => tickGapLower
    mapping(address => int24) public tickBoundaryOffset; // strategy => tickBoundaryOffset
    mapping(address => int24) public rescaleTickBoundaryOffset; // strategy => rescaleTickBoundaryOffset
    mapping(address => int24) public lastRescaleTick; // strategy => lastRescaleTick

    constructor(address _executor) {
        // set deployer as EXECUTOR_ROLE roleAdmin
        _setRoleAdmin(EXECUTOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // set EXECUTOR_ROLE memebers
        _setupRole(EXECUTOR_ROLE, _executor);
    }

    /// @dev backend get function support
    function isNftWithinRange(
        address _strategyContract
    ) public view returns (bool isWithinRange) {
        uint256 liquidityNftId = IStrategyInfo(_strategyContract)
            .liquidityNftId();

        require(
            liquidityNftId != 0,
            "not allow calling when liquidityNftId is 0"
        );

        (isWithinRange, ) = LiquidityNftHelper
            .verifyCurrentPriceInLiquidityNftRange(
                liquidityNftId,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
    }

    function getEarningFlag(
        address _strategyContract
    ) public view returns (bool isEarningFlag) {
        return IStrategyInfo(_strategyContract).isEarning();
    }

    function getRescalingFlag(
        address _strategyContract
    ) public view returns (bool isRescalingFlag) {
        uint256 liquidityNftId = IStrategyInfo(_strategyContract)
            .liquidityNftId();

        if (liquidityNftId == 0) {
            return true;
        } else {
            return false;
        }
    }

    function getRemainingEarnCountDown(
        address _strategyContract
    ) public view returns (uint256 remainingEarn) {
        bool isEarningFlag = getEarningFlag(_strategyContract);
        if (isEarningFlag == false) {
            return 0;
        }

        uint256 userListLength = IStrategyInfo(_strategyContract)
            .getAllUsersInUserList()
            .length;
        uint256 earnLoopStartIndex = IStrategyInfo(_strategyContract)
            .earnLoopStartIndex();

        uint256 remainingUserNumber = userListLength.sub(earnLoopStartIndex);
        uint256 earnLoopSegmentSize = IStrategyInfo(_strategyContract)
            .earnLoopSegmentSize();

        (uint256 quotient, uint256 remainder) = calculateQuotientAndRemainder(
            remainingUserNumber,
            earnLoopSegmentSize
        );

        return remainder > 0 ? (quotient.add(1)) : quotient;
    }

    function calculateQuotientAndRemainder(
        uint256 dividend,
        uint256 divisor
    ) internal pure returns (uint256 quotient, uint256 remainder) {
        quotient = dividend.div(divisor);
        remainder = dividend.mod(divisor);
    }

    function getAllFundManagers(
        address _fundManagerVaultContract
    ) public view returns (IFundManagerVault.FundManager[4] memory) {
        return
            IFundManagerVault(_fundManagerVaultContract).getAllFundManagers();
    }

    /// @dev transactionDeadlineDuration setter
    function setTransactionDeadlineDuration(
        address _strategyContract,
        uint256 _transactionDeadlineDuration
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setTransactionDeadlineDuration(
            _transactionDeadlineDuration
        );

        emit SetTransactionDeadlineDuration(
            _strategyContract,
            msg.sender,
            _transactionDeadlineDuration
        );
    }

    /// @dev tickSpreadUpper setter
    function setTickSpreadUpper(
        address _strategyContract,
        int24 _tickSpreadUpper
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOrEqualToZero(
            _tickSpreadUpper
        );

        // update tickSpreadUpper
        tickSpreadUpper[_strategyContract] = _tickSpreadUpper;

        // emit SetTickSpreadUpper event
        emit SetTickSpreadUpper(
            _strategyContract,
            msg.sender,
            _tickSpreadUpper
        );
    }

    /// @dev tickSpreadLower setter
    function setTickSpreadLower(
        address _strategyContract,
        int24 _tickSpreadLower
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOrEqualToZero(
            _tickSpreadLower
        );

        // update tickSpreadLower
        tickSpreadLower[_strategyContract] = _tickSpreadLower;

        // emit SetTickSpreadLower event
        emit SetTickSpreadLower(
            _strategyContract,
            msg.sender,
            _tickSpreadLower
        );
    }

    /// @dev tickGapUpper setter
    function setTickGapUpper(
        address _strategyContract,
        int24 _tickGapUpper
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOne(_tickGapUpper);

        // update tickGapUpper
        tickGapUpper[_strategyContract] = _tickGapUpper;

        // emit SetTickGapUpper event
        emit SetTickGapUpper(_strategyContract, msg.sender, _tickGapUpper);
    }

    /// @dev tickGapLower setter
    function setTickGapLower(
        address _strategyContract,
        int24 _tickGapLower
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOne(_tickGapLower);

        // update tickGapLower
        tickGapLower[_strategyContract] = _tickGapLower;

        // emit SetTickGapLower event
        emit SetTickGapLower(_strategyContract, msg.sender, _tickGapLower);
    }

    /// @dev buyBackToken setter
    function setBuyBackToken(
        address _strategyContract,
        address _buyBackToken
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setBuyBackToken(_buyBackToken);

        emit SetBuyBackToken(_strategyContract, msg.sender, _buyBackToken);
    }

    /// @dev buyBackNumerator setter
    function setBuyBackNumerator(
        address _strategyContract,
        uint24 _buyBackNumerator
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setBuyBackNumerator(
            _buyBackNumerator
        );

        emit SetBuyBackNumerator(
            _strategyContract,
            msg.sender,
            _buyBackNumerator
        );
    }

    /// @dev fundManagerVault setter
    function setFundManagerVaultByIndex(
        address _strategyContract,
        uint256 _index,
        address _fundManagerVaultAddress,
        uint24 _fundManagerProfitVaultNumerator
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setFundManagerVaultByIndex(
            _index,
            _fundManagerVaultAddress,
            _fundManagerProfitVaultNumerator
        );

        emit SetFundManagerVaultByIndex(
            _strategyContract,
            msg.sender,
            _index,
            _fundManagerVaultAddress,
            _fundManagerProfitVaultNumerator
        );
    }

    /// @dev fundManager setter
    function setFundManagerByIndex(
        address _fundManagerVaultContract,
        uint256 _index,
        address _fundManagerAddress,
        uint24 _fundManagerProfitNumerator
    ) public onlyRole(EXECUTOR_ROLE) {
        IFundManagerVault(_fundManagerVaultContract).setFundManagerByIndex(
            _index,
            _fundManagerAddress,
            _fundManagerProfitNumerator
        );

        emit SetFundManagerByIndex(
            _fundManagerVaultContract,
            msg.sender,
            _index,
            _fundManagerAddress,
            _fundManagerProfitNumerator
        );
    }

    /// @dev earnLoopSegmentSize setter
    function setEarnLoopSegmentSize(
        address _strategyContract,
        uint256 _earnLoopSegmentSize
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setEarnLoopSegmentSize(
            _earnLoopSegmentSize
        );

        emit SetEarnLoopSegmentSize(
            _strategyContract,
            msg.sender,
            _earnLoopSegmentSize
        );
    }

    /// @dev tickBoundaryOffset setter
    function setTickBoundaryOffset(
        address _strategyContract,
        int24 _tickBoundaryOffset
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOrEqualToZero(
            _tickBoundaryOffset
        );

        // update tickBoundaryOffset
        tickBoundaryOffset[_strategyContract] = _tickBoundaryOffset;

        // emit SetTickBoundaryOffset event
        emit SetTickBoundaryOffset(
            _strategyContract,
            msg.sender,
            _tickBoundaryOffset
        );
    }

    /// @dev rescaleTickBoundaryOffset setter
    function setRescaleTickBoundaryOffset(
        address _strategyContract,
        int24 _rescaleTickBoundaryOffset
    ) public onlyRole(EXECUTOR_ROLE) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanOrEqualToZero(
            _rescaleTickBoundaryOffset
        );

        // update rescaleTickBoundaryOffset
        rescaleTickBoundaryOffset[
            _strategyContract
        ] = _rescaleTickBoundaryOffset;

        // emit SetRescaleTickBoundaryOffset event
        emit SetRescaleTickBoundaryOffset(
            _strategyContract,
            msg.sender,
            _rescaleTickBoundaryOffset
        );
    }

    /// @dev earn related
    function collectRewards(
        address _strategyContract
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).collectRewards();

        emit CollectRewards(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            IStrategyInfo(_strategyContract).rewardToken0Amount(),
            IStrategyInfo(_strategyContract).rewardToken1Amount(),
            IStrategyInfo(_strategyContract).rewardWbtcAmount()
        );
    }

    function earnPreparation(
        address _strategyContract,
        uint256 _minimumToken0SwapOutAmount,
        uint256 _minimumToken1SwapOutAmount,
        uint256 _minimumBuybackSwapOutAmount
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).earnPreparation(
            _minimumToken0SwapOutAmount,
            _minimumToken1SwapOutAmount,
            _minimumBuybackSwapOutAmount
        );
        require(getEarningFlag(_strategyContract) == true, "earn prep error");

        emit EarnPreparation(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            IStrategyInfo(_strategyContract).rewardWbtcAmount(),
            getRemainingEarnCountDown(_strategyContract)
        );
    }

    function earn(address _strategyContract) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).earn();

        emit Earn(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            getRemainingEarnCountDown(_strategyContract)
        );
    }

    function work(
        address _fundManagerVaultContract
    ) public onlyRole(EXECUTOR_ROLE) {
        distribute(_fundManagerVaultContract);
    }

    function enter(
        address _fundManagerVaultContract
    ) public onlyRole(EXECUTOR_ROLE) {
        distribute(_fundManagerVaultContract);
    }

    function allocate(
        address _fundManagerVaultContract
    ) public onlyRole(EXECUTOR_ROLE) {
        distribute(_fundManagerVaultContract);
    }

    function distribute(address _fundManagerVaultContract) private {
        uint256 wbtcBeforeTx = IFundManagerVault(_fundManagerVaultContract)
            .getWbtcBalance();

        IFundManagerVault(_fundManagerVaultContract).allocate();

        uint256 wbtcAfterTx = IFundManagerVault(_fundManagerVaultContract)
            .getWbtcBalance();

        emit Allocate(
            _fundManagerVaultContract,
            msg.sender,
            wbtcBeforeTx.sub(wbtcAfterTx),
            wbtcAfterTx
        );
    }

    /// @dev rescale related
    function rescale(
        address _strategyContract,
        address _rescaleTickBoundaryCalculatorContract,
        bool _wasInRange
    ) public onlyRole(EXECUTOR_ROLE) {
        (
            bool allowRescale,
            int24 newTickUpper,
            int24 newTickLower
        ) = IRescaleTickBoundaryCalculator(
                _rescaleTickBoundaryCalculatorContract
            ).verifyAndGetNewRescaleTickBoundary(
                    _wasInRange,
                    lastRescaleTick[_strategyContract],
                    _strategyContract,
                    address(this)
                );
        require(allowRescale, "current condition not allow rescale");

        triggerRescaleStartEvent(_strategyContract, _wasInRange);

        (int24 currentTick, , ) = LiquidityNftHelper.getTickInfo(
            IStrategyInfo(_strategyContract).liquidityNftId(),
            Constants.UNISWAP_V3_FACTORY_ADDRESS,
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        );

        IStrategy(_strategyContract).rescale(newTickUpper, newTickLower);

        lastRescaleTick[_strategyContract] = currentTick;

        triggerRescaleEndEvent(_strategyContract, newTickUpper, newTickLower);
    }

    function triggerRescaleStartEvent(
        address _strategyContract,
        bool _wasInRange
    ) internal {
        (
            int24 currentTick,
            int24 originalTickLower,
            int24 originalTickUpper
        ) = LiquidityNftHelper.getTickInfo(
                IStrategyInfo(_strategyContract).liquidityNftId(),
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );

        emit RescaleStart(
            _strategyContract,
            msg.sender,
            _wasInRange,
            IStrategyInfo(_strategyContract).tickSpacing(),
            tickGapUpper[_strategyContract],
            tickGapLower[_strategyContract],
            tickBoundaryOffset[_strategyContract],
            lastRescaleTick[_strategyContract],
            currentTick,
            originalTickUpper,
            originalTickLower
        );
    }

    function triggerRescaleEndEvent(
        address _strategyContract,
        int24 newTickUpper,
        int24 newTickLower
    ) internal {
        (int24 currentTick, , ) = LiquidityNftHelper.getTickInfo(
            IStrategyInfo(_strategyContract).liquidityNftId(),
            Constants.UNISWAP_V3_FACTORY_ADDRESS,
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        );

        emit RescaleEnd(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).dustToken0Amount(),
            IStrategyInfo(_strategyContract).dustToken1Amount(),
            IStrategyInfo(_strategyContract).tickSpacing(),
            currentTick,
            tickSpreadUpper[_strategyContract],
            tickSpreadLower[_strategyContract],
            rescaleTickBoundaryOffset[_strategyContract],
            newTickUpper,
            newTickLower
        );
    }

    /// @dev deposit dust token related
    function depositDustToken(
        address _strategyContract,
        bool _depositDustToken0
    ) public onlyRole(EXECUTOR_ROLE) {
        (
            uint256 increasedToken0Amount,
            uint256 increasedToken1Amount
        ) = IStrategy(_strategyContract).depositDustToken(_depositDustToken0);

        emit DepositDustToken(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            _depositDustToken0,
            increasedToken0Amount,
            increasedToken1Amount,
            IStrategyInfo(_strategyContract).dustToken0Amount(),
            IStrategyInfo(_strategyContract).dustToken1Amount()
        );
    }
}

