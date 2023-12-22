// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeMath.sol";

import "./SafeToken.sol";
import "./Constant.sol";

import "./IRebateDistributor.sol";
import "./IPriceCalculator.sol";
import "./ICore.sol";
import "./IGToken.sol";
import "./ILocker.sol";
import "./IBEP20.sol";

contract RebateDistributor is IRebateDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    address internal constant ETH = 0x0000000000000000000000000000000000000000;
    uint256 public constant MAX_ADMIN_FEE_RATE = 5e17;
    uint256 public constant REBATE_CYCLE = 7 days;

    /* ========== STATE VARIABLES ========== */

    ICore public core;
    ILocker public locker;
    IPriceCalculator public priceCalc;
    Constant.RebateCheckpoint[] public rebateCheckpoints;
    uint256 public adminFeeRate;
    address public keeper;

    mapping(address => uint256) private userCheckpoint;
    mapping(address => Constant.RebateClaimInfo[]) private claimHistory;
    uint256 private adminCheckpoint;

    /* ========== VARIABLE GAP ========== */

    uint256[50] private __gap;

    /* ========== MODIFIERS ========== */

    /// @dev msg.sender 가 core address 인지 검증
    modifier onlyCore() {
        require(msg.sender == address(core), "GToken: only Core Contract");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "RebateDistributor: caller is not the owner or keeper");
        _;
    }

    /* ========== EVENTS ========== */

    event RebateClaimed(address indexed user, address[] markets, uint256[] uAmount, uint256[] gAmount);
    event AdminFeeRateUpdated(uint256 newAdminFeeRate);
    event AdminRebateTreasuryUpdated(address newTreasury);
    event KeeperUpdated(address newKeeper);

    /* ========== SPECIAL FUNCTIONS ========== */

    receive() external payable {}

    /* ========== INITIALIZER ========== */

    function initialize(address _core, address _locker, address _priceCalc) external initializer {
        require(_core != address(0), "RebateDistributor: invalid core address");
        require(_locker != address(0), "RebateDistributor: invalid locker address");
        require(_priceCalc != address(0), "RebateDistributor: invalid priceCalc address");

        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        core = ICore(_core);
        locker = ILocker(_locker);
        priceCalc = IPriceCalculator(_priceCalc);

        adminCheckpoint = block.timestamp;
        adminFeeRate = 5e17;

        if (rebateCheckpoints.length == 0) {
            rebateCheckpoints.push(
                Constant.RebateCheckpoint({
                    timestamp: _truncateTimestamp(block.timestamp),
                    totalScore: _getTotalScoreAtTruncatedTime(),
                    adminFeeRate: adminFeeRate
                })
            );
        }

        _approveMarkets();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice set keeper address
    /// @param _keeper new keeper address
    function setKeeper(address _keeper) external override onlyKeeper {
        require(_keeper != address(0), "RebateDistributor: invalid keeper address");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function updateAdminFeeRate(uint256 newAdminFeeRate) external override onlyKeeper {
        require(newAdminFeeRate <= MAX_ADMIN_FEE_RATE, "RebateDisbtirubor: Invalid fee rate");
        adminFeeRate = newAdminFeeRate;
        emit AdminFeeRateUpdated(newAdminFeeRate);
    }

    function approveMarkets() external override onlyKeeper {
        _approveMarkets();
    }

    /// @notice Claim accured admin rebates
    function claimAdminRebates()
        external
        override
        nonReentrant
        onlyKeeper
        returns (uint256[] memory rebates, address[] memory markets, uint256[] memory gAmounts)
    {
        (rebates, markets) = accuredAdminRebate();
        adminCheckpoint = block.timestamp;
        gAmounts = new uint256[](markets.length);

        for (uint256 i = 0; i < markets.length; i++) {
            uint256 exchangeRate = IGToken(markets[i]).exchangeRate();
            uint256 gAmount = rebates[i].mul(1e18).div(exchangeRate);
            if (gAmount > 0) {
                address(markets[i]).safeTransfer(msg.sender, gAmount);
                gAmounts[i] = gAmounts[i].add(gAmount);
            }
        }

        emit RebateClaimed(msg.sender, markets, rebates, gAmounts);
    }

    function addRebateAmount(address gToken, uint256 uAmount) external override onlyCore {
        _addRebateAmount(gToken, uAmount);
    }

    /* ========== VIEWS ========== */

    /// @notice Accured rebate amount of account
    /// @param account account address
    function accuredRebates(
        address account
    )
        public
        view
        override
        returns (uint256[] memory rebates, address[] memory markets, uint256[] memory prices, uint256 value)
    {
        Constant.RebateCheckpoint memory lastCheckpoint = rebateCheckpoints[rebateCheckpoints.length - 1];
        markets = core.allMarkets();
        rebates = new uint256[](markets.length);
        prices = priceCalc.getUnderlyingPrices(markets);
        value = 0;

        if (locker.lockInfoOf(account).length == 0) return (rebates, markets, prices, value);

        for (
            uint256 nextTimestamp = _truncateTimestamp(
                userCheckpoint[account] != 0 ? userCheckpoint[account] : locker.lockInfoOf(account)[0].timestamp
            ).add(REBATE_CYCLE);
            nextTimestamp <= lastCheckpoint.timestamp.sub(REBATE_CYCLE);
            nextTimestamp = nextTimestamp.add(REBATE_CYCLE)
        ) {
            uint256 votingPower = _getUserVPAt(account, nextTimestamp);
            if (votingPower == 0) continue;

            Constant.RebateCheckpoint storage currentCheckpoint = rebateCheckpoints[_getCheckpointIdxAt(nextTimestamp)];

            for (uint256 i = 0; i < markets.length; i++) {
                if (currentCheckpoint.amount[markets[i]] > 0) {
                    uint256 amount = currentCheckpoint
                        .amount[markets[i]]
                        .mul(uint256(1e18).sub(currentCheckpoint.adminFeeRate).mul(votingPower))
                        .div(1e36);
                    rebates[i] = rebates[i].add(amount);
                    value = value.add(amount.mul(10 ** (18 - _getDecimals(markets[i]))).mul(prices[i]).div(1e18));
                }
            }
        }
    }

    /// @notice Accured rebate amount of admin
    function accuredAdminRebate() public view returns (uint256[] memory rebates, address[] memory markets) {
        Constant.RebateCheckpoint memory lastCheckpoint = rebateCheckpoints[rebateCheckpoints.length - 1];
        markets = core.allMarkets();
        rebates = new uint256[](markets.length);

        for (
            uint256 nextTimestamp = _truncateTimestamp(adminCheckpoint).add(REBATE_CYCLE);
            nextTimestamp <= lastCheckpoint.timestamp.sub(REBATE_CYCLE);
            nextTimestamp = nextTimestamp.add(REBATE_CYCLE)
        ) {
            uint256 checkpointIdx = _getCheckpointIdxAt(nextTimestamp);
            Constant.RebateCheckpoint storage currentCheckpoint = rebateCheckpoints[checkpointIdx];
            for (uint256 i = 0; i < markets.length; i++) {
                if (currentCheckpoint.amount[markets[i]] > 0) {
                    rebates[i] = rebates[i].add(
                        currentCheckpoint.amount[markets[i]].mul(currentCheckpoint.adminFeeRate).div(1e18)
                    );
                }
            }
        }
    }

    function thisWeekRebatePool()
        external
        view
        override
        returns (uint256[] memory rebates, address[] memory markets, uint256 value, uint256 adminRate)
    {
        markets = core.allMarkets();
        rebates = new uint256[](markets.length);
        value = 0;

        uint256[] memory prices = priceCalc.getUnderlyingPrices(markets);
        Constant.RebateCheckpoint storage lastCheckpoint = rebateCheckpoints[rebateCheckpoints.length - 1];
        adminRate = lastCheckpoint.adminFeeRate;

        for (uint256 i = 0; i < markets.length; i++) {
            if (lastCheckpoint.amount[markets[i]] > 0) {
                rebates[i] = rebates[i].add(lastCheckpoint.amount[markets[i]]);
                value = value.add(rebates[i].mul(10 ** (18 - _getDecimals(markets[i]))).mul(prices[i]).div(1e18));
            }
        }
    }

    function weeklyRebatePool() public view override returns (uint256 value, uint256 adminRate) {
        value = 0;
        adminRate = 0;

        if (rebateCheckpoints.length >= 2) {
            address[] memory markets = core.allMarkets();
            uint256[] memory prices = priceCalc.getUnderlyingPrices(markets);
            Constant.RebateCheckpoint storage checkpoint = rebateCheckpoints[rebateCheckpoints.length - 2];
            adminRate = checkpoint.adminFeeRate;

            for (uint256 i = 0; i < markets.length; i++) {
                if (checkpoint.amount[markets[i]] > 0) {
                    value = value.add(
                        checkpoint.amount[markets[i]].mul(10 ** (18 - _getDecimals(markets[i]))).mul(prices[i]).div(
                            1e18
                        )
                    );
                }
            }
        }
    }

    function weeklyProfitOfVP(uint256 vp) public view override returns (uint256 amount) {
        require(vp >= 0 && vp <= 1e18, "RebateDistributor: Invalid VP");

        (uint256 value, uint256 adminRate) = weeklyRebatePool();
        uint256 feeRate = uint256(1e18).sub(adminRate).mul(vp);
        amount = 0;

        if (value > 0) {
            amount = value.mul(feeRate).div(1e36);
        }
    }

    function weeklyProfitOf(address account) external view override returns (uint256) {
        uint256 vp = _getUserVPAt(account, block.timestamp.add(REBATE_CYCLE));
        return weeklyProfitOfVP(vp);
    }

    function totalClaimedRebates(
        address account
    ) external view override returns (uint256[] memory rebates, address[] memory markets, uint256 value) {
        markets = core.allMarkets();
        rebates = new uint256[](markets.length);
        value = 0;
        uint256 claimCount = claimHistory[account].length;

        for (uint256 i = 0; i < claimCount; i++) {
            Constant.RebateClaimInfo memory info = claimHistory[account][i];

            for (uint256 j = 0; j < markets.length; j++) {
                for (uint256 k = 0; k < info.markets.length; k++) {
                    if (markets[j] == info.markets[k]) {
                        rebates[j] = rebates[j].add(info.amount[k]);
                    }
                }
            }
            value = value.add(info.value);
        }
    }

    function indicativeYearProfit() external view override returns (uint256) {
        (uint256 totalScore, ) = locker.totalScore();
        if (totalScore == 0) {
            return 0;
        }

        uint256 preScore = locker.preScoreOf(
            address(0),
            1e18,
            uint256(block.timestamp).add(365 days),
            Constant.EcoScorePreviewOption.LOCK
        );
        uint256 weeklyProfit = weeklyProfitOfVP(preScore.mul(1e18).div(totalScore));

        return weeklyProfit.mul(52);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Add checkpoint if needed and supply supluses
    function checkpoint() external override nonReentrant {
        Constant.RebateCheckpoint memory lastRebateScore = rebateCheckpoints[rebateCheckpoints.length - 1];
        address[] memory markets = core.allMarkets();

        uint256 nextTimestamp = lastRebateScore.timestamp.add(REBATE_CYCLE);
        while (block.timestamp >= nextTimestamp) {
            (uint256 totalScore, uint256 slope) = locker.totalScore();
            uint256 newTotalScore = totalScore == 0 ? 0 : totalScore.add(slope.mul(block.timestamp.sub(nextTimestamp)));
            rebateCheckpoints.push(
                Constant.RebateCheckpoint({
                    totalScore: newTotalScore,
                    timestamp: nextTimestamp,
                    adminFeeRate: adminFeeRate
                })
            );
            nextTimestamp = nextTimestamp.add(REBATE_CYCLE);

            for (uint256 i = 0; i < markets.length; i++) {
                IGToken(markets[i]).withdrawReserves();
            }
        }
        _supplySurpluses();
    }

    /// @notice Claim accured all rebates
    function claimRebates()
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256[] memory rebates, address[] memory markets, uint256[] memory gAmounts)
    {
        uint256[] memory prices;
        uint256 value;
        (rebates, markets, prices, value) = accuredRebates(msg.sender);
        userCheckpoint[msg.sender] = block.timestamp;
        gAmounts = new uint256[](markets.length);

        for (uint256 i = 0; i < markets.length; i++) {
            uint256 exchangeRate = IGToken(markets[i]).exchangeRate();
            uint256 gAmount = rebates[i].mul(1e18).div(exchangeRate);
            if (gAmount > 0) {
                address(markets[i]).safeTransfer(msg.sender, gAmount);
                gAmounts[i] = gAmounts[i].add(gAmount);
            }
        }

        claimHistory[msg.sender].push(
            Constant.RebateClaimInfo({
                timestamp: block.timestamp,
                markets: markets,
                amount: rebates,
                prices: prices,
                value: value
            })
        );
        emit RebateClaimed(msg.sender, markets, rebates, gAmounts);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @dev Approve markets to supply
    function _approveMarkets() private {
        address[] memory markets = core.allMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address underlying = IGToken(markets[i]).underlying();

            if (underlying != ETH) {
                underlying.safeApprove(markets[i], 0);
                underlying.safeApprove(markets[i], uint256(-1));
            }
        }
    }

    /// @dev Supply all having underlying tokens to markets
    function _supplySurpluses() private {
        require(rebateCheckpoints.length > 0, "RebateDistributor: invalid checkpoint");

        Constant.RebateCheckpoint storage lastCheckpoint = rebateCheckpoints[rebateCheckpoints.length - 1];
        address[] memory markets = core.allMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address underlying = IGToken(markets[i]).underlying();
            uint256 balance = underlying == address(ETH)
                ? address(this).balance
                : IBEP20(underlying).balanceOf(address(this));

            if (underlying == ETH && balance > 0) {
                core.supply{value: balance}(markets[i], balance);
            }
            if (underlying != ETH && balance > 0) {
                core.supply(markets[i], balance);
            }
            lastCheckpoint.amount[markets[i]] = lastCheckpoint.amount[markets[i]].add(balance);
        }
    }

    function _addRebateAmount(address gToken, uint256 uAmount) private {
        Constant.RebateCheckpoint storage lastCheckpoint = rebateCheckpoints[rebateCheckpoints.length - 1];
        lastCheckpoint.amount[gToken] = lastCheckpoint.amount[gToken].add(uAmount);
    }

    /// @notice Find checkpoint index of timestamp
    /// @param timestamp checkpoint timestamp
    function _getCheckpointIdxAt(uint256 timestamp) private view returns (uint256) {
        timestamp = _truncateTimestamp(timestamp);

        for (uint256 i = rebateCheckpoints.length - 1; i < uint256(-1); i--) {
            if (rebateCheckpoints[i].timestamp == timestamp) {
                return i;
            }
        }

        revert("RebateDistributor: checkpoint index error");
    }

    /// @notice Get total score at timestamp
    /// @dev Get from
    function _getTotalScoreAt(uint256 timestamp) private view returns (uint256) {
        for (uint256 i = rebateCheckpoints.length - 1; i < uint256(-1); i--) {
            if (rebateCheckpoints[i].timestamp == timestamp) {
                return rebateCheckpoints[i].totalScore;
            }
        }

        if (rebateCheckpoints[rebateCheckpoints.length - 1].timestamp < timestamp) {
            (uint256 totalScore, uint256 slope) = locker.totalScore();

            if (totalScore == 0 || slope == 0) {
                return 0;
            } else if (block.timestamp > timestamp) {
                return totalScore.add(slope.mul(block.timestamp.sub(timestamp)));
            } else if (block.timestamp < timestamp) {
                return totalScore.sub(slope.mul(timestamp.sub(block.timestamp)));
            } else {
                return totalScore;
            }
        }

        revert("RebateDistributor: checkpoint index error");
    }

    /// @notice Get total score at truncated current time
    function _getTotalScoreAtTruncatedTime() private view returns (uint256 score) {
        (uint256 totalScore, uint256 slope) = locker.totalScore();
        uint256 lastTimestmp = _truncateTimestamp(block.timestamp);
        score = 0;

        if (totalScore > 0 && slope > 0) {
            score = totalScore.add(slope.mul(block.timestamp.sub(lastTimestmp)));
        }
    }

    /// @notice Get user voting power at timestamp
    /// @param account account address
    /// @param timestamp timestamp
    function _getUserVPAt(address account, uint256 timestamp) private view returns (uint256) {
        timestamp = _truncateTimestamp(timestamp);
        uint256 userScore = locker.scoreOfAt(account, timestamp);
        uint256 totalScore = _getTotalScoreAt(timestamp);

        return totalScore != 0 ? userScore.mul(1e18).div(totalScore).div(1e8).mul(1e8) : 0;
    }

    /// @notice Truncate timestamp to adjust to rebate checkpoint
    function _truncateTimestamp(uint256 timestamp) private pure returns (uint256) {
        return timestamp.div(REBATE_CYCLE).mul(REBATE_CYCLE);
    }

    /// @notice View underlying token decimals by gToken address
    /// @param gToken gToken address
    function _getDecimals(address gToken) private view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18;
        } else {
            decimals = IBEP20(underlying).decimals();
        }
    }
}

