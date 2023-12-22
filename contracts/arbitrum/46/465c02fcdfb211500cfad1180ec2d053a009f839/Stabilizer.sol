// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Stabilizer.sol ==============================
// ====================================================================

import "./ISweep.sol";
import "./UniswapAMM.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";

/**
 * @title Stabilizer
 * @author MAXOS Team - https://maxos.finance/
 * @dev Implementation:
 * Allows to take debt by minting sweep and repaying by burning sweep
 * Allows to buy and sell sweep in an AMM
 * Repayments made by burning sweep
 * EquityRatio = Junior / (Junior + Senior)
 * Requires that the EquityRatio > MinimumEquityRatio when:
 * minting => increase of the senior tranche
 * withdrawing => decrease of the junior tranche
 */
contract Stabilizer {
    // Variables
    address public borrower;
    int256 public min_equity_ratio; // Minimum Equity Ratio. 10000 is 1%
    uint256 public sweep_borrowed;
    uint256 public loan_limit;

    uint256 public call_time;
    uint256 public call_delay;
    uint256 public call_amount;

    uint256 public spread_fee; // 10000 is 1%
    uint256 public spread_date;
    uint256 public liquidator_discount; // 10000 is 1%
    bool public liquidatable;
    string public link;

    bool public settings_enabled;
    bool public frozen;

    UniswapAMM public amm;

    // Tokens
    ISweep public sweep;
    IERC20 public usdx;

    // Constants for various precisions
    uint256 private constant DAY_SECONDS = 60 * 60 * 24; // seconds of Day
    uint256 private constant TIME_ONE_YEAR = 365 * DAY_SECONDS; // seconds of Year
    uint256 private constant PRECISION = 1e6;

    /* ========== Events ========== */

    event Borrowed(uint256 indexed sweep_amount);
    event Repaid(uint256 indexed sweep_amount);
    event Withdrawn(address indexed token, uint256 indexed amount);
    event PayFee(uint256 indexed sweep_amount);
    event Bought(uint256 indexed sweep_amount);
    event Sold(uint256 indexed sweep_amount);
    event BoughtSWEEP(uint256 indexed sweep_amount);
    event SoldSWEEP(uint256 indexed usdx_amount);
    event FrozenChanged(bool indexed frozen);
    event BorrowerChanged(address indexed borrower);
    event Proposed(address indexed borrower);
    event Rejected(address indexed borrower);

    event Invested(uint256 indexed usdx_amount);
    event Divested(uint256 indexed usdx_amount);
    event Liquidated(address indexed user);

    event ConfigurationChanged(
        int256 indexed min_equity_ratio,
        uint256 indexed spread_fee,
        uint256 loan_limit,
        uint256 liquidator_discount,
        uint256 call_delay,
        bool liquidatable,
        string url_link
    );
    event StatusChanged(
        uint256 indexed current_value,
        int256 indexed equity_ratio,
        int256 indexed min_equity_ratio,
        uint256 call_time,
        uint256 call_delay,
        uint256 call_amount,
        bool is_defaulted
    );

    /* ========== Errors ========== */

    error StabilizerFrozen();
    error OnlyBorrower();
    error OnlyBalancer();
    error OnlyAdmin();
    error SettingsDisabled();
    error ZeroAddressDetected();
    error OverZero();
    error InvalidMinter();
    error NotEnoughBalance();
    error EquityRatioExcessed();
    error InvalidToken();
    error SpreadNotEnough();
    error AssetNotLiquidatable();
    error NotDefaulted();

    /* ========== Modifies ========== */

    modifier notFrozen() {
        if (frozen) revert StabilizerFrozen();
        _;
    }

    modifier onlyBorrower() {
        if (msg.sender != borrower) revert OnlyBorrower();
        _;
    }

    modifier onlyBalancer() {
        if (msg.sender != sweep.balancer()) revert OnlyBalancer();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != sweep.owner()) revert OnlyAdmin();
        _;
    }

    modifier onlySettingsEnabled() {
        if (!settings_enabled) revert SettingsDisabled();
        _;
    }

    modifier validAddress(address _addr) {
        if (_addr == address(0)) revert ZeroAddressDetected();
        _;
    }

    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert OverZero();
        _;
    }

    constructor(
        address _sweep_address,
        address _usdx_address,
        address _amm_address
    ) {
        sweep = ISweep(_sweep_address);
        usdx = IERC20(_usdx_address);
        amm = UniswapAMM(_amm_address);
        borrower = sweep.owner();
        settings_enabled = true;
        frozen = false;
    }

    /* ========== Views ========== */

    /**
     * @notice Defaulted
     * @return bool that tells if stabilizer is in default.
     */
    function isDefaulted() public view returns (bool) {
        return
            (call_amount > 0 && block.timestamp > call_time) ||
            (getEquityRatio() < min_equity_ratio);
    }

    /**
     * @notice Get Equity Ratio
     * @return the current equity ratio based in the internal storage.
     * @dev this value have a precision of 6 decimals.
     */
    function getEquityRatio() public view returns (int256) {
        return calculateEquityRatio(0, 0);
    }

    /**
     * @notice Get Spread Amount
     * fee = borrow_amount * spread_ratio * (time / time_per_year)
     * @return uint256 calculated spread amount.
     */
    function accruedFee() public view returns (uint256) {
        if (sweep_borrowed == 0) return 0;
        else {
            uint256 period = block.timestamp - spread_date;
            return
                (((sweep_borrowed * spread_fee) / PRECISION) * period) /
                TIME_ONE_YEAR;
        }
    }

    /**
     * @notice Get Debt Amount
     * debt = borrow_amount + spread fee
     * @return uint256 calculated debt amount.
     */
    function getDebt() public view returns (uint256) {
        return sweep_borrowed + accruedFee();
    }

    /**
     * @notice Get Current Value
     * @return uint256.
     */
    function currentValue() public view virtual returns (uint256) {
        (uint256 usdx_balance, uint256 sweep_balance) = _balances();
        uint256 sweep_balance_in_usdx = sweep.convertToUSDX(sweep_balance);

        return usdx_balance + sweep_balance_in_usdx;
    }

    /**
     * @notice Get Junior Tranche Value
     * @return int256 calculated junior tranche amount.
     */
    function getJuniorTrancheValue() external view returns (int256) {
        uint256 senior_tranche_in_usdx = sweep.convertToUSDX(sweep_borrowed);
        uint256 total_value = currentValue();

        return int256(total_value) - int256(senior_tranche_in_usdx);
    }

    /**
     * @notice Returns the SWEEP required to liquidate the stabilizer
     * @return uint256
     */
    function getLiquidationValue() public view returns (uint256) {
        return
            sweep.convertToSWEEP(
                (currentValue() * (1e6 - liquidator_discount)) / PRECISION
            );
    }

    /* ========== Settings ========== */

    /**
     * @notice Set Borrower - who manages the investment actions.
     * @param _borrower.
     */
    function setBorrower(address _borrower)
        external
        onlyAdmin
        validAddress(_borrower)
    {
        borrower = _borrower;
        settings_enabled = true;

        emit BorrowerChanged(_borrower);
    }

    /**
     * @notice Frozen - stops investment actions.
     * @param _frozen.
     */
    function setFrozen(bool _frozen) external onlyAdmin {
        frozen = _frozen;

        emit FrozenChanged(_frozen);
    }

    /**
     * @notice Configure intial settings
     * @param _min_equity_ratio The minimum equity ratio can be negative.
     * @param _spread_fee.
     * @param _loan_limit.
     * @param _link Url link.
     */
    function configure(
        int256 _min_equity_ratio,
        uint256 _spread_fee,
        uint256 _loan_limit,
        uint256 _liquidator_discount,
        uint256 _call_delay,
        bool _liquidatable,
        string calldata _link
    ) external onlyBorrower onlySettingsEnabled {
        min_equity_ratio = _min_equity_ratio;
        spread_fee = _spread_fee;
        loan_limit = _loan_limit;
        liquidator_discount = _liquidator_discount;
        call_delay = _call_delay;
        liquidatable = _liquidatable;
        link = _link;

        emit ConfigurationChanged(
            _min_equity_ratio,
            _spread_fee,
            _loan_limit,
            _liquidator_discount,
            _call_delay,
            _liquidatable,
            _link
        );
    }

    /**
     * @notice Changes the account that control the global configuration to the protocol/governance admin
     * @dev after disable settings by admin
     * the protocol will evaluate adding the stabilizer to the minter list.
     */
    function propose() external onlyBorrower {
        settings_enabled = false;

        emit Proposed(borrower);
    }

    /**
     * @notice Changes the account that control the global configuration to the borrower
     * @dev after enable settings for the borrower
     * he/she should edit the values to align to the protocol requirements
     */
    function reject() external onlyAdmin {
        settings_enabled = true;

        emit Rejected(borrower);
    }

    /* ========== Actions ========== */

    /**
     * @notice Borrows Sweep
     * Asks the stabilizer to mint a certain amount of sweep token.
     * @param _sweep_amount.
     * @dev Increases the sweep_borrowed (senior tranche).
     */
    function borrow(uint256 _sweep_amount)
        external
        onlyBorrower
        notFrozen
        validAmount(_sweep_amount)
    {
        if (!sweep.isValidMinter(address(this))) revert InvalidMinter();

        int256 current_equity_ratio = calculateEquityRatio(_sweep_amount, 0);
        if (current_equity_ratio < min_equity_ratio)
            revert EquityRatioExcessed();

        _payFee();
        sweep.minter_mint(address(this), _sweep_amount);
        sweep_borrowed += _sweep_amount;

        _logAction();
        emit Borrowed(_sweep_amount);
    }

    /**
     * @notice Repays Sweep
     * Burns the sweep_amount to reduce the debt (senior tranche).
     * @param _sweep_amount Amount to be burnt by Sweep.
     * @dev Decreases the sweep borrowed.
     */
    function repay(uint256 _sweep_amount)
        external
        onlyBorrower
        validAmount(_sweep_amount)
    {
        _repay(_sweep_amount);
    }

    /**
     * @notice Divests From Asset.
     * Sends balance from the asset to the STABILIZER.
     * @param _amount Amount to be divested.
     */
    function divest(uint256 _amount) public virtual onlyBorrower {}

    /**
     * @notice Pay the spread to the treasury
     */
    function payFee() external onlyBorrower {
        _payFee();
    }

    /**
     * @notice Margin Call.
     * @param _usdx_call_amount to swap for Sweep.
     */
    function marginCall(uint256 _usdx_call_amount)
        external
        onlyBalancer
        validAmount(_usdx_call_amount)
    {
        uint256 amount_to_redeem;
        uint256 missing_usdx;

        uint256 sweep_to_buy = sweep.convertToSWEEP(_usdx_call_amount);
        (uint256 usdx_balance, uint256 sweep_balance) = _balances();

        call_time = block.timestamp + call_delay;
        call_amount = _min(sweep_to_buy, sweep_borrowed);

        if (sweep_balance < call_amount) {
            uint256 missing_sweep = call_amount - sweep_balance;
            missing_usdx = sweep.convertToUSDX(missing_sweep);
            amount_to_redeem = missing_usdx - usdx_balance;
        }

        if (liquidatable && amount_to_redeem > 0) divest(amount_to_redeem);

        (usdx_balance, ) = _balances();
        uint256 amount_to_buy = _min(usdx_balance, missing_usdx);
        if (amount_to_buy > 0) _buy(amount_to_buy, 0);

        (, sweep_balance) = _balances();
        uint256 sweep_to_repay = _min(call_amount, sweep_balance);
        if (sweep_to_repay > 0) _repay(sweep_to_repay);

        _logAction();
    }

    /**
     * @notice Buy
     * Buys sweep_amount from the stabilizer's balance to the AMM (swaps USDX to SWEEP).
     * @param _usdx_amount Amount to be changed in the AMM.
     * @param _amountOutMin Minimum amount out.
     * @dev Increases the sweep balance and decrease usdx balance.
     */
    function buy(uint256 _usdx_amount, uint256 _amountOutMin)
        external
        onlyBorrower
        notFrozen
        validAmount(_usdx_amount)
        returns (uint256 sweep_amount)
    {
        sweep_amount = _buy(_usdx_amount, _amountOutMin);

        _logAction();
        emit Bought(sweep_amount);
    }

    /**
     * @notice Sell Sweep
     * Sells sweep_amount from the stabilizer's balance to the AMM (swaps SWEEP to USDX).
     * @param _sweep_amount.
     * @param _amountOutMin Minimum amount out.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function sell(uint256 _sweep_amount, uint256 _amountOutMin)
        external
        onlyBorrower
        notFrozen
        validAmount(_sweep_amount)
        returns (uint256 usdx_amount)
    {
        (, uint256 sweep_balance) = _balances();
        if (_sweep_amount > sweep_balance) _sweep_amount = sweep_balance;

        TransferHelper.safeApprove(address(sweep), address(amm), _sweep_amount);
        usdx_amount = amm.sellSweep(
            address(usdx),
            _sweep_amount,
            _amountOutMin
        );

        _logAction();
        emit Sold(_sweep_amount);
    }

    /**
     * @notice Buy Sweep with Stabilizer
     * Buys sweep_amount from the stabilizer's balance to the Borrower (swaps USDX to SWEEP).
     * @param _usdx_amount.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function buySWEEP(uint256 _usdx_amount)
        external
        onlyBorrower
        notFrozen
        validAmount(_usdx_amount)
    {
        uint256 sweep_amount = (_usdx_amount * 10**sweep.decimals()) /
            sweep.target_price();
        (, uint256 sweep_balance) = _balances();
        if (sweep_amount > sweep_balance) revert NotEnoughBalance();

        TransferHelper.safeTransferFrom(
            address(usdx),
            msg.sender,
            address(this),
            _usdx_amount
        );
        TransferHelper.safeTransfer(address(sweep), msg.sender, sweep_amount);

        _logAction();
        emit BoughtSWEEP(sweep_amount);
    }

    /**
     * @notice Sell Sweep with Stabilizer
     * Sells sweep_amount to the stabilizer (swaps SWEEP to USDX).
     * @param _sweep_amount.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function sellSWEEP(uint256 _sweep_amount)
        external
        onlyBorrower
        notFrozen
        validAmount(_sweep_amount)
    {
        uint256 usdx_amount = sweep.convertToUSDX(_sweep_amount);
        (uint256 usdx_balance, ) = _balances();
        if (usdx_amount > usdx_balance) revert NotEnoughBalance();

        TransferHelper.safeTransferFrom(
            address(sweep),
            msg.sender,
            address(this),
            _sweep_amount
        );
        TransferHelper.safeTransfer(address(usdx), msg.sender, usdx_amount);

        _logAction();
        emit SoldSWEEP(usdx_amount);
    }

    /**
     * @notice Withdraw SWEEP
     * Takes out sweep balance if the new equity ratio is higher than the minimum equity ratio.
     * @param _token.
     * @param _amount.
     * @dev Decreases the sweep balance.
     */
    function withdraw(address _token, uint256 _amount)
        external
        onlyBorrower
        notFrozen
        validAmount(_amount)
    {
        if (_token != address(sweep) && _token != address(usdx))
            revert InvalidToken();

        if (_amount > IERC20(_token).balanceOf(address(this)))
            revert NotEnoughBalance();

        if (sweep_borrowed != 0) {
            uint256 usdx_amount = _amount;
            if (_token == address(sweep))
                usdx_amount = sweep.convertToUSDX(_amount);
            int256 current_equity_ratio = calculateEquityRatio(0, usdx_amount);
            if (current_equity_ratio < min_equity_ratio)
                revert EquityRatioExcessed();
        }

        TransferHelper.safeTransfer(_token, msg.sender, _amount);

        _logAction();
        emit Withdrawn(_token, _amount);
    }

    /**
     * @notice Liquidates
     * a liquidator repays the debt in sweep and gets the same value
     * of the assets that the stabilizer holds at a discount
     */
    function _liquidate(address token) internal {
        if (!liquidatable) revert AssetNotLiquidatable();
        if (!isDefaulted()) revert NotDefaulted();

        uint256 sweep_to_liquidate = getLiquidationValue();
        (uint256 usdx_balance, uint256 sweep_balance) = _balances();
        uint256 token_balance = IERC20(token).balanceOf(address(this));
        // Gives all the assets to the liquidator first
        TransferHelper.safeTransfer(address(sweep), msg.sender, sweep_balance);
        TransferHelper.safeTransfer(address(usdx), msg.sender, usdx_balance);
        TransferHelper.safeTransfer(token, msg.sender, token_balance);

        // Takes SWEEP from the liquidator and repays as much debt as it can
        TransferHelper.safeTransferFrom(
            address(sweep),
            msg.sender,
            address(this),
            sweep_to_liquidate
        );

        _repay(_min(sweep_to_liquidate, getDebt()));

        _logAction();
        emit Liquidated(msg.sender);

    }

    function _buy(uint256 _usdx_amount, uint256 _amountOutMin)
        internal
        returns (uint256)
    {
        (uint256 usdx_balance, ) = _balances();
        if (_usdx_amount > usdx_balance) _usdx_amount = usdx_balance;

        TransferHelper.safeApprove(address(usdx), address(amm), _usdx_amount);
        uint256 sweep_amount = amm.buySweep(
            address(usdx),
            _usdx_amount,
            _amountOutMin
        );

        return sweep_amount;
    }

    function _repay(uint256 _sweep_amount) internal {
        (, uint256 sweep_balance) = _balances();
        if (_sweep_amount > sweep_balance) _sweep_amount = sweep_balance;

        uint256 spread_amount = accruedFee();
        uint256 sweep_amount = _sweep_amount - spread_amount;
        if (sweep_borrowed < sweep_amount) {
            sweep_amount = sweep_borrowed;
            sweep_borrowed = 0;
        } else {
            sweep_borrowed -= sweep_amount;
        }
        TransferHelper.safeTransfer(
            address(sweep),
            sweep.treasury(),
            spread_amount
        );

        call_amount = call_amount > _sweep_amount
            ? (call_amount - _sweep_amount)
            : 0;

        TransferHelper.safeApprove(address(sweep), address(this), sweep_amount);
        spread_date = block.timestamp;
        sweep.minter_burn_from(sweep_amount);

        emit Repaid(sweep_amount);
    }

    function _payFee() internal {
        uint256 spread_amount = accruedFee();
        (, uint256 sweep_balance) = _balances();
        if (spread_amount > sweep_balance) revert SpreadNotEnough();

        if (spread_amount != 0) {
            TransferHelper.safeTransfer(
                address(sweep),
                sweep.treasury(),
                spread_amount
            );
        }
        spread_date = block.timestamp;

        emit PayFee(spread_amount);
    }

    /**
     * @notice Calculate Equity Ratio
     * Calculated the equity ratio based on the internal storage.
     * @param _sweep_delta Variation of SWEEP to recalculate the new equity ratio.
     * @param _usdx_delta Variation of USDX to recalculate the new equity ratio.
     * @return the new equity ratio used to control the Mint and Withdraw functions.
     * @dev Current Equity Ratio percentage has a precision of 4 decimals.
     */
    function calculateEquityRatio(uint256 _sweep_delta, uint256 _usdx_delta)
        internal
        view
        returns (int256)
    {
        uint256 current_value = currentValue();
        uint256 sweep_delta_in_usdx = sweep.convertToUSDX(_sweep_delta);
        uint256 senior_tranche_in_usdx = sweep.convertToUSDX(
            sweep_borrowed + _sweep_delta
        );
        uint256 total_value = current_value + sweep_delta_in_usdx - _usdx_delta;

        if (total_value == 0) return 0;

        // 1e6 is decimals of the percentage result
        int256 current_equity_ratio = ((int256(total_value) -
            int256(senior_tranche_in_usdx)) * 1e6) / int256(total_value);

        if (current_equity_ratio < -1e6) current_equity_ratio = -1e6;

        return current_equity_ratio;
    }

    /**
     * @notice Get Balances of the usdx and sweep.
     **/
    function _balances()
        internal
        view
        returns (uint256 usdx_balance, uint256 sweep_balance)
    {
        usdx_balance = usdx.balanceOf(address(this));
        sweep_balance = sweep.balanceOf(address(this));
    }

    /**
     * @notice Get minimum value between a and b.
     **/
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a < b) ? a : b;
    }

    /**
     * @notice Events Log.
     **/
    function _logAction() internal {
        emit StatusChanged(
            currentValue(),
            getEquityRatio(),
            min_equity_ratio,
            call_time,
            call_delay,
            call_amount,
            isDefaulted()
        );
    }

    // function _collect(address _to) internal virtual {}
    // function _liquidate(address _to) internal virtual {}
}

