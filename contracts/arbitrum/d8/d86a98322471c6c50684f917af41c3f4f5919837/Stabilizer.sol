// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Stabilizer.sol ==============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./IStabilizer.sol";
import "./ISweep.sol";
import "./IAsset.sol";
import "./UniswapAMM.sol";
import "./ERC20.sol";
import "./PRBMathSD59x18.sol";
import "./TransferHelper.sol";

/**
 * @title Stabilizer
 * @author MAXOS Team - https://maxos.finance/
 * @dev Implementation:
 * Facilitates the investment and paybacks of off-chain & on-chain assets
 * Allows to deposit and withdraw usdx
 * Allows to take debt by minting sweep and repaying by burning sweep
 * Allows to buy and sell sweep in an AMM
 * Repayments made by burning sweep
 * EquityRatio = Junior / (Junior + Senior)
 * Requires that the EquityRatio > MinimumEquityRatio when:
 * minting => increase of the senior tranche
 * withdrawing => decrease of the junior tranche
 */
contract Stabilizer is IStabilizer {
    using PRBMathSD59x18 for int256;

    uint256 public sweep_borrowed;
    uint256 public minimum_equity_ratio;
    uint256 public loan_limit;
    uint256 public repayment_date;
    string public link;

    // Investment Asset
    IAsset public asset;
    UniswapAMM public amm;

    address public borrower;
    address public settings_manager;

    // Spread Variables
    uint256 public spread_ratio; // 100 is 1%
    uint256 public spread_payment_time;

    // Tokens
    ISweep public sweep;
    ERC20 public usdx;

    // Control
    bool public frozen;

    // Constants for various precisions
    uint256 private constant DAY_SECONDS = 60 * 60 * 24; // seconds per days
    uint256 private constant TIME_ONE_YEAR = 365 * DAY_SECONDS; // seconds per Year
    uint256 private constant SPREAD_PRECISION = 1e5;

    constructor(
        address _sweep_address,
        address _usdx_address,
        uint256 _min_equity_ratio,
        uint256 _spread_ratio,
        address _amm_address
    ) {
        sweep = ISweep(_sweep_address);
        usdx = ERC20(_usdx_address);
        amm = UniswapAMM(_amm_address);
        borrower = sweep.owner();
        settings_manager = borrower;
        minimum_equity_ratio = _min_equity_ratio;
        spread_ratio = _spread_ratio;
        frozen = false;
    }

    // EVENTS ====================================================================

    event Minted(uint256 indexed sweep_amount);
    event Invested(uint256 indexed amount0, uint256 indexed amount1);
    event Paidback(uint256 indexed amount);
    event Burnt(uint256 indexed sweep_amount);
    event Withdrawn(address indexed token, uint256 indexed amount);
    event Collected(address indexed owner);
    event PaySpread(uint256 indexed sweep_amount);
    event Liquidate(address indexed user);
    event Bought(uint256 indexed sweep_amount);
    event Sold(uint256 indexed sweep_amount);
    event BoughtSWEEP(uint256 indexed sweep_amount);
    event SoldSWEEP(uint256 indexed usdx_amount);
    event FrozenChanged(bool indexed frozen);
    event BorrowerChanged(address indexed borrower);
    event Proposed(address indexed borrower);
    event Rejected(address indexed borrower);
    event SpreadRatioChanged(uint256 indexed spread_ratio);
    event RepaymentDateChanged(uint256 indexed repayment_date);
    event LoanLimitChanged(uint256 indexed loan_limit);
    event UsdxChanged(address indexed usdx_address);
    event AssetChanged(address indexed asset);
    event MinimumEquityRatioChanged(uint256 indexed minimum_equity_ratio);
    event ConfigurationChanged(
        address indexed asset,
        uint256 indexed minimum_equity_ratio,
        uint256 indexed spread_ratio,
        uint256 loan_limit,
        string url_link
    );
    event LinkChanged(string indexed link);

    // ERRORS ====================================================================

    error StabilizerFrozen();
    error OnlyBorrower();
    error OnlyBalancer();
    error OnlyAdmin();
    error OnlySettingsManager();
    error ZeroAddressDetected();
    error OverZero();
    error InvalidMinter();
    error NotEnoughBalance();
    error EquityRatioExcessed();
    error InvalidToken();
    error NotDefaulted();
    error DebtNotYetPaid();
    error SpreadNotEnough();

    // MODIFIERS =================================================================

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

    modifier onlySettingsManager() {
        if (msg.sender != settings_manager) revert OnlySettingsManager();
        _;
    }

    // ADMIN FUNCTIONS ===========================================================

    /**
     * @notice Set Borrower - who manages the investment actions.
     * @param _borrower.
     */
    function setBorrower(address _borrower) external onlyAdmin {
        if (_borrower == address(0)) revert ZeroAddressDetected();
        borrower = _borrower;
        settings_manager = _borrower;
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
     * @notice set Default Date.
     * @param _days_from_now.
     */
    function setRepaymentDate(uint32 _days_from_now) external onlyBalancer {
        repayment_date = block.timestamp + (_days_from_now * DAY_SECONDS);
        emit RepaymentDateChanged(repayment_date);
    }

    /**
     * @notice set loan limit.
     * @param _loan_limit.
     */
    function setLoanLimit(uint256 _loan_limit) external {
        require(msg.sender == sweep.balancer() || msg.sender == settings_manager, "not balancer or settings manager");
        loan_limit = _loan_limit;
        emit LoanLimitChanged(_loan_limit);
    }

    // SETTINGS FUNCTIONS ====================================================

    /**
     * @notice Configure intial settings
     * @param _asset Address
     * @param _minimum_equity_ratio.
     * @param _spread_ratio.
     * @param _loan_limit.
     * @param _url_link.
     */
    function configure(
        address _asset,
        uint256 _minimum_equity_ratio,
        uint256 _spread_ratio,
        uint256 _loan_limit,
        string calldata _url_link
    ) external onlySettingsManager {
        if (_asset == address(0)) revert ZeroAddressDetected();
        if (_minimum_equity_ratio == 0 || _spread_ratio == 0) revert OverZero();
        asset = IAsset(_asset);
        minimum_equity_ratio = _minimum_equity_ratio;
        spread_ratio = _spread_ratio;
        loan_limit = _loan_limit;
        link = _url_link;
        emit ConfigurationChanged(
            _asset,
            _minimum_equity_ratio,
            _spread_ratio,
            _loan_limit,
            _url_link
        );
    }

    /**
     * @notice Update Link
     * @param _link New link.
     */
    function setLink(string calldata _link) external onlySettingsManager {
        link = _link;
        emit LinkChanged(_link);
    }

    /**
     * @notice Set Asset to invest. This can be an On-Chain or Off-Chain asset.
     * @param _asset Address
     */
    function setAsset(address _asset) external onlySettingsManager {
        if (_asset == address(0)) revert ZeroAddressDetected();
        asset = IAsset(_asset);
        emit AssetChanged(_asset);
    }

    /**
     * @notice Set Minimum Equity Ratio that defines the junior tranche size.
     * @param _minimum_equity_ratio New minimum equity ratio.
     * @dev this value is a percentage with 6 decimals.
     */
    function setMinimumEquityRatio(
        uint256 _minimum_equity_ratio
    ) external onlySettingsManager {
        if (_minimum_equity_ratio == 0) revert OverZero();
        minimum_equity_ratio = _minimum_equity_ratio;
        emit MinimumEquityRatioChanged(_minimum_equity_ratio);
    }

    /**
     * @notice Set Spread Ratio that will be used to calculate the spread that we owe to the protocol.
     * @param _spread_ratio spread ratio.
     */
    function setSpreadRatio(
        uint256 _spread_ratio
    ) external onlySettingsManager {
        if (_spread_ratio == 0) revert OverZero();
        spread_ratio = _spread_ratio;
        emit SpreadRatioChanged(_spread_ratio);
    }

    /**
     * @notice Changes the account that control the global configuration to the protocol/governance admin
     * @dev after delegating the settings management to the admin
     * the protocol will evaluate adding the stabilizer to the minter list.
     */
    function propose() external onlySettingsManager {
        settings_manager = sweep.owner();
        emit Proposed(borrower);
    }

    /**
     * @notice Changes the account that control the global configuration to the borrower
     * @dev after assigning the settings management to the borrower
     * he/she should edit the values to align to the protocol requirements
     */
    function reject() external onlySettingsManager {
        settings_manager = borrower;
        emit Rejected(borrower);
    }

    // BORROWER FUNCTIONS ==========================================================

    /**
     * @notice Mint Sweep
     * Asks the stabilizer to mint a certain amount of sweep token.
     * @param _sweep_amount.
     * @dev Increases the sweep_borrowed (senior tranche).
     */
    function mint(uint256 _sweep_amount) external onlyBorrower notFrozen {
        if (_sweep_amount == 0) revert OverZero();
        if (!sweep.isValidMinter(address(this))) revert InvalidMinter();

        uint256 sweep_available = loan_limit - sweep_borrowed;
        if (sweep_available < _sweep_amount) revert NotEnoughBalance();
        uint256 current_equity_ratio = calculateEquityRatio(_sweep_amount, 0);
        if (current_equity_ratio < minimum_equity_ratio)
            revert EquityRatioExcessed();

        _paySpread();
        sweep.minter_mint(address(this), _sweep_amount);
        sweep_borrowed += _sweep_amount;

        emit Minted(_sweep_amount);
    }

    /**
     * @notice Burn
     * Burns the sweep_amount to reduce the debt (senior tranche).
     * @param _sweep_amount Amount to be burnt by Sweep.
     * @dev Decreases the sweep borrowed.
     */
    function burn(uint256 _sweep_amount) external onlyBorrower {
        if (_sweep_amount == 0) revert OverZero();
        if (_sweep_amount > sweep.balanceOf((address(this))))
            revert NotEnoughBalance();
        _burn(_sweep_amount);
    }

    /**
     * @notice Repay debt
     * takes sweep from the sender and burns it
     * @param _sweep_amount Amount to be burnt by Sweep.
     */
    function repay(uint256 _sweep_amount) public {
        if (_sweep_amount == 0) revert OverZero();
        TransferHelper.safeTransferFrom(
            address(sweep),
            msg.sender,
            address(this),
            _sweep_amount
        );
        _burn(_sweep_amount);
    }

    /**
     * @notice Invest USDX
     * Sends balances from the STABILIZER to the asset address.
     * @param _amount0 USDX Amount to be invested.
     * @param _amount1 Sweep Amount to be invested.
     */
    function invest(
        uint256 _amount0,
        uint256 _amount1
    ) external onlyBorrower notFrozen {
        if (_amount0 > usdx.balanceOf(address(this)))
            revert NotEnoughBalance();
        if (_amount1 > sweep.balanceOf(address(this)))
            revert NotEnoughBalance();

        TransferHelper.safeApprove(address(usdx), address(asset), _amount0);
        TransferHelper.safeApprove(address(sweep), address(asset), _amount1);

        asset.deposit(_amount0, _amount1);

        emit Invested(_amount0, _amount1);
    }

    /**
     * @notice Payback USDX
     * Sends balance from the asset to the STABILIZER.
     * @param _usdx_amount Amount to be repaid.
     */
    function payback(uint256 _usdx_amount) external onlyBorrower {
        if (_usdx_amount == 0) revert OverZero();
        asset.withdraw(_usdx_amount);

        emit Paidback(_usdx_amount);
    }

    /**
     * @notice Collect Rewards
     * Takes the rewards generated by the asset (On-Chain only).
     * @dev Rewards are sent to the borrower.
     */
    function collect() external onlyBorrower {
        asset.withdrawRewards(borrower);

        emit Collected(borrower);
    }

    /**
     * @notice Pay the spread to the treasury
     */
    function paySpread() external onlyBorrower {
        _paySpread();
    }

    /**
     * @notice Liquidates a stabilizer
     * takes ownership of the stabilizer by repaying its debt
     */
    function liquidate(uint256 sweep_amount) external {
        if (!isDefaulted()) revert NotDefaulted();
        repay(sweep_amount);
        if (sweep_borrowed != 0) revert DebtNotYetPaid();
        borrower = msg.sender;

        emit Liquidate(msg.sender);
    }

    function _burn(uint256 _sweep_amount) internal {
        uint256 spread_amount = getSpreadValue();
        if (spread_amount > sweep.balanceOf(address(this)))
            revert SpreadNotEnough();

        uint256 sweep_amount = _sweep_amount - spread_amount;
        if (sweep_borrowed < sweep_amount) {
            sweep_amount = sweep_borrowed;
            sweep_borrowed = 0;
        } else {
            sweep_borrowed -= sweep_amount;
        }
        address sweep_address = address(sweep);
        TransferHelper.safeTransfer(
            sweep_address,
            sweep.treasury(),
            spread_amount
        );
        spread_payment_time = block.timestamp;
        TransferHelper.safeApprove(sweep_address, address(this), sweep_amount);
        sweep.minter_burn_from(sweep_amount);

        emit Burnt(sweep_amount);
    }

    function _paySpread() internal {
        uint256 spread_amount = getSpreadValue();
        if (spread_amount > sweep.balanceOf(address(this)))
            revert SpreadNotEnough();

        if (spread_amount != 0) {
            TransferHelper.safeTransfer(
                address(sweep),
                sweep.treasury(),
                spread_amount
            );
        }
        spread_payment_time = block.timestamp;

        emit PaySpread(spread_amount);
    }

    /**
     * @notice Buy
     * Buys sweep_amount from the stabilizer's balance to the AMM (swaps USDX to SWEEP).
     * @param _usdx_amount Amount to be changed in the AMM.
     * @param _amountOutMin Minimum amount out.
     * @dev Increases the sweep balance and decrease usdx balance.
     */
    function buy(
        uint256 _usdx_amount,
        uint256 _amountOutMin
    ) external onlyBorrower notFrozen returns (uint256 sweep_amount) {
        if (_usdx_amount == 0) revert OverZero();
        if (_usdx_amount > usdx.balanceOf(address(this)))
            revert NotEnoughBalance();
        address usdx_address = address(usdx);
        TransferHelper.safeApprove(usdx_address, address(amm), _usdx_amount);
        sweep_amount = amm.buySweep(usdx_address, _usdx_amount, _amountOutMin);

        emit Bought(sweep_amount);
    }

    /**
     * @notice Sell Sweep
     * Sells sweep_amount from the stabilizer's balance to the AMM (swaps SWEEP to USDX).
     * @param _sweep_amount.
     * @param _amountOutMin Minimum amount out.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function sell(
        uint256 _sweep_amount,
        uint256 _amountOutMin
    ) external onlyBorrower notFrozen returns (uint256 usdx_amount) {
        if (_sweep_amount == 0) revert OverZero();
        if (_sweep_amount > sweep.balanceOf(address(this)))
            revert NotEnoughBalance();

        TransferHelper.safeApprove(address(sweep), address(amm), _sweep_amount);
        usdx_amount = amm.sellSweep(
            address(usdx),
            _sweep_amount,
            _amountOutMin
        );

        emit Sold(_sweep_amount);
    }

    /**
     * @notice Buy Sweep with Stabilizer
     * Buys sweep_amount from the stabilizer's balance to the Borrower (swaps USDX to SWEEP).
     * @param _usdx_amount.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function buySWEEP(uint256 _usdx_amount) external onlyBorrower notFrozen {
        if (_usdx_amount == 0) revert OverZero();

        uint256 sweep_amount = (_usdx_amount * 10 ** sweep.decimals()) /
            sweep.target_price();
        if (sweep_amount > sweep.balanceOf(address(this)))
            revert NotEnoughBalance();

        TransferHelper.safeTransferFrom(
            address(usdx),
            msg.sender,
            address(this),
            _usdx_amount
        );
        TransferHelper.safeTransfer(address(sweep), msg.sender, sweep_amount);

        emit BoughtSWEEP(sweep_amount);
    }

    /**
     * @notice Sell Sweep with Stabilizer
     * Sells sweep_amount to the stabilizer (swaps SWEEP to USDX).
     * @param _sweep_amount.
     * @dev Decreases the sweep balance and increase usdx balance
     */
    function sellSWEEP(uint256 _sweep_amount) external onlyBorrower notFrozen {
        if (_sweep_amount == 0) revert OverZero();

        uint256 usdx_amount = SWEEPinUSDX(_sweep_amount);
        if (usdx_amount > usdx.balanceOf(address(this)))
            revert NotEnoughBalance();

        TransferHelper.safeTransferFrom(
            address(sweep),
            msg.sender,
            address(this),
            _sweep_amount
        );
        TransferHelper.safeTransfer(address(usdx), msg.sender, usdx_amount);

        emit SoldSWEEP(usdx_amount);
    }

    /**
     * @notice Withdraw SWEEP
     * Takes out sweep balance if the new equity ratio is higher than the minimum equity ratio.
     * @param token.
     * @dev Decreases the sweep balance.
     */
    function withdraw(
        address token,
        uint256 amount
    ) external onlyBorrower notFrozen {
        if (amount == 0) revert OverZero();
        address sweep_address = address(sweep);
        if (token != sweep_address && token != address(usdx))
            revert InvalidToken();
        if (amount > ERC20(token).balanceOf(address(this)))
            revert NotEnoughBalance();

        if (sweep_borrowed != 0) {
            if (token == sweep_address) amount = SWEEPinUSDX(amount);
            uint256 current_equity_ratio = calculateEquityRatio(0, amount);
            if (current_equity_ratio < minimum_equity_ratio)
                revert EquityRatioExcessed();
        }

        TransferHelper.safeTransfer(token, msg.sender, amount);

        emit Withdrawn(token, amount);
    }

    // GETTERS ===================================================================

    /**
     * @notice Calculate Equity Ratio
     * Calculated the equity ratio based on the internal storage.
     * @param sweep_delta Variation of SWEEP to recalculate the new equity ratio.
     * @param usdx_delta Variation of USDX to recalculate the new equity ratio.
     * @return the new equity ratio used to control the Mint and Withdraw functions.
     * @dev Current Equity Ratio percentage has a precision of 6 decimals.
     */
    function calculateEquityRatio(
        uint256 sweep_delta,
        uint256 usdx_delta
    ) internal view returns (uint256) {
        uint256 sweep_balance = sweep.balanceOf(address(this));
        uint256 usdx_balance = usdx.balanceOf(address(this));
        uint256 sweep_balance_in_usdx = SWEEPinUSDX(
            sweep_balance + sweep_delta
        );
        uint256 senior_tranche_in_usdx = SWEEPinUSDX(
            sweep_borrowed + sweep_delta
        );
        uint256 total_value = asset.currentValue() +
            usdx_balance +
            sweep_balance_in_usdx -
            usdx_delta;

        if (total_value == 0 || total_value <= senior_tranche_in_usdx) return 0;

        // 1e6 is decimals of the percentage result
        uint256 current_equity_ratio = ((total_value - senior_tranche_in_usdx) *
            100e6) / total_value;

        return current_equity_ratio;
    }

    /**
     * @notice Get Equity Ratio
     * @return the current equity ratio based in the internal storage.
     * @dev this value have a precision of 6 decimals.
     */
    function getEquityRatio() public view returns (uint256) {
        return calculateEquityRatio(0, 0);
    }

    /**
     * @notice Defaulted
     * @return bool that tells if stabilizer is in default.
     */
    function isDefaulted() public view returns (bool) {
        return
            (block.timestamp > repayment_date && sweep_borrowed > loan_limit) ||
            (getEquityRatio() < minimum_equity_ratio) ||
            IAsset(asset).isDefaulted();
    }

    /**
     * @notice Get Junior Tranche Value
     * @return int calculated junior tranche amount.
     */
    function getJuniorTrancheValue() external view returns (int256) {
        uint256 sweep_balance = sweep.balanceOf(address(this));
        uint256 usdx_balance = usdx.balanceOf(address(this));
        uint256 sweep_balance_in_usdx = SWEEPinUSDX(sweep_balance);
        uint256 senior_tranche_in_usdx = SWEEPinUSDX(sweep_borrowed);
        uint256 total_value = asset.currentValue() +
            usdx_balance +
            sweep_balance_in_usdx;

        return int256(total_value) - int256(senior_tranche_in_usdx);
    }

    /**
     * @notice Get Spread Amount
     * r: interest rate per year
     * t: time period we pay the rate
     * y: time in one year
     * v: starting value
     * new v = v * (1 + r) ^ (t / y);
     * @return uint calculated spread amount.
     */
    function getSpreadValue() public view returns (uint256) {
        if (sweep_borrowed == 0) return 0;
        else {
            int256 sp_ratio = int256(SPREAD_PRECISION + spread_ratio).fromInt();
            int256 period = int256(block.timestamp - spread_payment_time)
                .fromInt();
            int256 year = int256(TIME_ONE_YEAR).fromInt();
            int256 sp_prec = int256(SPREAD_PRECISION).fromInt();
            int256 time_ratio = period.div(year);
            int256 sp_unit = sp_ratio.pow(time_ratio).div(
                sp_prec.pow(time_ratio)
            );

            return
                (sweep_borrowed * uint256(sp_unit)) /
                (10 ** sweep.decimals()) -
                sweep_borrowed;
        }
    }

    /**
     * @notice SWEEP in USDX
     * Calculate the amount of USDX that are equivalent to the SWEEP input.
     * @param amount Amount of SWEEP.
     * @return amount of USDX.
     * @dev 1e6 = PRICE_PRECISION
     */
    function SWEEPinUSDX(uint256 amount) internal view returns (uint256) {
        return
            (amount * sweep.target_price() * (10 ** usdx.decimals())) /
            (10 ** sweep.decimals() * 1e6);
    }
}

