// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";

import "./SafeToken.sol";

import "./Market.sol";

import "./interfaces_IWETH.sol";

contract GToken is Market {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== STATE VARIABLES ========== */

    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => mapping(address => uint256)) private _transferAllowances;

    /* ========== EVENT ========== */

    event Mint(address minter, uint256 mintAmount);
    event Redeem(
        address account,
        uint256 underlyingAmount,
        uint256 gTokenAmount,
        uint256 uAmountToReceive,
        uint256 uAmountRedeemFee
    );

    event Borrow(address account, uint256 ammount, uint256 accountBorrow);
    event RepayBorrow(address payer, address borrower, uint256 amount, uint256 accountBorrow);
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 amount,
        address gTokenCollateral,
        uint256 seizeAmount
    );

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /* ========== INITIALIZER ========== */

    /// @notice Initialization
    /// @param _name name
    /// @param _symbol symbol
    /// @param _decimals decimals
    function initialize(string memory _name, string memory _symbol, uint8 _decimals) external initializer {
        __GMarket_init();

        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /* ========== VIEWS ========== */

    /// @notice View allowance
    /// @param account Account address
    /// @param spender Spender address
    /// @return Allowance amount
    function allowance(address account, address spender) external view override returns (uint256) {
        return _transferAllowances[account][spender];
    }

    /// @notice Owner address 조회
    function getOwner() external view returns (address) {
        return owner();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address dst, uint256 amount) external override accrue nonReentrant returns (bool) {
        core.transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external override accrue nonReentrant returns (bool) {
        core.transferTokens(msg.sender, src, dst, amount);
        return true;
    }

    /// @notice account 의 allowance amount 변경
    /// @param spender spender address
    /// @param amount amount
    function approve(address spender, uint256 amount) external override returns (bool) {
        _transferAllowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Update supply information
    /// @param account Account address to supply
    /// @param uAmount Underlying token amount to supply
    /// @return gAmount gToken amount to receive
    function supply(address account, uint256 uAmount) external payable override accrue onlyCore returns (uint256) {
        uint256 exchangeRate = exchangeRate();
        uAmount = underlying == address(ETH) ? msg.value : uAmount;
        uAmount = _doTransferIn(account, uAmount);
        uint256 gAmount = uAmount.mul(1e18).div(exchangeRate);
        require(gAmount > 0, "GToken: invalid gAmount");
        updateSupplyInfo(account, gAmount, 0);

        emit Mint(account, gAmount);
        emit Transfer(address(0), account, gAmount);
        return gAmount;
    }

    /// @notice Redeem token by gToken amount
    /// @param redeemer Redeemer account address
    /// @param gAmount gToken amount
    function redeemToken(address redeemer, uint256 gAmount) external override accrue nftAccrue onlyCore returns (uint256) {
        return _redeem(redeemer, gAmount, 0);
    }

    /// @notice Redeem token by underlying token amount
    /// @param redeemer Redeemer account address
    /// @param uAmount Underlying token amount
    function redeemUnderlying(address redeemer, uint256 uAmount) external override accrue nftAccrue onlyCore returns (uint256) {
        return _redeem(redeemer, 0, uAmount);
    }

    /// @notice Update borrow information
    /// @param account Borrower account address
    /// @param amount Borrow amount
    function borrow(address account, uint256 amount) external override accrue nftAccrue onlyCore returns (uint256) {
        require(getCash() >= amount, "GToken: borrow amount exceeds cash");
        updateBorrowInfo(account, amount, 0);
        _doTransferOut(account, amount);

        emit Borrow(account, amount, borrowBalanceOf(account));
        return amount;
    }

    /// @notice Repay own borrowing dept
    /// @dev Called when repay my own debt only
    /// @param account Borrower account address
    /// @param amount Repay amount
    function repayBorrow(address account, uint256 amount) external payable override accrue onlyCore returns (uint256) {
        if (amount == uint256(-1)) {
            amount = borrowBalanceOf(account);
        }
        return _repay(account, account, underlying == address(ETH) ? msg.value : amount);
    }

    /// @notice Repay others' debt behalf
    /// @dev Called when repay others' debt behalf
    /// @param payer Account address who pay for the debt
    /// @param borrower Account address who borrowing debt
    /// @param amount Dept amount to repay
    function repayBorrowBehalf(
        address payer,
        address borrower,
        uint256 amount
    ) external payable override accrue onlyCore returns (uint256) {
        return _repay(payer, borrower, underlying == address(ETH) ? msg.value : amount);
    }

    /// @notice Force to liquidate others debt
    /// @param gTokenCollateral gToken address provided as collateral
    /// @param liquidator Liquidator account address
    /// @param borrower Borrower account address
    /// @param amount Collateral amount
    function liquidateBorrow(
        address gTokenCollateral,
        address liquidator,
        address borrower,
        uint256 amount
    )
        external
        payable
        override
        accrue
        onlyCore
        returns (uint256 seizeGAmount, uint256 rebateGAmount, uint256 liquidatorGAmount)
    {
        require(borrower != liquidator, "GToken: cannot liquidate yourself");
        amount = underlying == address(ETH) ? msg.value : amount;
        amount = _repay(liquidator, borrower, amount);
        require(amount > 0 && amount < uint256(-1), "GToken: invalid repay amount");

        (seizeGAmount, rebateGAmount, liquidatorGAmount) = IValidator(core.validator()).gTokenAmountToSeize(
            address(this),
            gTokenCollateral,
            amount
        );

        require(
            IGToken(payable(gTokenCollateral)).balanceOf(borrower) >= seizeGAmount,
            "GToken: too much seize amount"
        );

        emit LiquidateBorrow(liquidator, borrower, amount, gTokenCollateral, seizeGAmount);
    }

    function seize(
        address liquidator,
        address borrower,
        uint256 gAmount
    ) external override accrue onlyCore nonReentrant {
        accountBalances[borrower] = accountBalances[borrower].sub(gAmount);
        accountBalances[liquidator] = accountBalances[liquidator].add(gAmount);

        emit Transfer(borrower, liquidator, gAmount);
    }

    function withdrawReserves() external override accrue onlyRebateDistributor nonReentrant {
        if (getCash() >= totalReserve) {
            uint256 amount = totalReserve;

            if (totalReserve > 0) {
                totalReserve = 0;
                _doTransferOut(address(rebateDistributor), amount);
            }
        }
    }

    /// @notice Transfer interneal
    /// @param spender Spender account address
    /// @param src Source account address
    /// @param dst Destination account address
    /// @param amount Transfer amount
    function transferTokensInternal(
        address spender,
        address src,
        address dst,
        uint256 amount
    ) external override onlyCore {
        require(
            src != dst && IValidator(core.validator()).redeemAllowed(address(this), src, amount),
            "GToken: cannot transfer"
        );
        require(amount != 0, "GToken: zero amount");
        uint256 _allowance = spender == src ? uint256(-1) : _transferAllowances[src][spender];
        uint256 _allowanceNew = _allowance.sub(amount, "GToken: transfer amount exceeds allowance");

        accountBalances[src] = accountBalances[src].sub(amount);
        accountBalances[dst] = accountBalances[dst].add(amount);

        if (_allowance != uint256(-1)) {
            _transferAllowances[src][spender] = _allowanceNew;
        }
        emit Transfer(src, dst, amount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice Transfer in underlying token
    /// @param from Transfer from address
    /// @param amount Transfer amount
    /// @return Transfered amount
    function _doTransferIn(address from, uint256 amount) private returns (uint256) {
        if (underlying == address(ETH)) {
            require(msg.value >= amount, "GToken: value mismatch");
            return Math.min(msg.value, amount);
        } else {
            uint256 balanceBefore = IBEP20(underlying).balanceOf(address(this));
            underlying.safeTransferFrom(from, address(this), amount);
            uint256 balanceAfter = IBEP20(underlying).balanceOf(address(this));
            require(balanceAfter.sub(balanceBefore) <= amount);
            return balanceAfter.sub(balanceBefore);
        }
    }

    /// @notice Transfer out underlying token
    /// @param to Transfer target add
    /// @param amount Transfer amount
    function _doTransferOut(address to, uint256 amount) private {
        if (underlying == address(ETH)) {
            SafeToken.safeTransferETH(to, amount);
        } else {
            underlying.safeTransfer(to, amount);
        }
    }

    /// @notice Redeem underlying token
    /// @dev Use only one of the amount params (gAmountIn or uAmountIn)
    ///      Pass unused parameter to 0
    /// @param account Redeemer account
    /// @param gAmountIn Redeem amount calculated by gToken amount
    /// @param uAmountIn Redeem amount
    function _redeem(address account, uint256 gAmountIn, uint256 uAmountIn) private returns (uint256) {
        require(gAmountIn == 0 || uAmountIn == 0, "GToken: one of gAmountIn or uAmountIn must be zero");
        require(totalSupply >= gAmountIn, "GToken: not enough total supply");
        require(getCash() >= uAmountIn || uAmountIn == 0, "GToken: not enough underlying");
        require(
            getCash() >= gAmountIn.mul(exchangeRate()).div(1e18) || gAmountIn == 0,
            "GToken: not enough underlying"
        );

        IValidator validator = IValidator(core.validator());
        uint256 gAmountToRedeem = gAmountIn > 0 ? gAmountIn : uAmountIn.mul(1e18).div(exchangeRate());
        uint256 uAmountToRedeem = gAmountIn > 0 ? gAmountIn.mul(exchangeRate()).div(1e18) : uAmountIn;

        require(validator.redeemAllowed(address(this), account, gAmountToRedeem), "GToken: cannot redeem");

        uint256 redeemFeeRate = validator.getAccountRedeemFeeRate(account);
        uint256 uAmountRedeemFee = uAmountToRedeem.mul(redeemFeeRate).div(1e4);
        uint256 uAmountToReceive = uAmountToRedeem.sub(uAmountRedeemFee);

        updateSupplyInfo(account, 0, gAmountToRedeem);
        _doTransferOut(account, uAmountToReceive);
        _doTransferOut(core.rebateDistributor(), uAmountRedeemFee);

        emit Transfer(account, address(0), gAmountToRedeem);
        emit Redeem(account, uAmountToRedeem, gAmountToRedeem, uAmountToReceive, uAmountRedeemFee);
        return uAmountToRedeem;
    }

    /// @notice Repay borrowing debt and update borrow information
    /// @param payer Payer account address
    /// @param borrower Borrower account address
    function _repay(address payer, address borrower, uint256 amount) private returns (uint256) {
        uint256 borrowBalance = borrowBalanceOf(borrower);
        uint256 repayAmount = Math.min(borrowBalance, amount);
        repayAmount = _doTransferIn(payer, repayAmount);
        updateBorrowInfo(borrower, 0, repayAmount);

        if (underlying == address(ETH)) {
            uint256 refundAmount = amount > repayAmount ? amount.sub(repayAmount) : 0;
            if (refundAmount > 0) {
                _doTransferOut(payer, refundAmount);
            }
        }

        emit RepayBorrow(payer, borrower, repayAmount, borrowBalanceOf(borrower));
        return repayAmount;
    }
}

