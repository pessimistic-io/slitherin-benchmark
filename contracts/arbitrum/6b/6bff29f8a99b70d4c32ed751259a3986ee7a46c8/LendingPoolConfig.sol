// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";

contract LendingPoolConfig is Ownable {
  /* ========== STATE VARIABLES ========== */

  // Base interest rate which is the y-intercept when utilization rate is 0 in 1e18
  uint256 public baseRate;
  // Multiplier of utilization rate that gives the slope of the interest rate in 1e18
  uint256 public multiplier;
  // Multiplier after hitting a specified utilization point (kink2) in 1e18
  uint256 public jumpMultiplier;
  // Utilization point at which the interest rate is fixed in 1e18
  uint256 public kink1;
  // Utilization point at which the jump multiplier is applied in 1e18
  uint256 public kink2;

  /* ========== MAPPINGS ========== */

  // Mapping of approved keepers
  mapping(address => bool) public keepers;

  /* ========== EVENTS ========== */

  event UpdateInterestRateModel(
    uint256 baseRate,
    uint256 multiplier,
    uint256 jumpMultiplier,
    uint256 kink1,
    uint256 kink2
  );
  event UpdateKeeper(address _keeper, bool _status);

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant SECONDS_PER_YEAR = 365 days;

  /* ========== MODIFIERS ========== */

  /**
    * Only allow approved addresses for keepers
  */
  modifier onlyKeeper() {
    require(keepers[msg.sender], "Keeper not approved");
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _baseRate // Base interest rate when utilization rate is 0 in 1e18
    * @param _multiplier // Multiplier of utilization rate that gives the slope of the interest rate in 1e18
    * @param _jumpMultiplier // Multiplier after hitting a specified utilization point (kink2) in 1e18
    * @param _kink1 // Utilization point at which the interest rate is fixed in 1e18
    * @param _kink2 // Utilization point at which the jump multiplier is applied in 1e18
  */
  constructor(
    uint256 _baseRate,
    uint256 _multiplier,
    uint256 _jumpMultiplier,
    uint256 _kink1,
    uint256 _kink2
  ) {
      keepers[msg.sender] = true;
      updateInterestRateModel(_baseRate, _multiplier, _jumpMultiplier, _kink1, _kink2);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Return the interest rate (APR) based on the utilization rate
    * @param _debt Total borrowed amount
    * @param _floating Total available liquidity
    * @return rate Current interest rate in annual percentage return in 1e18
  */
  function interestRateAPR(uint256 _debt, uint256 _floating) external view returns (uint256) {
    return _calculateInterestRate(_debt, _floating);
  }

  /**
    * Return the interest rate based on the utilization rate, per second
    * @param _debt Total borrowed amount
    * @param _floating Total available liquidity
    * @return ratePerSecond Current interest rate per second in 1e18
  */
  function interestRatePerSecond(uint256 _debt, uint256 _floating) external view returns (uint256) {
    return _calculateInterestRate(_debt, _floating) / SECONDS_PER_YEAR;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Return the interest rate based on the utilization rate
    * @param _debt Total borrowed amount
    * @param _floating Total available liquidity
    * @return rate Current interest rate in 1e18
  */
  function _calculateInterestRate(uint256 _debt, uint256 _floating) internal view returns (uint256) {
    if (_debt == 0 && _floating == 0) return 0;

    uint256 total = _debt + _floating;
    uint256 utilizationRate = _debt * SAFE_MULTIPLIER / total;

    // If utilization above kink2, return a higher interest rate
    // (base + rate + excess utilization above kink 2 * jumpMultiplier)
    if (utilizationRate > kink2) {
      return baseRate + (kink1 * multiplier / SAFE_MULTIPLIER)
                      + ((utilizationRate - kink2) * jumpMultiplier / SAFE_MULTIPLIER);
    }

    // If utilization between kink1 and kink2, rates are flat
    if (kink1 < utilizationRate && utilizationRate <= kink2) {
      return baseRate + (kink1 * multiplier / SAFE_MULTIPLIER);
    }

    // If utilization below kink1, calculate borrow rate for slope up to kink 1
    return baseRate + (utilizationRate * multiplier / SAFE_MULTIPLIER);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Updates lending pool interest rate model variables, callable only by owner
    @param _baseRate // Base interest rate when utilization rate is 0 in 1e18
    @param _multiplier // Multiplier of utilization rate that gives the slope of the interest rate in 1e18
    @param _jumpMultiplier // Multiplier after hitting a specified utilization point (kink2) in 1e18
    @param _kink1 // Utilization point at which the interest rate is fixed in 1e18
    @param _kink2 // Utilization point at which the jump multiplier is applied in 1e18
  */
  function updateInterestRateModel(
    uint256 _baseRate,
    uint256 _multiplier,
    uint256 _jumpMultiplier,
    uint256 _kink1,
    uint256 _kink2
  ) public onlyKeeper {
    baseRate = _baseRate;
    multiplier = _multiplier;
    jumpMultiplier = _jumpMultiplier;
    kink1 = _kink1;
    kink2 = _kink2;

    emit UpdateInterestRateModel(baseRate, multiplier, jumpMultiplier, kink1, kink2);
  }

  /**
    * Approve or revoke address to be a keeper for this vault
    * @param _keeper Keeper address
    * @param _approval Boolean to approve keeper or not
  */
  function updateKeeper(address _keeper, bool _approval) external onlyOwner {
    require(_keeper != address(0), "Invalid address");
    keepers[_keeper] = _approval;

    emit UpdateKeeper(_keeper, _approval);
  }
}

