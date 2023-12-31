// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// ====================================================================
// ======================= SWEEP Dollar Coin (SWEEP) ==================
// ====================================================================

import "./BaseSweep.sol";
import "./IAMM.sol";
import "./Math.sol";

contract SweepDollarCoin is BaseSweep {
    using Math for uint256;

    IAMM public amm;

    // Addresses
    address public balancer;
    address public treasury;

    // Variables
    int256 public interest_rate; // 4 decimals of precision, e.g. 50000 = 5%
    int256 public step_value; // Amount to change SWEEP interest rate. 4 decimals of precision and default value is 2500 (0.25%)
    uint256 public period_start; // Start time for new period
    uint256 public period_time; // Period Time. Default = 604800 (7 days)
    uint256 public current_target_price; // The cuurent target price of SWEEP
    uint256 public next_target_price; // The next target price of SWEEP
    uint256 public arb_spread; // 4 decimals of precision, e.g. 1000 = 0.1%

    // Constants
    uint256 internal constant SPREAD_PRECISION = 1e6;

    /* ========== Events ========== */

    event PeriodTimeSet(uint256 new_period_time);
    event ArbSpreadSet(uint256 new_arb_spread);
    event InterestRateSet(int256 new_interest_rate);
    event AMMSet(address ammAddress);
    event BalancerSet(address balancer_address);
    event TreasurySet(address treasury_address);
    event NewPeriodStarted(uint256 period_start);
    event TargetPriceSet(
        uint256 current_target_price,
        uint256 next_target_price
    );

    /* ========== Errors ========== */

    error MintNotAllowed();
    error NotOwnerOrBalancer();
    error NotBalancer();
    error NotPassedPeriodTime();
    error AlreadyExist();

    /* ======= MODIFIERS ====== */

    modifier onlyBalancer() {
        if (msg.sender != balancer) revert NotBalancer();
        _;
    }

    // Constructor
    function initialize(
        address _lzEndpoint,
        address _fast_multisig,
        int256 _step_value
    ) public initializer {
        BaseSweep.__Sweep_init(
            "SWEEP Dollar Coin",
            "SWEEP",
            _lzEndpoint,
            _fast_multisig
        );

        step_value = _step_value;
        interest_rate = 0;
        current_target_price = 1e6;
        next_target_price = 1e6;
        period_time = 604800; // 7 days
        arb_spread = 0;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Get Sweep Price
     * The Sweep Price comes from the AMM.
     * @return uint256 Sweep price
     */
    function amm_price() public view returns (uint256) {
        return amm.getPrice();
    }

    /**
     * @notice Get Sweep Time Weighted Averate Price
     * The Sweep Price comes from the AMM.
     * @return uint256 Sweep price
     */
    function twa_price() external view returns (uint256) {
        return amm.getTWAPrice();
    }

    /**
     * @notice Get Sweep Target Price
     * Target Price will be used to peg the Sweep Price safely.
     * It must have 6 decimals as USD_DECIMALS in IAMM.
     * @return uint256 Sweep target price
     */
    function target_price() public view returns (uint256) {
        if (block.timestamp - period_start >= period_time) {
            // if over period, return next target price for new period
            return next_target_price;
        } else {
            // if in period, return current target price
            return current_target_price;
        }
    }

    /**
     * @notice Get Sweep Minting Allow Status
     * @return bool Sweep minting allow status
     */
    function is_minting_allowed() public view returns (bool) {
        uint256 arb_price = ((SPREAD_PRECISION - arb_spread) * target_price()) /
            SPREAD_PRECISION;
        return amm_price() >= arb_price ? true : false;
    }

    /* ========== Actions ========== */

    /**
     * @notice Mint (Override)
     * @param _minter Address of a minter.
     * @param _amount Amount for mint.
     */
    function minter_mint(
        address _minter,
        uint256 _amount
    ) public override validMinter(msg.sender) whenNotPaused {
        if (address(amm) != address(0) && !is_minting_allowed())
            revert MintNotAllowed();

        super.minter_mint(_minter, _amount);
    }

    /**
     * @notice Set Period Time
     * @param _period_time.
     */
    function setPeriodTime(uint256 _period_time) external onlyGov {
        period_time = _period_time;

        emit PeriodTimeSet(_period_time);
    }

    /**
     * @notice Set Balancer Address
     * @param _balancer.
     */
    function setBalancer(address _balancer) external onlyGov {
        if (_balancer == address(0)) revert ZeroAddressDetected();
        balancer = _balancer;

        emit BalancerSet(_balancer);
    }

    /**
     * @notice Set arbitrage spread ratio
     * @param _new_arb_spread.
     */
    function setArbSpread(uint256 _new_arb_spread) external onlyGov {
        arb_spread = _new_arb_spread;

        emit ArbSpreadSet(_new_arb_spread);
    }

    /**
     * @notice Set AMM
     * @param ammAddress.
     */
    function setAMM(
        address ammAddress
    ) external onlyGov {
        if (ammAddress == address(0)) revert ZeroAddressDetected();
        amm = IAMM(ammAddress);

        emit AMMSet(ammAddress);
    }

    /**
     * @notice Set Interest Rate
     * @param _new_interest_rate.
     */
    function setInterestRate(int256 _new_interest_rate) external onlyBalancer {
        interest_rate = _new_interest_rate;

        emit InterestRateSet(_new_interest_rate);
    }

    /**
     * @notice Set Target Price
     * @param _current_target_price.
     * @param _next_target_price.
     */
    function setTargetPrice(
        uint256 _current_target_price,
        uint256 _next_target_price
    ) external onlyBalancer {
        current_target_price = _current_target_price;
        next_target_price = _next_target_price;

        emit TargetPriceSet(_current_target_price, _next_target_price);
    }

    /**
     * @notice Start New Period
     */
    function startNewPeriod() external onlyBalancer {
        if (block.timestamp - period_start < period_time)
            revert NotPassedPeriodTime();

        period_start = block.timestamp;

        emit NewPeriodStarted(period_start);
    }

    /**
     * @notice Set Treasury Address
     * @param _treasury.
     */
    function setTreasury(address _treasury) external onlyMultisig {
        if (_treasury == address(0)) revert ZeroAddressDetected();
        if (treasury != address(0)) revert AlreadyExist();
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    /**
     * @notice SWEEP in USD
     * Calculate the amount of USDX that are equivalent to the SWEEP input.
     * @param sweepAmount Amount of SWEEP.
     * @return usdAmount of USDX.
     */
    function convertToUSD(uint256 sweepAmount) external view returns (uint256 usdAmount) {
        usdAmount = sweepAmount.mulDiv(target_price(), 10 ** decimals());
    }

    /**
     * @notice USD in SWEEP
     * Calculate the amount of SWEEP that are equivalent to the USDX input.
     * @param usdAmount Amount of USDX.
     * @return sweepAmount of SWEEP.
     */
    function convertToSWEEP(uint256 usdAmount) external view returns (uint256 sweepAmount) {
        sweepAmount = usdAmount.mulDiv(10 ** decimals(), target_price());
    }
}

