// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IFundManagerVault.sol";
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

        (isWithinRange, ) = LiquidityNftHelper
            .verifyCurrentPriceInLiquidityNftRange(
                liquidityNftId,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
    }

    function isNftWithinOneTickSpacingRange(
        address _strategyContract
    ) public view returns (bool isWithinOneTickSpacingRange) {
        uint256 liquidityNftId = IStrategyInfo(_strategyContract)
            .liquidityNftId();

        require(
            liquidityNftId != 0,
            "not allow calling when liquidityNftId is 0"
        );

        int24 tickSpacing = IStrategyInfo(_strategyContract).tickSpacing();
        isWithinOneTickSpacingRange = LiquidityNftHelper
            .verifyCurrentPriceInLiquidityNftValidGapRange(
                tickSpacing,
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
        IStrategySetter(_strategyContract).setTickSpreadUpper(_tickSpreadUpper);

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
        IStrategySetter(_strategyContract).setTickSpreadLower(_tickSpreadLower);

        emit SetTickSpreadLower(
            _strategyContract,
            msg.sender,
            _tickSpreadLower
        );
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
            IStrategyInfo(_strategyContract).rewardUsdtAmount()
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

    function allocate(
        address _fundManagerVaultContract
    ) public onlyRole(EXECUTOR_ROLE) {
        uint256 usdtBeforeTx = IFundManagerVault(_fundManagerVaultContract)
            .getUsdtBalance();

        IFundManagerVault(_fundManagerVaultContract).allocate();

        uint256 usdtAfterTx = IFundManagerVault(_fundManagerVaultContract)
            .getUsdtBalance();

        emit Allocate(
            _fundManagerVaultContract,
            msg.sender,
            usdtBeforeTx.sub(usdtAfterTx),
            usdtAfterTx
        );
    }

    /// @dev rescale related
    function rescale(address _strategyContract) public onlyRole(EXECUTOR_ROLE) {
        IStrategy(_strategyContract).rescale();

        emit Rescale(
            _strategyContract,
            msg.sender,
            IStrategyInfo(_strategyContract).dustToken0Amount(),
            IStrategyInfo(_strategyContract).dustToken1Amount()
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

