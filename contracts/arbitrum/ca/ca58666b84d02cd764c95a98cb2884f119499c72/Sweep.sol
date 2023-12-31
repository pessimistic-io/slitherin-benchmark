// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// ====================================================================
// ======================= SWEEP Coin (SWEEP) =========================
// ====================================================================

import "./BaseSweep.sol";
import "./IAMM.sol";
import "./Math.sol";

contract SweepCoin is BaseSweep {
    using Math for uint256;

    IAMM public amm;

    // Addresses
    address public balancer;
    address public treasury;

    // Variables
    int256 public interestRate; // 4 decimals of precision, e.g. 50000 = 5%
    int256 public stepValue; // Amount to change SWEEP interest rate. 4 decimals of precision and default value is 2500 (0.25%)
    uint256 public periodStart; // Start time for new period
    uint256 public periodTime; // Period Time. Default = 604800 (7 days)
    uint256 public currentTargetPrice; // The cuurent target price of SWEEP
    uint256 public nextTargetPrice; // The next target price of SWEEP
    uint256 public arbSpread; // 4 decimals of precision, e.g. 1000 = 0.1%

    // Constants
    uint256 internal constant SPREAD_PRECISION = 1e6;

    /* ========== Events ========== */

    event PeriodTimeSet(uint256 newPeriodTime);
    event ArbSpreadSet(uint256 newArbSpread);
    event InterestRateSet(int256 newInterestRate);
    event AMMSet(address ammAddress);
    event BalancerSet(address balancerAddress);
    event TreasurySet(address treasuryAddress);
    event NewPeriodStarted(uint256 periodStart);
    event TargetPriceSet(
        uint256 currentTargetPrice,
        uint256 nextTargetPrice
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
        address lzEndpoint,
        address fastMultisig,
        int256 stepValue_
    ) public initializer {
        BaseSweep.__Sweep_init(
            "SweepCoin",
            "SWEEP",
            lzEndpoint,
            fastMultisig
        );

        stepValue = stepValue_;
        interestRate = 0;
        currentTargetPrice = 1e6;
        nextTargetPrice = 1e6;
        periodTime = 604800; // 7 days
        arbSpread = 0;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Get Sweep Price
     * The Sweep Price comes from the AMM.
     * @return uint256 Sweep price
     */
    function ammPrice() public view returns (uint256) {
        return amm.getPrice();
    }

    /**
     * @notice Get Sweep Time Weighted Averate Price
     * The Sweep Price comes from the AMM.
     * @return uint256 Sweep price
     */
    function twaPrice() external view returns (uint256) {
        return amm.getTWAPrice();
    }

    /**
     * @notice Get Sweep Target Price
     * Target Price will be used to peg the Sweep Price safely.
     * It must have 6 decimals as USD_DECIMALS in IAMM.
     * @return uint256 Sweep target price
     */
    function targetPrice() public view returns (uint256) {
        if (block.timestamp - periodStart >= periodTime) {
            // if over period, return next target price for new period
            return nextTargetPrice;
        } else {
            // if in period, return current target price
            return currentTargetPrice;
        }
    }

    /**
     * @notice Get Sweep Minting Allow Status
     * @return bool Sweep minting allow status
     */
    function isMintingAllowed() public view returns (bool) {
        uint256 arbPrice = ((SPREAD_PRECISION - arbSpread) * targetPrice()) /
            SPREAD_PRECISION;
        return (ammPrice() >= arbPrice);
    }

    /* ========== Actions ========== */

    /**
     * @notice Mint (Override)
     * @param minter Address of a minter.
     * @param amount Amount for mint.
     */
    function minterMint(
        address minter,
        uint256 amount
    ) public override validMinter(msg.sender) whenNotPaused {
        if (address(amm) != address(0) && !isMintingAllowed())
            revert MintNotAllowed();

        super.minterMint(minter, amount);
    }

    /**
     * @notice Set Period Time
     * @param newPeriodTime.
     */
    function setPeriodTime(uint256 newPeriodTime) external onlyGov {
        periodTime = newPeriodTime;

        emit PeriodTimeSet(newPeriodTime);
    }

    /**
     * @notice Set Balancer Address
     * @param newBalancer.
     */
    function setBalancer(address newBalancer) external onlyGov {
        if (newBalancer == address(0)) revert ZeroAddressDetected();
        balancer = newBalancer;

        emit BalancerSet(newBalancer);
    }

    /**
     * @notice Set arbitrage spread ratio
     * @param newArbSpread.
     */
    function setArbSpread(uint256 newArbSpread) external onlyGov {
        arbSpread = newArbSpread;

        emit ArbSpreadSet(newArbSpread);
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
     * @param newInterestRate.
     */
    function setInterestRate(int256 newInterestRate) external onlyBalancer {
        interestRate = newInterestRate;

        emit InterestRateSet(newInterestRate);
    }

    /**
     * @notice Set Target Price
     * @param newCurrentTargetPrice.
     * @param newNextTargetPrice.
     */
    function setTargetPrice(
        uint256 newCurrentTargetPrice,
        uint256 newNextTargetPrice
    ) external onlyBalancer {
        currentTargetPrice = newCurrentTargetPrice;
        nextTargetPrice = newNextTargetPrice;

        emit TargetPriceSet(newCurrentTargetPrice, newNextTargetPrice);
    }

    /**
     * @notice Start New Period
     */
    function startNewPeriod() external onlyBalancer {
        if (block.timestamp - periodStart < periodTime)
            revert NotPassedPeriodTime();

        periodStart = block.timestamp;

        emit NewPeriodStarted(periodStart);
    }

    /**
     * @notice Set Treasury Address
     * @param newTreasury.
     */
    function setTreasury(address newTreasury) external onlyGov {
        if (newTreasury == address(0)) revert ZeroAddressDetected();
        if (treasury != address(0)) revert AlreadyExist();
        treasury = newTreasury;

        emit TreasurySet(newTreasury);
    }

    /**
     * @notice SWEEP in USD
     * Calculate the amount of USDX that are equivalent to the SWEEP input.
     * @param sweepAmount Amount of SWEEP.
     * @return usdAmount of USDX.
     */
    function convertToUSD(uint256 sweepAmount) external view returns (uint256 usdAmount) {
        usdAmount = sweepAmount.mulDiv(targetPrice(), 10 ** decimals());
    }

    /**
     * @notice USD in SWEEP
     * Calculate the amount of SWEEP that are equivalent to the USDX input.
     * @param usdAmount Amount of USDX.
     * @return sweepAmount of SWEEP.
     */
    function convertToSWEEP(uint256 usdAmount) external view returns (uint256 sweepAmount) {
        sweepAmount = usdAmount.mulDiv(10 ** decimals(), targetPrice());
    }
}

