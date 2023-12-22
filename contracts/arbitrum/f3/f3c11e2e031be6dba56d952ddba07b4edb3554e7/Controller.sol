// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IControllerEvent.sol";
import "./IStrategyInfo.sol";
import "./IStrategy.sol";
import "./IStrategySetter.sol";
import "./Constants.sol";
import "./LiquidityNftHelper.sol";
import "./AccessControl.sol";
import "./SafeMath.sol";

/// @dev verified, private contract
/// @dev only owner or operator/backend callable
contract Controller is AccessControl, IControllerEvent {
    using SafeMath for uint256;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

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

        int24 tickEndurance = IStrategyInfo(_strategyContract).tickEndurance();
        int24 tickSpacing = IStrategyInfo(_strategyContract).tickSpacing();
        isWithinRange = LiquidityNftHelper
            .verifyCurrentPriceInLiquidityNftValidRange(
                tickEndurance,
                tickSpacing,
                liquidityNftId,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
    }

    function isSwapIntervalValid(
        address _strategyContract
    ) public view returns (bool isValidSwapInterval) {
        uint256 currentTimeStamp = block.timestamp;
        uint256 lastSwapTimestamp = IStrategyInfo(_strategyContract)
            .lastSwapTimestamp();
        uint256 minSwapTimeInterval = IStrategyInfo(_strategyContract)
            .minSwapTimeInterval();

        if ((lastSwapTimestamp.add(minSwapTimeInterval)) <= currentTimeStamp) {
            return true;
        } else {
            return false;
        }
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

    function getRemainingRescaleCountDown(
        address _strategyContract
    ) public view returns (uint256 remainingRescale) {
        uint256 remainingSwapAmount = IStrategyInfo(_strategyContract)
            .remainingSwapAmount();
        if (remainingSwapAmount == 0) {
            return 0;
        }

        bool swapToken0ToToken1 = IStrategyInfo(_strategyContract)
            .swapToken0ToToken1();
        uint256 maxSwapAmount;
        if (swapToken0ToToken1) {
            maxSwapAmount = IStrategyInfo(_strategyContract)
                .maxToken0ToToken1SwapAmount();
        } else {
            maxSwapAmount = IStrategyInfo(_strategyContract)
                .maxToken1ToToken0SwapAmount();
        }

        (uint256 quotient, uint256 remainder) = calculateQuotientAndRemainder(
            remainingSwapAmount,
            maxSwapAmount
        );

        return remainder > 0 ? (quotient.add(1)) : quotient;
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

    /// @dev tickSpread setter
    function setTickSpread(
        address _strategyContract,
        int24 _tickSpread
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setTickSpread(_tickSpread);

        emit SetTickSpread(_strategyContract, msg.sender, _tickSpread);
    }

    /// @dev tickEndurance setter
    function setTickEndurance(
        address _strategyContract,
        int24 _tickEndurance
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setTickEndurance(_tickEndurance);

        emit SetTickEndurance(_strategyContract, msg.sender, _tickEndurance);
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

    /// @dev fundManager setter
    function setFundManagerByIndex(
        address _strategyContract,
        uint256 _index,
        address _fundManagerAddress,
        uint24 _fundManagerProfitNumerator
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setFundManagerByIndex(
            _index,
            _fundManagerAddress,
            _fundManagerProfitNumerator
        );

        emit SetFundManagerByIndex(
            _strategyContract,
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

    /// @dev maxToken0ToToken1SwapAmount setter
    function setMaxToken0ToToken1SwapAmount(
        address _strategyContract,
        uint256 _maxToken0ToToken1SwapAmount
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setMaxToken0ToToken1SwapAmount(
            _maxToken0ToToken1SwapAmount
        );

        emit SetMaxToken0ToToken1SwapAmount(
            _strategyContract,
            msg.sender,
            _maxToken0ToToken1SwapAmount
        );
    }

    /// @dev maxToken1ToToken0SwapAmount setter
    function setMaxToken1ToToken0SwapAmount(
        address _strategyContract,
        uint256 _maxToken1ToToken0SwapAmount
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setMaxToken1ToToken0SwapAmount(
            _maxToken1ToToken0SwapAmount
        );

        emit SetMaxToken1ToToken0SwapAmount(
            _strategyContract,
            msg.sender,
            _maxToken1ToToken0SwapAmount
        );
    }

    /// @dev minSwapTimeInterval setter
    function setMinSwapTimeInterval(
        address _strategyContract,
        uint256 _minSwapTimeInterval
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategySetter(_strategyContract).setMinSwapTimeInterval(
            _minSwapTimeInterval
        );

        emit SetMinSwapTimeInterval(
            _strategyContract,
            msg.sender,
            _minSwapTimeInterval
        );
    }

    /// @dev earn related
    function earnPreparation(
        address _strategyContract
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).earnPreparation();
        require(getEarningFlag(_strategyContract) == true, "earn prep error");

        emit EarnPreparation(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).liquidityNftId(),
            IStrategyInfo(_strategyContract).rewardUsdtAmount(),
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

    /// @dev rescale related
    function rescalePreparation(
        address _strategyContract
    ) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).rescalePreparation();
        require(
            getRescalingFlag(_strategyContract) == true,
            "rescale prep error"
        );

        emit RescalePreparation(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).dustToken0Amount(),
            IStrategyInfo(_strategyContract).dustToken1Amount(),
            IStrategyInfo(_strategyContract).swapToken0ToToken1(),
            IStrategyInfo(_strategyContract).remainingSwapAmount(),
            getRemainingRescaleCountDown(_strategyContract)
        );
    }

    function rescale(address _strategyContract) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).rescale();

        emit Rescale(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).dustToken0Amount(),
            IStrategyInfo(_strategyContract).dustToken1Amount(),
            IStrategyInfo(_strategyContract).lastSwapTimestamp(),
            IStrategyInfo(_strategyContract).swapToken0ToToken1(),
            IStrategyInfo(_strategyContract).remainingSwapAmount(),
            getRemainingRescaleCountDown(_strategyContract)
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

