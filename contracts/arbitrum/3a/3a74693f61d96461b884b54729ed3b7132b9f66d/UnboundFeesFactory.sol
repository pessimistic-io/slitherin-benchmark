// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./UnboundMath.sol";

import "./IUnboundFeesFactory.sol";
import "./Ownable.sol";

// UnboundFeesFactory - contract is responsible to calculate fees for all the borrowing and redemption happening on all vaults

contract UnboundFeesFactory is IUnboundFeesFactory, Ownable {

    uint256 public constant DECIMAL_PRECISION = 1e18;

    uint constant public override REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%

    uint constant public override BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%

    // The timestamp of the latest fee operation (redemption or new UND issuance)
    uint256 public lastFeeOperationTime;

    uint256 public baseRate;

    // --- Data structures ---

    uint256 constant public SECONDS_IN_ONE_MINUTE = 60;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 constant public MINUTE_DECAY_FACTOR = 999037758833783000;
    uint constant public MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

    mapping (address => bool) public isBorrowOperationAddress;
    mapping (address => bool) public isAccountManagerAddress;

    // --- Borrowing fee functions ---

    // Updates the baseRate state variable based on time elapsed since the last redemption or UND borrowing operation.
    function decayBaseRateFromBorrowing() external override {
        _requireCallerIsBorrowerOperations();

        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    function getBorrowingRate() public view override returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }


    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return UnboundMath._min(
            BORROWING_FEE_FLOOR + _baseRate,
            MAX_BORROWING_FEE
        );
    }

    function getBorrowingFee(uint _UNDDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _UNDDebt);
    }

    function getBorrowingFeeWithDecay(uint _UNDDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _UNDDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _UNDDebt) internal pure returns (uint) {
        return (_borrowingRate * _UNDDebt) / DECIMAL_PRECISION;
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or UND borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function updateBaseRateFromRedemption(uint _CollateralDrawn,  uint _price, uint _totalUNDSupply) external override returns (uint) {
        _requireCallerIsAccountManager();

        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn Collateral back to UND at face value rate (1 UND:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedUNDFraction = (_CollateralDrawn * _price) / _totalUNDSupply;

        uint newBaseRate = decayedBaseRate + (redeemedUNDFraction / BETA);
        newBaseRate = UnboundMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);
        
        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return UnboundMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function getRedemptionFee(uint _CollateralDrawn) external override view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _CollateralDrawn);
    }

    function getRedemptionFeeWithDecay(uint _CollateralDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _CollateralDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _CollateralDrawn) internal pure returns (uint) {
        uint redemptionFee = (_redemptionRate * _CollateralDrawn) / DECIMAL_PRECISION;
        require(redemptionFee < _CollateralDrawn, "UnboundFeesFactory: Fee would eat up all returned collateral");
        return redemptionFee;
    }

    // Restricted functions

    function setAccountManagerAddress(address _addr, bool _status) external onlyOwner{
        isAccountManagerAddress[_addr] = _status;
        emit AccountManagerUpdated(_addr, _status);
    }

    function setBorrowOpsAddress(address _addr, bool _status) external onlyOwner{
        isBorrowOperationAddress[_addr] = _status;
        emit BorrowOpsUpdated(_addr, _status);
    }

    // check if address is account manager or borrow operation address or not
    function allowed(address _account) external view returns(bool){
        return isBorrowOperationAddress[_account] || isAccountManagerAddress[_account];
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = UnboundMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return (block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(isBorrowOperationAddress[msg.sender], "UnboundFeesFactory: Caller is not the BorrowerOperations contract");
    }

    function _requireCallerIsAccountManager() internal view {
        require(isAccountManagerAddress[msg.sender], "UnboundFeesFactory: Caller is not the AccountManager contract");
    }

}
