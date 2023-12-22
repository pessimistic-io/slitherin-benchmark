// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;

// ====================================================================
// ======================= SWEEP Dollar Coin (SWEEP) ==================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./BaseSweep.sol";
import "./UniV3TWAPOracle.sol";

contract SweepDollarCoin is BaseSweep {
    UniV3TWAPOracle private uniV3TWAPOracle;

    // Addresses
    address public sweep_usdc_oracle_address;
    address public balancer;
    address public treasury;

    // Variables
    uint256 public interest_rate; // 6 decimals of precision, e.g. 50000 = 5%
    uint256 public period_start; // Start time for new period
    uint256 public period_time; // Period Time. Default = 604800 (7 days)
    uint256 public current_target_price; // The cuurent target price of SWEEP
    uint256 public next_target_price; // The next target price of SWEEP
    uint256 public step_value; // Amount to change SWEEP interest rate. 6 decimals of precision and default value is 2500 (0.25%)

    // Events
    event PeriodTimeSet(uint256 new_period_time);
    event PeriodStartSet(uint256 new_period_start);
    event StepValueSet(uint256 new_step_value);
    event InterestRateSet(uint256 new_interest_rate);
    event UniswapOracleSet(address uniswap_oracle_address);
    event BalancerSet(address balancer_address);
    event TreasurySet(address treasury_address);
    event NewPeriodStarted(uint256 period_start);
    event TargetPriceSet(uint256 current_target_price, uint256 next_target_price);

    // Constructor
    function initialize(
        address _timelock_address,
        address _multisig_address,
        address _transfer_approver_address,
        address _treasury
    ) public initializer {
        BaseSweep.__Sweep_init(
            _timelock_address,
            _multisig_address,
            _transfer_approver_address,
            "SWEEP Dollar Coin",
            "SWEEP"
        );

        treasury = _treasury;

        interest_rate = 0;
        current_target_price = 1e6;
        next_target_price = 1e6;

        period_time = 604800; // 7 days
        step_value = 2500; // 0.25%
    }

    /* ======= MODIFIERS ====== */
    modifier onlyOwnerOrBalancer() {
        require(msg.sender == owner() || msg.sender == balancer, "Not a Owner or Balancer");
        _;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Get Sweep Price
     * The Sweep Price comes from UniswapV3TWAPOracle.
     * @return uint256 Sweep price
     */
    function amm_price() public view returns (uint256) {
        return uniV3TWAPOracle.getPrice();
    }

    /**
     * @notice Get Sweep Target Price
     * Target Price will be used to peg the Sweep Price safely.
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

    /* ========== Actions ========== */

    /**
     * @notice Set Period Time
     * @param _period_time.
     */
    function setPeriodTime(uint256 _period_time) public onlyOwner {
        period_time = _period_time;

        emit PeriodTimeSet(_period_time);
    }

    /**
     * @notice Set Interest Rate
     * @param _new_interest_rate.
     */
    function setInterestRate(uint256 _new_interest_rate) public onlyOwnerOrBalancer {
        interest_rate = _new_interest_rate;

        emit InterestRateSet(_new_interest_rate);
    }

    /**
     * @notice Set Target Price
     * @param _current_target_price.
     * @param _next_target_price.
     */
    function setTargetPrice(uint256 _current_target_price, uint256 _next_target_price) public onlyOwnerOrBalancer {
        current_target_price = _current_target_price;
        next_target_price = _next_target_price;

        emit TargetPriceSet(_current_target_price, _next_target_price);
    }

    /**
     * @notice Set Balancer Address
     * @param _balancer_address.
     */
    function setBalancer(address _balancer_address) public onlyOwner {
        require(_balancer_address != address(0), "Zero address detected");
        balancer = _balancer_address;

        emit BalancerSet(_balancer_address);
    }

    /**
     * @notice Set Treasury Address
     * @param _treasury_address.
     */
    function setTreasury(address _treasury_address) public onlyOwner {
        require(_treasury_address != address(0), "Zero address detected");
        treasury = _treasury_address;

        emit TreasurySet(_treasury_address);
    }

    /**
     * @notice Set Uniswap Oracle
     * @param _uniswap_oracle_address.
     */
    function setUniswapOracle(address _uniswap_oracle_address) public onlyOwner {
        require(_uniswap_oracle_address != address(0), "Zero address detected");

        sweep_usdc_oracle_address = _uniswap_oracle_address;
        uniV3TWAPOracle = UniV3TWAPOracle(_uniswap_oracle_address);

        emit UniswapOracleSet(_uniswap_oracle_address);
    }

    /**
     * @notice Set step value to change SWEEP interest rate
     * @param _new_step_value.
     */
    function setStepValue(uint256 _new_step_value) public onlyOwner {
        step_value = _new_step_value;

        emit StepValueSet(_new_step_value);
    }

    /**
     * @notice Start New Period
     */
    function startNewPeriod() public onlyOwnerOrBalancer {
        require(
            block.timestamp - period_start >= period_time,
            "Must wait for period time"
        );

        period_start = block.timestamp;
        emit NewPeriodStarted(period_start);
    }
}

