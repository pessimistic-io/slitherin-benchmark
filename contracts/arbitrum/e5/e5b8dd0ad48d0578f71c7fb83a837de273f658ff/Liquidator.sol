pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./ComptrollerInterface.sol";
import "./VEther.sol";
import "./VErc20.sol";
import "./WithAdmin.sol";
import "./SafeMath.sol";

contract Liquidator is WithAdmin, ReentrancyGuard {

    /// @notice Address of vEther contract.
    VEther public vEther;

    /// @notice Address of VeladashLending Unitroller contract.
    IComptroller comptroller;

    /// @notice Address of VeladashLendingr Treasury.
    address public treasury;

    /// @notice Percent of seized amount that goes to treasury.
    uint256 public treasuryPercentMantissa;

    /// @notice Emitted when once changes the percent of the seized amount
    ///         that goes to treasury.
    event NewLiquidationTreasuryPercent(uint256 oldPercent, uint256 newPercent);

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrowedTokens(address liquidator, address borrower, uint256 repayAmount, address vTokenCollateral, uint256 seizeTokensForTreasury, uint256 seizeTokensForLiquidator);

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor(
        address admin_,
        address payable vEther_,
        address comptroller_,
        address treasury_,
        uint256 treasuryPercentMantissa_
    )
        WithAdmin(admin_)
        ReentrancyGuard()
    {
        ensureNonzeroAddress(admin_);
        ensureNonzeroAddress(address(vEther_));
        ensureNonzeroAddress(comptroller_);
        ensureNonzeroAddress(treasury_);
        vEther = VEther(vEther_);
        comptroller = IComptroller(comptroller_);
        treasury = treasury_;
        treasuryPercentMantissa = treasuryPercentMantissa_;
    }

    /// @notice Liquidates a borrow and splits the seized amount between treasury and
    ///         liquidator. The liquidators should use this interface instead of calling
    ///         vToken.liquidateBorrow(...) directly.
    /// @dev For ETH borrows msg.value should be equal to repayAmount; otherwise msg.value
    ///      should be zero.
    /// @param vToken Borrowed vToken
    /// @param borrower The address of the borrower
    /// @param repayAmount The amount to repay on behalf of the borrower
    /// @param vTokenCollateral The collateral to seize
    function liquidateBorrow(
        address vToken,
        address borrower,
        uint256 repayAmount,
        VToken vTokenCollateral
    )
        external
        payable
        nonReentrant
    {
        ensureNonzeroAddress(borrower);
        uint256 ourBalanceBefore = vTokenCollateral.balanceOf(address(this));
        if (vToken == address(vEther)) {
            require(repayAmount == msg.value, "wrong amount");
            vEther.liquidateBorrow{value: msg.value}(borrower, vTokenCollateral);
        } else {
            require(msg.value == 0, "you shouldn't pay for this");
            _liquidateErc20(VErc20(vToken), borrower, repayAmount, vTokenCollateral);
        }
        uint256 ourBalanceAfter = vTokenCollateral.balanceOf(address(this));
        uint256 seizedAmount = ourBalanceAfter.sub(ourBalanceBefore);
        (uint256 ours, uint256 theirs) = _distributeLiquidationIncentive(vTokenCollateral, seizedAmount);
        emit LiquidateBorrowedTokens(msg.sender, borrower, repayAmount, address(vTokenCollateral), ours, theirs);
    }

    /// @notice Sets the new percent of the seized amount that goes to treasury. Should
    ///         be less than or equal to comptroller.liquidationIncentiveMantissa().sub(1e18).
    /// @param newTreasuryPercentMantissa New treasury percent (scaled by 10^18).
    function setTreasuryPercent(uint256 newTreasuryPercentMantissa) external onlyAdmin {
        require(
            newTreasuryPercentMantissa <= comptroller.liquidationIncentiveMantissa().sub(1e18),
            "appetite too big"
        );
        emit NewLiquidationTreasuryPercent(treasuryPercentMantissa, newTreasuryPercentMantissa);
        treasuryPercentMantissa = newTreasuryPercentMantissa;
    }

    /// @dev Transfers Erc20 tokens to self, then approves vToken to take these tokens.
    function _liquidateErc20(
        VErc20 vToken,
        address borrower,
        uint256 repayAmount,
        VToken vTokenCollateral
    )
        internal
    {
        IERC20 borrowedToken = IERC20(vToken.underlying());
        uint256 actualRepayAmount = _transferErc20(borrowedToken, msg.sender, address(this), repayAmount);
        borrowedToken.safeApprove(address(vToken), 0);
        borrowedToken.safeApprove(address(vToken), actualRepayAmount);
        vToken.liquidateBorrow(borrower, actualRepayAmount, vTokenCollateral);
    }

    /// @dev Splits the received vTokens between the liquidator and treasury.
    function _distributeLiquidationIncentive(VToken vTokenCollateral, uint256 siezedAmount)
        internal returns (uint256 ours, uint256 theirs)
    {
        (ours, theirs) = _splitLiquidationIncentive(siezedAmount);
        require(
            vTokenCollateral.transfer(msg.sender, theirs),
            "failed to transfer to liquidator"
        );
        require(
            vTokenCollateral.transfer(treasury, ours),
            "failed to transfer to treasury"
        );
        return (ours, theirs);
    }

    /// @dev Transfers tokens and returns the actual transfer amount
    function _transferErc20(IERC20 token, address from, address to, uint256 amount)
        internal
        returns (uint256 actualAmount)
    {
        uint256 prevBalance = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        return token.balanceOf(to).sub(prevBalance);
    }

    /// @dev Computes the amounts that would go to treasury and to the liquidator.
    function _splitLiquidationIncentive(uint256 seizedAmount)
        internal
        view
        returns (uint256 ours, uint256 theirs)
    {
        uint256 totalIncentive = comptroller.liquidationIncentiveMantissa();
        uint256 seizedForRepayment = seizedAmount.mul(1e18).div(totalIncentive);
        ours = seizedForRepayment.mul(treasuryPercentMantissa).div(1e18);
        theirs = seizedAmount.sub(ours);
        return (ours, theirs);
    }

    function ensureNonzeroAddress(address addr) internal pure {
        require(addr != address(0), "address should be nonzero");
    }
}

