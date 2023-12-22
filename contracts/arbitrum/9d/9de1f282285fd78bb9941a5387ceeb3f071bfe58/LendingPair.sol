// SPDX-License-Identifier: UNLICENSED

// Copyright (c) FloraLoans - All rights reserved
// https://twitter.com/Flora_Loans

pragma solidity 0.8.19;

import "./Address.sol";
import "./Math.sol";
import "./Clones.sol";
import "./ReentrancyGuard.sol";
import "./extensions_IERC20Metadata.sol";

import "./LPTokenMaster.sol";
import "./TransferHelper.sol";
import "./LendingPairEvents.sol";

import "./ICallee.sol";
import "./ILendingPair.sol";
import "./ILPTokenMaster.sol";
import "./ILendingController.sol";

/// @title Lending Pair Contract
/// @author 0xdev and flora.loans
/// @notice This contract contains all functionality of an effective LendingPair, including deposit, borrow, withdraw and the liquidation mechanism

contract LendingPair is
    ILendingPair,
    LendingPairEvents,
    ReentrancyGuard,
    TransferHelper
{
    using Address for address;
    using Clones for address;

    struct InterestRateModel {
        uint256 lpRate;
        uint256 minRate;
        uint256 lowRate;
        uint256 highRate;
        uint256 targetUtilization;
    }

    struct AccountingData {
        uint256 totalSupplyShares;
        uint256 totalSupplyAmount;
        uint256 totalDebtShares;
        uint256 totalDebtAmount;
        mapping(address token => uint256) supplySharesOf;
        mapping(address token => uint256) debtSharesOf;
    }

    /// CONSTANTS
    uint256 public constant LIQ_MIN_HEALTH = 1e18;
    uint256 private constant MIN_DECIMALS = 6;
    address public feeRecipient;
    ILendingController public lendingController;

    /// Token related
    address public override tokenA;
    address public override tokenB;
    mapping(address token => uint256) private _decimals;
    mapping(address token => uint256) public colFactor;
    mapping(address token => address) public override lpToken;
    mapping(address token => uint256) public override pendingSystemFees;
    mapping(address token => uint256) public lastBlockAccrued;

    /// Protocol
    InterestRateModel public irm;
    mapping(address token => AccountingData) internal _accounting;

    /// Modifier
    modifier onlyLpToken() {
        require(
            lpToken[tokenA] == msg.sender || lpToken[tokenB] == msg.sender,
            "LendingController: caller must be LP token"
        );
        _;
    }
    modifier onlyOwner() {
        require(
            msg.sender == lendingController.owner(),
            "LendingPair: caller is not the owner"
        );
        _;
    }

    constructor(IWETH _WETH) TransferHelper(_WETH) {}

    /// =======================================================================
    /// ======================= INIT ==========================================
    /// =======================================================================

    /// @notice called once by the PairFactory after the creation of a new Pair
    /// @param _lpTokenMaster address to the implementation
    /// @param _lendingController LendingController
    /// @param _feeRecipient receiver of protocol fees
    /// @param _tokenA first pair token (base asset)
    /// @param _tokenB second pair token (user asset)
    function initialize(
        address _lpTokenMaster,
        address _lendingController,
        address _feeRecipient,
        address _tokenA,
        address _tokenB
    ) external override {
        require(tokenA == address(0), "LendingPair: already initialized");

        lendingController = ILendingController(_lendingController);

        feeRecipient = _feeRecipient;
        tokenA = _tokenA;
        tokenB = _tokenB;
        lastBlockAccrued[tokenA] = block.number;
        lastBlockAccrued[tokenB] = block.number;

        _decimals[tokenA] = IERC20Metadata(tokenA).decimals();
        _decimals[tokenB] = IERC20Metadata(tokenB).decimals();

        require(
            _decimals[tokenA] >= MIN_DECIMALS &&
                _decimals[tokenB] >= MIN_DECIMALS,
            "LendingPair: MIN_DECIMALS"
        );

        lpToken[tokenA] = _createLpToken(_lpTokenMaster, tokenA);
        lpToken[tokenB] = _createLpToken(_lpTokenMaster, tokenB);

        // Setting the collateral factor
        uint256 colFactorTokenA = lendingController.colFactor(_tokenA);
        uint256 colFactorTokenB = lendingController.colFactor(_tokenB);
        uint256 defaultCollateralFactor = lendingController.defaultColFactor();

        colFactor[_tokenA] = colFactorTokenA != 0
            ? colFactorTokenA
            : defaultCollateralFactor;
        colFactor[_tokenB] = colFactorTokenB != 0
            ? colFactorTokenB
            : defaultCollateralFactor;

        // Initialize Interest rate model
        // Need to check then if calculations still match with new units
        irm.lpRate = 70e18; // Percentage of debt-interest received by the suppliers
        irm.minRate = 0;
        irm.lowRate = 7_642_059_868_087; // 20%
        irm.highRate = 382_102_993_404_363; // 1,000%
        irm.targetUtilization = 90e18; // Must be < 100e18;
    }

    ///
    ///
    /// =======================================================================
    /// ======================= USER CORE ACTIONS =============================
    /// =======================================================================
    ///
    ///

    /// @notice deposit either tokenA or tokenB
    /// @param _account address of the account to credit the deposit to
    /// @param _token token to deposit
    /// @param _amount amount to deposit
    function deposit(
        address _account,
        address _token,
        uint256 _amount
    ) external payable nonReentrant {
        if (msg.value > 0) {
            _depositWeth();
            _safeTransfer(address(WETH), msg.sender, msg.value);
        }
        _deposit(_account, _token, _amount);
    }

    /// @notice withdraw either tokenA or tokenB
    /// @param _recipient address of the account receiving the tokens
    /// @param _token token to withdraw
    /// @param _amount amount to withdraw
    function withdraw(
        address _recipient,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        _withdraw(_recipient, _token, _amount);
        _checkAccountHealth(msg.sender);
        _checkReserve(_token);
    }

    /// @notice withdraw the whole amount of either tokenA or tokenB
    /// @param _recipient address of the account to transfer the tokens to
    /// @param _token token to withdraw
    function withdrawAll(
        address _recipient,
        address _token
    ) external nonReentrant {
        _withdrawAll(_recipient, _token);
        _checkAccountHealth(msg.sender);
        _checkReserve(_token);
    }

    /// @notice borrow either tokenA or tokenB
    /// @param _recipient address of the account to transfer the tokens to
    /// @param _token token to borrow
    /// @param _amount amount to borrow
    function borrow(
        address _recipient,
        address _token,
        uint256 _amount
    ) external nonReentrant {
        _borrow(_recipient, _token, _amount);
        _checkAccountHealth(msg.sender);
        _checkReserve(_token);
    }

    /// @notice repay either tokenA or tokenB
    /// @param _account address of the account to reduce the debt for
    /// @param _token token to repay
    /// @param _maxAmount maximum amount willing to repay
    /// @dev debt can increase due to accrued interest
    function repay(
        address _account,
        address _token,
        uint256 _maxAmount
    ) external payable nonReentrant {
        if (msg.value > 0) {
            _depositWeth();
            _safeTransfer(address(WETH), msg.sender, msg.value);
        }
        _repay(_account, _token, _maxAmount);
    }

    ///
    ///
    /// =======================================================================
    /// ======================= USER ADVANCED ACTIONS =========================
    /// =======================================================================
    ///
    ///

    /// @notice transfers tokens _from -> _to
    /// @dev Non erc20 compliant, but can be wrapped by an erc20 interface
    function transferLp(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external override onlyLpToken {
        require(
            _accounting[_token].debtSharesOf[_to] == 0,
            "LendingPair: cannot receive borrowed token"
        );
        _accounting[_token].supplySharesOf[_from] -= _amount;
        _accounting[_token].supplySharesOf[_to] += _amount;
        _checkAccountHealth(_from);
    }

    /// @notice Liquidate an account to help maintain the protocol's healthy debt position.
    /// @param _account The user account to be liquidated.
    /// @param _repayToken The token which was borrowed by the user and is now in debt
    /// @param _repayAmount The amount of debt to be repaid.
    /// @param _amountOutMin The minimum amount of collateral expected to be received by the liquidator.
    function liquidateAccount(
        address _account,
        address _repayToken,
        uint256 _repayAmount,
        uint256 _amountOutMin
    ) external nonReentrant {
        _liquidateAccount(_account, _repayToken, _repayAmount, _amountOutMin);
        _checkAccountHealth(msg.sender);
        _checkReserve(tokenA);
        _checkReserve(tokenB);
    }

    ///
    ///
    /// =======================================================================
    /// ======================= ADMIN & PROTOCOL ACTIONS ======================
    /// =======================================================================
    ///
    ///

    /// @notice transfer the current pending fees (protocol fees) to the feeRecipient
    /// @param _token token to collect fees
    /// @param _amount fee amount to collect
    function collectSystemFee(
        address _token,
        uint256 _amount
    ) external nonReentrant {
        _validateToken(_token);
        _amount = pendingSystemFees[_token] > _amount
            ? pendingSystemFees[_token]
            : _amount;
        pendingSystemFees[_token] -= _amount;
        _safeTransfer(_token, feeRecipient, _amount);
        _checkReserve(_token);
        emit CollectSystemFee(_token, _amount);
    }

    /// @notice charge interest on debt and add interest to supply
    /// @dev first accrueDebt, then credit a proportion of the newDebt to the totalSupply
    /// @dev the other part of newDebt is credited to pendingSystemFees
    /// @param _token token to be accrued
    function accrue(address _token) public {
        if (lastBlockAccrued[_token] < block.number) {
            uint256 newDebt = _accrueDebt(_token);
            uint256 newSupply = (newDebt * irm.lpRate) / 100e18;
            _accounting[_token].totalSupplyAmount += newSupply;

            // @Note rounding errors should not exsits anymore, but leave it here to be save
            // '-1' helps prevent _checkReserve fails due to rounding errors
            uint256 newFees = (newDebt - newSupply) == 0
                ? 0
                : (newDebt - newSupply - 1);
            pendingSystemFees[_token] += newFees;

            lastBlockAccrued[_token] = block.number;
        }
    }

    ///
    /// =======================================================================
    /// ======================= SETTER functions ==============================
    /// =======================================================================
    ///

    /// @notice change the collateral factor for a token
    /// @param _token token
    /// @param _value newColFactor
    function setColFactor(address _token, uint256 _value) external onlyOwner {
        require(_value <= 99e18, "LendingPair: _value <= 99e18");
        uint256 oldValue = colFactor[_token];
        _validateToken(_token);
        colFactor[_token] = _value;
        emit ColFactorSet(_token, oldValue, _value);
    }

    /// @notice sets the lpRate
    /// @notice lpRate defines the amount of interest going to the lendingPair -> liquidity providers
    /// @dev remaining percent goes to the feeRecipient -> protocol
    /// @dev 1e18 = 1%
    /// @param _lpRate new lpRate
    function setlpRate(uint256 _lpRate) external onlyOwner {
        uint256 oldLpRate = irm.lpRate;
        require(_lpRate != 0, "LendingPair: LP rate cannot be zero");
        require(_lpRate <= 100e18, "LendingPair: LP rate cannot be gt 100");
        irm.lpRate = _lpRate;
        emit LpRateSet(oldLpRate, _lpRate);
    }

    /// @notice Set the parameters of the interest rate model
    /// @dev The target utilization must be less than 100e18
    /// @param _minRate The minimum interest rate for the model, usually when utilization is 0
    /// @param _lowRate The interest rate at the low utilization boundary
    /// @param _highRate The interest rate at the high utilization boundary
    /// @param _targetUtilization The target utilization rate as a percentage, represented as a number between 0 and 100e18
    function setInterestRateModel(
        uint256 _minRate,
        uint256 _lowRate,
        uint256 _highRate,
        uint256 _targetUtilization
    ) external onlyOwner {
        require(
            _targetUtilization < 100e18,
            "Target Utilization must be < 100e18"
        );
        InterestRateModel memory oldIrm = irm;
        irm.minRate = _minRate;
        irm.lowRate = _lowRate;
        irm.highRate = _highRate;
        irm.targetUtilization = _targetUtilization;

        emit InterestRateParametersSet(
            oldIrm.minRate,
            oldIrm.lowRate,
            oldIrm.highRate,
            oldIrm.targetUtilization,
            irm.minRate,
            irm.lowRate,
            irm.highRate,
            irm.targetUtilization
        );
    }

    ///
    ///
    /// =======================================================================
    /// ======================= ADVANCED GETTER ===============================
    /// =======================================================================
    ///
    ///

    /// @notice Unit conversion. Get the amount of borrowed tokens and convert it to the same value of _returnToken
    /// @param _account The address of the account for which the borrowed balance will be retrieved and converted
    /// @param _borrowedToken The address of the token that has been borrowed
    /// @param _returnToken The address of the token to which the borrowed balance will be converted
    /// @return The borrowed balance represented in the units of _returnToken
    function borrowBalanceConverted(
        address _account,
        address _borrowedToken,
        address _returnToken
    ) external view returns (uint256) {
        _validateToken(_borrowedToken);
        _validateToken(_returnToken);

        (uint256 borrowPrice, uint256 returnPrice) = tokenPrices(
            _borrowedToken,
            _returnToken
        );
        return
            _borrowBalanceConverted(
                _account,
                _borrowedToken,
                _returnToken,
                borrowPrice,
                returnPrice
            );
    }

    /// @notice Unit conversion. Get the amount of supplied tokens and convert it to the same value of _returnToken
    /// @param _account The address of the account for which the supplied balance will be retrieved and converted
    /// @param _suppliedToken The address of the token that has been supplied
    /// @param _returnToken The address of the token to which the supplied balance will be converted
    /// @return The supplied balance represented in the units of _returnToken
    function supplyBalanceConverted(
        address _account,
        address _suppliedToken,
        address _returnToken
    ) external view override returns (uint256) {
        _validateToken(_suppliedToken);
        _validateToken(_returnToken);

        (uint256 supplyPrice, uint256 returnPrice) = tokenPrices(
            _suppliedToken,
            _returnToken
        );
        return
            _supplyBalanceConverted(
                _account,
                _suppliedToken,
                _returnToken,
                supplyPrice,
                returnPrice
            );
    }

    /// @notice Calculate the interest rate for supplying a specific token for the current block
    /// @dev This function determines the interest received on supplied tokens based on the current interest rate model
    /// @dev The interest rate is influenced by factors like utilization, and the return value may be zero if there is no supply or debt for the token
    /// @param _token The address of the token for which the supply interest rate is queried
    /// @return interestRate The interest received on supplied tokens for the current block, represented as a proportion between 0 and 100e18
    function supplyRatePerBlock(
        address _token
    ) external view returns (uint256) {
        _validateToken(_token);
        if (
            _accounting[_token].totalSupplyAmount == 0 ||
            _accounting[_token].totalDebtAmount == 0
        ) {
            return 0;
        }
        return
            (((_interestRatePerBlock(_token) * utilizationRate(_token)) /
                100e18) * irm.lpRate) / 100e18; // 1e18: annual interest split into interest per Block // 0e18 - 100e18 // e18
    }

    /// @notice Calculate the interest rate for borrowing a specific token for the current block
    /// @dev This function returns the borrow interest rate as calculated by the interest rate model
    /// @dev The return value is based on the current state of the market and the token's utilization rate
    /// @param _token The address of the token for which the borrow interest rate is queried
    /// @return interestRate The interest paid on borrowed tokens for the current block, as a proportion
    function borrowRatePerBlock(
        address _token
    ) external view returns (uint256) {
        _validateToken(_token);
        return _interestRatePerBlock(_token);
    }

    /// @notice Perform a unit conversion to convert a specified amount of one token to the equivalent value in another token
    /// @dev This function takes an input amount of `_fromToken` and returns the equivalent value in `_toToken` based on their respective prices
    /// @param _fromToken The address of the token to convert from
    /// @param _toToken The address of the token to convert to
    /// @param _inputAmount The amount of `_fromToken` to be converted to `_toToken`
    /// @return convertedAmount The amount of `_toToken` having the same value as `_inputAmount` of `_fromToken`
    function convertTokenValues(
        address _fromToken,
        address _toToken,
        uint256 _inputAmount
    ) external view returns (uint256) {
        _validateToken(_fromToken);
        _validateToken(_toToken);

        (uint256 fromPrice, uint256 toPrice) = tokenPrices(
            _fromToken,
            _toToken
        );
        return
            _convertTokenValues(
                _fromToken,
                _toToken,
                _inputAmount,
                fromPrice,
                toPrice
            );
    }

    /// @notice Calculate the proportion of borrowed tokens to supplied tokens for a given token
    /// @dev This function returns the utilization rate, which is the ratio of total borrowed amount to the total supplied amount for the given token
    /// @dev If there is no total supply or total debt for the token, the utilization rate will be 0
    /// @dev The return value is represented as a proportion and is bounded within the range 0 to 100e18
    /// @param _token The address of the token for which the utilization rate is queried
    /// @return utilizationRate The proportion of borrowed tokens to supplied tokens, represented as a number between 0 and 100e18
    function utilizationRate(address _token) public view returns (uint256) {
        uint256 totalSupply = _accounting[_token].totalSupplyAmount; //e18
        uint256 totalDebt = _accounting[_token].totalDebtAmount; //e18
        if (totalSupply == 0 || totalDebt == 0) {
            return 0;
        }
        return Math.min((totalDebt * 100e18) / totalSupply, 100e18); // e20
    }

    ///
    /// =======================================================================
    /// ======================= GETTER functions ==============================
    /// =======================================================================
    ///

    /// @notice Check the current health of an account, represented by the ratio of collateral to debt
    /// @dev The account health is calculated based on the prices of the collateral and debt tokens (tokenA and tokenB) and represents the overall stability of an account in the lending protocol
    /// @dev A healthy account typically has a health ratio greater than 1, meaning that the collateral value is greater than the debt value
    /// @param _account The address of the account for which the health is being checked
    /// @return health The ratio of collateral to debt for the specified account, represented as a proportion. Health should typically be greater than 1
    function accountHealth(address _account) external view returns (uint256) {
        (uint256 priceA, uint256 priceB) = tokenPrices(tokenA, tokenB);
        return _accountHealth(_account, priceA, priceB);
    }

    /// @notice Fetches the current token price
    /// @dev For the native asset: uses the oracle set in the controller
    /// @dev For the permissionless asset: uses the uniswap TWAP oracle
    /// @param _token token for which the Oracle price should be received
    /// @return quote for 1 unit of the token, priced in ETH
    function tokenPrice(address _token) public view returns (uint256) {
        return lendingController.tokenPrice(_token);
    }

    /// @notice Fetches the current token prices for both assets
    /// @dev calls tokenPrice() for each asset
    /// @param _tokenA first token for which the Oracle price should be received
    /// @param _tokenB second token for which the Oracle price should be received
    /// @return oracle price of each asset priced in 1 unit swapped for eth
    function tokenPrices(
        address _tokenA,
        address _tokenB
    ) public view returns (uint256, uint256) {
        return lendingController.tokenPrices(_tokenA, _tokenB);
    }

    /// ======================================================================
    /// =============== Accounting for tokens and shares =====================
    /// ======================================================================

    /// @notice Check the debt of an account for a specific token
    /// @param _token The address of the token for which the debt is being checked
    /// @param _account The address of the account for which the debt is being checked
    /// @return debtAmount The number of `_token` owed by the `_account`
    function debtOf(
        address _token,
        address _account
    ) external view override returns (uint256) {
        _validateToken(_token);
        return _debtOf(_token, _account);
    }

    /// @notice Check the balance of an account for a specific token
    /// @param _token The address of the token for which the supply balance is being checked
    /// @param _account The address of the account for which the supply balance is being checked
    /// @return supplyAmount The balance of `_token` that has been supplied by the `_account`
    function supplyOf(
        address _token,
        address _account
    ) external view override returns (uint256) {
        _validateToken(_token);
        return _supplyOf(_token, _account);
    }

    /// @notice Returns the debt shares of a user for a specific token
    /// @param token The address of the token
    /// @param user The address of the user
    /// @return The amount of debt shares for the user and token
    function debtSharesOf(
        address token,
        address user
    ) public view returns (uint256) {
        return _accounting[token].debtSharesOf[user];
    }

    /// @notice Returns the supply shares of a user for a specific token
    /// @param token The address of the token
    /// @param user The address of the user
    /// @return The amount of supply shares for the user and token
    function supplySharesOf(
        address token,
        address user
    ) public view returns (uint256) {
        return _accounting[token].supplySharesOf[user];
    }

    /// @notice Returns the total supply shares of a specific token
    /// @param token The address of the token
    /// @return The total supply shares for the token
    function totalSupplyShares(address token) public view returns (uint256) {
        return _accounting[token].totalSupplyShares;
    }

    /// @notice Returns the total supply amount of a specific token
    /// @param token The address of the token
    /// @return The total supply amount for the token
    function totalSupplyAmount(address token) public view returns (uint256) {
        return _accounting[token].totalSupplyAmount;
    }

    /// @notice Returns the total debt shares of a specific token
    /// @param token The address of the token
    /// @return The total debt shares for the token
    function totalDebtShares(address token) public view returns (uint256) {
        return _accounting[token].totalDebtShares;
    }

    /// @notice Returns the total debt amount of a specific token
    /// @param token The address of the token
    /// @return The total debt amount for the token
    function totalDebtAmount(address token) public view returns (uint256) {
        return _accounting[token].totalDebtAmount;
    }

    ///
    ///
    /// =======================================================================
    /// ======================= INTERNAL functions ============================
    /// =======================================================================
    ///
    ///

    /// @notice deposit a token into the pair (as collateral)
    /// @dev mints new supply shares
    /// @dev folding is prohibited (deposit and borrow the same token)
    function _deposit(
        address _account,
        address _token,
        uint256 _amount
    ) internal {
        _validateToken(_token);
        accrue(_token);

        require(
            _accounting[_token].debtSharesOf[_account] == 0,
            "LendingPair: cannot deposit borrowed token"
        );

        _mintSupplyAmount(_token, _account, _amount);
        _safeTransferFrom(_token, msg.sender, _amount);

        emit Deposit(_account, _token, _amount);
    }

    /// @notice withdraw a specified amount of collateral to a recipient
    /// @dev health and credit are not checked
    /// @dev accrues interest and calls _withdrawShares with updated supply
    function _withdraw(
        address _recipient,
        address _token,
        uint256 _amount
    ) internal {
        _validateToken(_token);
        accrue(_token);

        // Fix rounding error:
        uint256 _shares = _supplyToShares(_token, _amount);
        if (_sharesToSupply(_token, _shares) < _amount) {
            ++_shares;
        }

        _withdrawShares(_token, _shares);
        _transferAsset(_token, _recipient, _amount);
    }

    /// @notice borrow a specified amount and check pair related boundary conditions.
    /// @dev the health/collateral is not checked. Calling this can borrow any amount available
    function _borrow(
        address _recipient,
        address _token,
        uint256 _amount
    ) internal {
        _validateToken(_token);
        accrue(_token);

        require(
            _accounting[_token].supplySharesOf[msg.sender] == 0,
            "LendingPair: cannot borrow supplied token"
        );

        _mintDebtAmount(_token, msg.sender, _amount);
        _transferAsset(_token, _recipient, _amount);

        emit Borrow(msg.sender, _token, _amount);
    }

    /// @notice withdraw all collateral of _token to a recipient
    function _withdrawAll(address _recipient, address _token) internal {
        _validateToken(_token);
        accrue(_token);

        uint256 shares = _accounting[_token].supplySharesOf[msg.sender];
        uint256 amount = _sharesToSupply(_token, shares);
        _withdrawShares(_token, shares);
        _transferAsset(_token, _recipient, amount);
    }

    /// @notice repays a specified _maxAmount of _token debt
    /// @dev if _maxAmount > debt defaults to repaying all debt of selected token
    function _repay(
        address _account,
        address _token,
        uint256 _maxAmount
    ) internal {
        _validateToken(_token);
        accrue(_token);

        uint256 maxShares = _debtToShares(_token, _maxAmount);

        uint256 sharesAmount = Math.min(
            _accounting[_token].debtSharesOf[_account],
            maxShares
        );
        uint256 repayAmount = _repayShares(_account, _token, sharesAmount);

        _safeTransferFrom(_token, msg.sender, repayAmount);
    }

    /// @notice checks the current account health is greater than required min health (based on provided collateral, debt and token prices)
    /// @dev reverts if health is below liquidation limit
    function _checkAccountHealth(address _account) internal view {
        (uint256 priceA, uint256 priceB) = tokenPrices(tokenA, tokenB);
        uint256 health = _accountHealth(_account, priceA, priceB);
        require(
            health >= LIQ_MIN_HEALTH,
            "LendingPair: insufficient accountHealth"
        );
    }

    /// @notice liquidation: Sell collateral to reduce debt and increase accountHealth
    /// @notice the liquidator needs to provide enought tokens to repay debt and receives supply tokens
    /// @dev Set _repayAmount to type(uint).max to repay all debt, inc. pending interest
    function _liquidateAccount(
        address _account,
        address _repayToken,
        uint256 _repayAmount,
        uint256 _amountOutMin
    ) internal {
        // Input validation and adjustments

        _validateToken(_repayToken);

        address supplyToken = _repayToken == tokenA ? tokenB : tokenA;

        // Check account is underwater after interest

        accrue(supplyToken);
        accrue(_repayToken);

        (uint256 priceA, uint256 priceB) = tokenPrices(tokenA, tokenB);

        uint256 health = _accountHealth(_account, priceA, priceB);
        require(
            health < LIQ_MIN_HEALTH,
            "LendingPair: account health < LIQ_MIN_HEALTH"
        );

        // Calculate balance adjustments

        _repayAmount = Math.min(_repayAmount, _debtOf(_repayToken, _account));

        // Calculates the amount of collateral to liquidate for _repayAmount
        // Avoiding stack too deep error
        uint256 supplyDebt = _convertTokenValues(
            _repayToken,
            supplyToken,
            _repayAmount,
            _repayToken == tokenA ? priceA : priceB, // repayPrice
            supplyToken == tokenA ? priceA : priceB // supplyPrice
        );

        // Adding fees
        uint256 callerFee = (supplyDebt *
            lendingController.liqFeeCaller(_repayToken)) / 100e18;
        uint256 systemFee = (supplyDebt *
            lendingController.liqFeeSystem(_repayToken)) / 100e18;
        uint256 supplyBurn = supplyDebt + callerFee + systemFee;
        uint256 supplyOutput = supplyDebt + callerFee;

        // Ensure that the tokens received by the liquidator meet or exceed the desired minimum amount
        require(
            supplyOutput >= _amountOutMin,
            "LendingPair: Liquidation output below minimium desired amount"
        );

        // Adjust balances
        _burnSupplyShares(
            supplyToken,
            _account,
            _supplyToShares(supplyToken, supplyBurn)
        );
        pendingSystemFees[supplyToken] += systemFee;
        _burnDebtShares(
            _repayToken,
            _account,
            _debtToShares(_repayToken, _repayAmount)
        );

        // Transfer collateral from liquidator
        _safeTransferFrom(_repayToken, msg.sender, _repayAmount);

        // Mint liquidator
        _mintSupplyAmount(supplyToken, msg.sender, supplyOutput);

        emit Liquidation(
            _account,
            _repayToken,
            supplyToken,
            _repayAmount,
            supplyOutput
        );
    }

    /// @notice calls the function wildCall of any contract
    /// @param _callee contract to call
    /// @param _data calldata
    function _call(address _callee, bytes memory _data) internal {
        ICallee(_callee).wildCall(_data);
    }

    /// @notice Supply tokens.
    /// @dev Mint new supply shares (corresponding to supply _amount) and credit them to _account.
    /// @dev increase total supply amount and shares
    /// @return shares | number of supply shares newly minted
    function _mintSupplyAmount(
        address _token,
        address _account,
        uint256 _amount
    ) internal returns (uint256 shares) {
        if (_amount > 0) {
            shares = _supplyToShares(_token, _amount);
            _accounting[_token].supplySharesOf[_account] += shares;
            _accounting[_token].totalSupplyShares += shares;
            _accounting[_token].totalSupplyAmount += _amount;
        }
    }

    /// @notice Withdraw Tokens.
    /// @dev burns supply shares credited to _account by the number of _shares specified
    /// @dev reduces totalSupplyShares. Reduces totalSupplyAmount by the corresponding amount
    /// @return amount of tokens corresponding to _shares
    function _burnSupplyShares(
        address _token,
        address _account,
        uint256 _shares
    ) internal returns (uint256 amount) {
        if (_shares > 0) {
            // Fix rounding error which can make issues during depositRepay / withdrawBorrow
            if (_accounting[_token].supplySharesOf[_account] - _shares == 1) {
                _shares += 1;
            }

            amount = _sharesToSupply(_token, _shares);
            _accounting[_token].supplySharesOf[_account] -= _shares;
            _accounting[_token].totalSupplyShares -= _shares;
            _accounting[_token].totalSupplyAmount -= amount;
        }
    }

    /// @notice Make debt.
    /// @dev Mint new debt shares (corresponding to debt _amount) and credit them to _account.
    /// @dev increase total debt amount and shares
    /// @return shares | number of debt shares newly minted
    function _mintDebtAmount(
        address _token,
        address _account,
        uint256 _amount
    ) internal returns (uint256 shares) {
        if (_amount > 0) {
            shares = _debtToShares(_token, _amount);
            // Borrowing costs 1 share to account for later underpayment
            ++shares;

            _accounting[_token].debtSharesOf[_account] += shares;
            _accounting[_token].totalDebtShares += shares;
            _accounting[_token].totalDebtAmount += _amount;
        }
    }

    /// @notice Repay Debt.
    /// @dev burns debt shares credited to _account by the number of _shares specified
    /// @dev reduces totalDebtShares. Reduces totalDebtAmount by the corresponding amount
    /// @return amount of tokens corresponding to _shares
    function _burnDebtShares(
        address _token,
        address _account,
        uint256 _shares
    ) internal returns (uint256 amount) {
        if (_shares > 0) {
            // Fix rounding error which can make issues during depositRepay / withdrawBorrow
            if (_accounting[_token].debtSharesOf[_account] - _shares == 1) {
                _shares += 1;
            }
            amount = _sharesToDebt(_token, _shares);
            _accounting[_token].debtSharesOf[_account] -= _shares;
            _accounting[_token].totalDebtShares -= _shares;
            _accounting[_token].totalDebtAmount -= amount;
        }
    }

    /// @notice accrue interest on debt, by adding newDebt since last accrue to totalDebtAmount.
    /// @dev done by: applying the interest per Block on the oustanding debt times blocks elapsed
    /// @dev using _interestRatePerBlock() interest rate Model
    /// @return newDebt
    function _accrueDebt(address _token) internal returns (uint256 newDebt) {
        // If borrowed or existing Debt, else skip
        if (_accounting[_token].totalDebtAmount > 0) {
            uint256 blocksElapsed = block.number - lastBlockAccrued[_token];
            uint256 pendingInterestRate = _interestRatePerBlock(_token) *
                blocksElapsed;
            newDebt =
                (_accounting[_token].totalDebtAmount * pendingInterestRate) /
                100e18;
            _accounting[_token].totalDebtAmount += newDebt;
        }
    }

    /// @notice reduces the SupplyShare of msg.sender by the defined amount, emits Withdraw event
    function _withdrawShares(address _token, uint256 _shares) internal {
        uint256 amount = _burnSupplyShares(_token, msg.sender, _shares);
        emit Withdraw(msg.sender, _token, amount);
    }

    /// @notice repay debt shares
    /// @return amount of tokens repayed for _shares
    function _repayShares(
        address _account,
        address _token,
        uint256 _shares
    ) internal returns (uint256 amount) {
        amount = _burnDebtShares(_token, _account, _shares);
        emit Repay(_account, _token, amount);
    }

    /// @notice Safe withdraw of ERC-20 tokens (revert on failure)
    function _transferAsset(
        address _asset,
        address _to,
        uint256 _amount
    ) internal {
        if (_asset == address(WETH)) {
            //Withdraw as ETH
            _wethWithdrawTo(_to, _amount);
        } else {
            _safeTransfer(_asset, _to, _amount);
        }
    }

    /// @notice creates a new ERC-20 token representing collateral amounts within this pair
    /// @dev called during pair initialization
    /// @dev acts as an interface to the information stored in this contract
    function _createLpToken(
        address _lpTokenMaster,
        address _underlying
    ) internal returns (address) {
        ILPTokenMaster newLPToken = ILPTokenMaster(_lpTokenMaster.clone());
        newLPToken.initialize(_underlying, address(lendingController));
        return address(newLPToken);
    }

    /// @notice checks the current health of an _account, the health represents the ratio of collateral to debt
    /// @dev Query all supply & borrow balances and convert the amounts into the the same token (tokenA)
    /// @dev then calculates the ratio
    function _accountHealth(
        address _account,
        uint256 _priceA,
        uint256 _priceB
    ) internal view returns (uint256) {
        // No Debt:
        if (
            _accounting[tokenA].debtSharesOf[_account] == 0 &&
            _accounting[tokenB].debtSharesOf[_account] == 0
        ) {
            return LIQ_MIN_HEALTH;
        }

        uint256 colFactorA = colFactor[tokenA];
        uint256 colFactorB = colFactor[tokenB];

        uint256 creditA = (_supplyOf(tokenA, _account) * colFactorA) / 100e18;
        uint256 creditB = (_supplyBalanceConverted(
            _account,
            tokenB,
            tokenA,
            _priceB,
            _priceA
        ) * colFactorB) / 100e18;

        uint256 totalAccountBorrow = _debtOf(tokenA, _account) +
            _borrowBalanceConverted(_account, tokenB, tokenA, _priceB, _priceA);

        return ((creditA + creditB) * 1e18) / totalAccountBorrow;
    }

    /// @notice returns the amount of shares representing X tokens (_inputSupply)
    /// @param _totalShares total shares in circulation
    /// @param _totalAmount total amount of token X deposited in the pair
    /// @param _inputSupply amount of tokens to find the proportional amount of shares for
    /// @return shares representing _inputSupply
    function _amountToShares(
        uint256 _totalShares,
        uint256 _totalAmount,
        uint256 _inputSupply
    ) internal pure returns (uint256) {
        if (_totalShares > 0 && _totalAmount > 0) {
            return (_inputSupply * _totalShares) / _totalAmount;
        } else {
            return _inputSupply;
        }
    }

    /// @notice returns the amount of tokens representing X shares (_inputShares)
    /// @param _totalShares total shares in circulation
    /// @param _totalAmount total amount of token X deposited in the pair
    /// @param _inputShares amount of shares to find the proportional amount of tokens for
    /// @return the underlying amount of tokens for _inputShares
    function _sharesToAmount(
        uint256 _totalShares,
        uint256 _totalAmount,
        uint256 _inputShares
    ) internal pure returns (uint256) {
        if (_totalShares > 0 && _totalAmount > 0) {
            return (_inputShares * _totalAmount) / _totalShares;
        } else {
            return _inputShares;
        }
    }

    /// @notice converts an input debt amount to the corresponding number of DebtShares representing it
    /// @dev calls _amountToShares with the arguments of totalDebtShares, totalDebtAmount, and debt amount to convert to DebtShares
    function _debtToShares(
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        return
            _amountToShares(
                _accounting[_token].totalDebtShares,
                _accounting[_token].totalDebtAmount,
                _amount
            );
    }

    /// @notice converts a number of DebtShares to the underlying amount of token debt
    /// @dev calls _sharesToAmount with the arguments of totalDebtShares, totalDebtAmount, and the number of shares to convert to the underlying debt amount
    function _sharesToDebt(
        address _token,
        uint256 _shares
    ) internal view returns (uint256) {
        return
            _sharesToAmount(
                _accounting[_token].totalDebtShares,
                _accounting[_token].totalDebtAmount,
                _shares
            );
    }

    /// @notice converts an input amount to the corresponding number of shares representing it
    /// @dev calls _amountToShares with the arguments of totalSupplyShares, totalSupplyAmount, and amount to convert to shares
    function _supplyToShares(
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        return
            _amountToShares(
                _accounting[_token].totalSupplyShares,
                _accounting[_token].totalSupplyAmount,
                _amount
            );
    }

    /// @notice converts a number of shares to the underlying amount of tokens
    /// @dev calls _sharesToAmount with the arguments of totalSupplyShares, totalSupplyAmount, and the number of shares to convert to the underlying amount
    function _sharesToSupply(
        address _token,
        uint256 _shares
    ) internal view returns (uint256) {
        return
            _sharesToAmount(
                _accounting[_token].totalSupplyShares,
                _accounting[_token].totalSupplyAmount,
                _shares
            );
    }

    /// @return amount of tokens (including interest) borrowed by _account
    /// @dev gets the number of debtShares owed by _account and converts it into the amount of underlying tokens (_sharesToDebt)
    function _debtOf(
        address _token,
        address _account
    ) internal view returns (uint256) {
        return
            _sharesToDebt(_token, _accounting[_token].debtSharesOf[_account]);
    }

    /// @return amount of tokens (including interest) supplied by _account
    /// @dev gets the number of shares credited to _account and converts it into the amount of underlying tokens (_sharesToSupply)
    function _supplyOf(
        address _token,
        address _account
    ) internal view returns (uint256) {
        return
            _sharesToSupply(
                _token,
                _accounting[_token].supplySharesOf[_account]
            );
    }

    /// @notice Unit conversion. Get the amount of borrowed tokens and convert it to the same value of _returnToken
    /// @return amount borrowed converted to _returnToken
    function _borrowBalanceConverted(
        address _account,
        address _borrowedToken,
        address _returnToken,
        uint256 _borrowPrice,
        uint256 _returnPrice
    ) internal view returns (uint256) {
        return
            _convertTokenValues(
                _borrowedToken,
                _returnToken,
                _debtOf(_borrowedToken, _account),
                _borrowPrice,
                _returnPrice
            );
    }

    /// @notice Unit conversion. Get the amount of supplied tokens and convert it to the same value of _returnToken
    /// @return amount supplied converted to _returnToken
    function _supplyBalanceConverted(
        address _account,
        address _suppliedToken,
        address _returnToken,
        uint256 _supplyPrice,
        uint256 _returnPrice
    ) internal view returns (uint256) {
        return
            _convertTokenValues(
                _suppliedToken,
                _returnToken,
                _supplyOf(_suppliedToken, _account), //input amount
                _supplyPrice,
                _returnPrice
            );
    }

    /// @notice converts an _inputAmount (_fromToken) to the same value of _toToken
    /// @notice like a price quote of _fromToken -> _toToken with an amount of _inputAmout
    /// @dev  Not calling priceOracle.convertTokenValues() to save gas by reusing already fetched prices
    function _convertTokenValues(
        address _fromToken,
        address _toToken,
        uint256 _inputAmount,
        uint256 _fromPrice,
        uint256 _toPrice
    ) internal view returns (uint256) {
        uint256 fromPrice = (_fromPrice * 1e18) / 10 ** _decimals[_fromToken];
        uint256 toPrice = (_toPrice * 1e18) / 10 ** _decimals[_toToken];

        return (_inputAmount * fromPrice) / toPrice;
    }

    /// @notice calculates the interest rate per block based on current supply+borrow amounts and limits
    /// @dev we have two interest rate curves in place:
    /// @dev                     1) 0%->loweRate               : if ultilization < targetUtilization
    /// @dev                     2) lowerRate + 0%->higherRate : if ultilization >= targetUtilization
    /// @dev
    /// @dev To convert time rate to block rate, use this formula:
    /// @dev RATE FORMULAR: annualRate [0-100] * BLOCK_TIME [s] * 1e18 / (365 * 86400); BLOCK_TIME_MAIN_OLD=13.2s
    /// @dev where annualRate is in format: 1e18 = 1%
    /// @dev Arbitrum uses ethereum blocknumbers. block.number is updated every ~1min
    /// @dev Ethereum PoS-blocktime is 12.05s
    /// @dev Ethereum Blocks per year: ~2617095
    function _interestRatePerBlock(
        address _token
    ) internal view returns (uint256) {
        uint256 totalSupply = _accounting[_token].totalSupplyAmount;
        uint256 totalDebt = _accounting[_token].totalDebtAmount;

        if (totalSupply == 0 || totalDebt == 0) {
            return irm.minRate;
        }

        uint256 utilization = (((totalDebt * 100e18) / totalSupply) * 100e18) /
            irm.targetUtilization;

        // If current utilization is below targetUtilization
        if (utilization < 100e18) {
            uint256 rate = (irm.lowRate * utilization) / 100e18; //[e2-e0] with lowRate
            return Math.max(rate, irm.minRate);
        } else {
            // This "utilization" represents the utilization of funds between target-utilization and totalSupply
            // E.g. totalSupply=100 totalDebt=95 taget=90 -> utilization=50%
            uint256 targetSupplyUtilization = (totalSupply *
                irm.targetUtilization) / 100e18;
            uint256 excessUtilization = ((totalDebt - targetSupplyUtilization));
            uint256 maxExcessUtiization = totalSupply *
                (100e18 - irm.targetUtilization);

            utilization =
                (excessUtilization * 100e18) /
                (maxExcessUtiization / 100e18);

            utilization = Math.min(utilization, 100e18);
            return
                irm.lowRate +
                ((irm.highRate - irm.lowRate) * utilization) /
                100e18;
        }
    }

    /// @notice _accounting! Makes sure balances, debt, supply, and fees add up.
    function _checkReserve(address _token) internal view {
        IERC20Metadata token = IERC20Metadata(_token);

        uint256 balance = token.balanceOf(address(this));
        uint256 debt = _accounting[_token].totalDebtAmount;
        uint256 supply = _accounting[_token].totalSupplyAmount;
        uint256 fees = pendingSystemFees[_token];

        require(
            int256(balance) + int256(debt) - int256(supply) - int256(fees) >= 0,
            "LendingPair: reserve check failed"
        );
    }

    /// @notice validates that the input token is one of the pair Tokens (tokenA or tokenB).
    function _validateToken(address _token) internal view {
        require(
            _token == tokenA || _token == tokenB,
            "LendingPair: invalid token"
        );
    }
}

