// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import internal dependencies
import "./Kernel.sol";
import {TRSRYv1} from "./TRSRY.v1.sol";
import {MINTRv1} from "./MINTR.v1.sol";
import {LENDRv1} from "./LENDR.v1.sol";
import {ROLESv1, RolesConsumer} from "./OlympusRoles.sol";

// Import types
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {OlympusERC20Token} from "./OlympusERC20.sol";
import {ERC20} from "./ERC20.sol";

// Import libraries
import {FullMath} from "./FullMath.sol";

// Import interfaces
import {ILendingAMO} from "./ILendingAMO.sol";
import {ISilo, ISiloInterestRateModel, ISiloLens, ISiloIncentivesController} from "./ISilo.sol";

/// @title Olympus Silo Lending AMO
/// @notice Olympus Silo Lending AMO (Policy) Contract
contract SiloAMO is ILendingAMO, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;

    // ========= STATE ========= //

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;
    LENDRv1 public LENDR;

    // Token
    OlympusERC20Token public OHM;

    // External Market Info
    address public market;
    address public rateModel;
    address public siloLens;
    address public incentivesController;
    address public siloShareOhm;
    address public siloToken;

    // Configuration Variables
    uint256 public maximumToDeploy;
    uint256 public updateInterval;

    // State Variables
    uint256 public ohmDeployed;
    uint256 public circulatingOhmBurned;
    uint256 public lastUpdateTimestamp;
    bool public status;
    bool public shouldEmergencyUnwind;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address market_,
        address rateModel_,
        address siloLens_,
        address incentivesController_,
        address siloShareOhm_,
        address siloToken_,
        uint256 maximumToDeploy_,
        uint256 updateInterval_
    ) Policy(kernel_) {
        OHM = OlympusERC20Token(ohm_);
        market = market_;
        rateModel = rateModel_;
        siloLens = siloLens_;
        incentivesController = incentivesController_;
        siloShareOhm = siloShareOhm_;
        siloToken = siloToken_;
        maximumToDeploy = maximumToDeploy_;
        updateInterval = updateInterval_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("LENDR");
        dependencies[3] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        LENDR = LENDRv1(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();
        Keycode LENDR_KEYCODE = LENDR.KEYCODE();

        requests = new Permissions[](5);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        requests[3] = Permissions(LENDR_KEYCODE, LENDR.addAMO.selector);
        requests[4] = Permissions(LENDR_KEYCODE, LENDR.removeAMO.selector);
    }

    //============================================================================================//
    //                                           MODIFIERS                                        //
    //============================================================================================//

    modifier onlyWhileActive() {
        if (!status) revert AMO_Inactive(address(this));
        _;
    }

    //============================================================================================//
    //                                        CORE FUNCTIONS                                      //
    //============================================================================================//

    /// @inheritdoc ILendingAMO
    function deposit(uint256 amount_) external onlyWhileActive onlyRole("lendingamo_admin") {
        // Don't allow deposits if we are unwinding
        if (shouldEmergencyUnwind) revert AMO_UnwindOnly(address(this));

        // Don't allow deposits if it would put us over the maximum
        if (!_canDeposit(amount_)) revert AMO_LimitViolation(address(this));

        // Mint and deposit OHM
        _deposit(amount_);
    }

    /// @inheritdoc ILendingAMO
    function withdraw(
        uint256 amount_
    ) external onlyWhileActive nonReentrant onlyRole("lendingamo_admin") {
        _withdraw(amount_);
    }

    /// @inheritdoc ILendingAMO
    function update() external onlyWhileActive nonReentrant {
        // Don't allow updates if enough time has not passed
        if (block.timestamp - lastUpdateTimestamp < updateInterval)
            revert AMO_UpdateInterval(address(this));

        // Don't allow updates if we are unwinding
        if (shouldEmergencyUnwind) revert AMO_UnwindOnly(address(this));

        // Don't allow the public to call the update function if utilization rate is
        // outside the acceptable bounds
        ISilo.UtilizationData memory utilizationData = ISilo(market).utilizationData(address(OHM));
        ISiloInterestRateModel.Config memory config = ISiloInterestRateModel(rateModel).getConfig(
            market,
            address(OHM)
        );
        uint256 utilizationRate = utilizationData.totalDeposits == 0
            ? 0
            : utilizationData.totalBorrowAmount.mulDiv(1e18, utilizationData.totalDeposits);
        uint256 minUtilization = _getMinAcceptableUtilization(
            uint256(config.uopt),
            uint256(config.ucrit)
        );
        uint256 maxUtilization = _getMaxAcceptableUtilization(
            uint256(config.uopt),
            uint256(config.ulow)
        );
        if (utilizationRate < minUtilization || utilizationRate > maxUtilization) {
            // Require msg.sender to be the lendingamo_admin role
            ROLES.requireRole("lendingamo_admin", msg.sender);
        }

        if (utilizationData.interestRateTimestamp == block.timestamp)
            revert AMO_UpdateReentrancyGuard(address(this));

        // Update state
        lastUpdateTimestamp = block.timestamp;

        // Handle update logic
        _update();
    }

    /// @inheritdoc ILendingAMO
    function harvestYield() external {
        ISiloIncentivesController incentivesController_ = ISiloIncentivesController(
            incentivesController
        );

        address[] memory assets = new address[](1);
        assets[0] = siloShareOhm;

        // Get claimable rewards
        uint256 claimableRewards = incentivesController_.getRewardsBalance(assets, address(this));

        // Claim rewards
        if (claimableRewards > 0)
            incentivesController_.claimRewards(assets, claimableRewards, address(this));

        // Send rewards to TRSRY
        ERC20(siloToken).transfer(address(TRSRY), ERC20(siloToken).balanceOf(address(this)));
    }

    /// @inheritdoc ILendingAMO
    function emergencyUnwind() external nonReentrant onlyRole("emergency_admin") {
        shouldEmergencyUnwind = true;
        _emergencyUnwind();
    }

    /// @inheritdoc ILendingAMO
    function sweepTokens(address token_) external onlyRole("lendingamo_admin") {
        ERC20(token_).transfer(msg.sender, ERC20(token_).balanceOf(address(this)));
    }

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// @inheritdoc ILendingAMO
    /// @dev        You have to call market.accrueInterest before using this function. Otherwise
    //              the value returned will be incorrect (will not include interest), and the
    //              siloLens.totalDepositsWithInterest function is broken and will overstate claim
    //              on OHM.
    function getUnderlyingOhmBalance() public view returns (uint256) {
        ISilo.AssetStorage memory assetStorage = ISilo(market).assetStorage(address(OHM));
        uint256 underlyingBalance = ISiloLens(siloLens).balanceOfUnderlying(
            assetStorage.totalDeposits,
            siloShareOhm,
            address(this)
        );

        return underlyingBalance;
    }

    /// @inheritdoc ILendingAMO
    function getTargetDeploymentAmount() public view returns (uint256 targetDeploymentAmount) {
        ISiloInterestRateModel.Config memory config = ISiloInterestRateModel(rateModel).getConfig(
            market,
            address(OHM)
        );
        ISilo.UtilizationData memory utilizationData = ISilo(market).utilizationData(address(OHM));

        // This is the optimal utilization percentage formatted with 18 decimals
        // This is int256 but should never be negative, so we can safely cast to uint256
        int256 optimalUtilizationPct = config.uopt;
        uint256 totalBorrowed = utilizationData.totalBorrowAmount;

        // Optimal utilization percentage is formatted with 18 decimals, so we need to multiply by 1e18
        targetDeploymentAmount = totalBorrowed.mulDiv(1e18, uint256(optimalUtilizationPct));
    }

    /// @inheritdoc ILendingAMO
    function getBorrowedOhm() public view returns (uint256) {
        ISilo.UtilizationData memory utilizationData = ISilo(market).utilizationData(address(OHM));
        return (
            utilizationData.totalBorrowAmount > ohmDeployed
                ? ohmDeployed
                : utilizationData.totalBorrowAmount
        );
    }

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// @notice Updates the tracked Silo market interest rate model in the event of an upgrade
    /// @param newRateModel_ The address of the new Silo interest rate model
    /// @dev This function is permissioned to only be called by the lendingamo_admin role
    function setRateModel(address newRateModel_) external onlyRole("lendingamo_admin") {
        rateModel = newRateModel_;
    }

    /// @notice Updates the trackes Silo incentives controller in the event of an upgrade
    /// @param newController_ The address of the new Silo incentives controller
    /// @dev This function is permissioned to only be called by the lendingamo_admin role
    function setIncentivesController(address newController_) external onlyRole("lendingamo_admin") {
        incentivesController = newController_;
    }

    /// @inheritdoc ILendingAMO
    function setMaximumToDeploy(uint256 newMaximum_) external onlyRole("lendingamo_admin") {
        maximumToDeploy = newMaximum_;
    }

    /// @inheritdoc ILendingAMO
    function setUpdateInterval(uint256 newInterval_) external onlyRole("lendingamo_admin") {
        updateInterval = newInterval_;
    }

    /// @inheritdoc ILendingAMO
    function activate() external onlyRole("lendingamo_admin") {
        status = true;
        LENDR.addAMO(address(this));
    }

    /// @inheritdoc ILendingAMO
    function deactivate() external onlyRole("lendingamo_admin") {
        status = false;
        LENDR.removeAMO(address(this));
    }

    //============================================================================================//
    //                                      INTERNAL FUNCTIONS                                    //
    //============================================================================================//

    function _getMinAcceptableUtilization(
        uint256 uopt_,
        uint256 ucrit_
    ) internal pure returns (uint256) {
        uint HUGE_NUMBER = 2 ** 96;
        uint ADJUSTMENT = 1e8;
        // We want this to be 18 decimals. uopt_ and ucrit_ are 18 decimals
        uint min = HUGE_NUMBER / (((2 * HUGE_NUMBER) / uopt_) - (HUGE_NUMBER / ucrit_));
        return min + ADJUSTMENT;
    }

    function _getMaxAcceptableUtilization(
        uint256 uopt_,
        uint256 ulow_
    ) internal pure returns (uint256) {
        // We want this to be 18 decimals, uopt_ and ulow_ are 18 decimals
        uint max = uopt_ + uopt_.mulDiv((((uopt_ * 1e18) / ulow_) - 1e18), 1e18);
        return max >= 1e18 ? 1e18 : max - 1;
    }

    function _canDeposit(uint256 amount_) internal view returns (bool) {
        if (ohmDeployed + amount_ > maximumToDeploy) return false;
        return true;
    }

    function _deposit(uint256 amount_) internal {
        // Update state
        uint256 cachedCirculatingOhmBurned = circulatingOhmBurned;
        if (cachedCirculatingOhmBurned > amount_) {
            circulatingOhmBurned -= amount_;
        } else if (cachedCirculatingOhmBurned > 0) {
            circulatingOhmBurned = 0;
            ohmDeployed += amount_ - cachedCirculatingOhmBurned;
        } else {
            ohmDeployed += amount_;
        }

        // Mint OHM via the minter
        _mintOhm(amount_);

        // Deposit OHM into Silo
        OHM.increaseAllowance(market, amount_);
        ISilo(market).deposit(address(OHM), amount_, false);

        emit Deposit(amount_);
    }

    function _withdraw(uint256 amount_) internal {
        // The OHM deposit will accrue interest over time leading to the potential to withdraw more OHM
        // than is tracked by the ohmDeployed value. This is fine, but we need to avoid underflow errors
        // and track the amount of OHM that has been burned from the circulating supply after being accrued
        // as interest
        if (ohmDeployed < amount_) circulatingOhmBurned += amount_ - ohmDeployed;
        ohmDeployed -= ohmDeployed > amount_ ? amount_ : ohmDeployed;

        // Withdraw OHM from Silo
        ISilo(market).withdraw(address(OHM), amount_, false);

        // Burn received OHM
        _burnOhm(amount_);

        emit Withdrawal(amount_);
    }

    function _emergencyUnwind() internal {
        // Accrue interest on Silo
        ISilo(market).accrueInterest(address(OHM));

        // Calculate amount to withdraw
        // Silo withdrawals work by reverting if there is insufficient liquidity to withdraw the requested amount
        // so we need to check the available liquidity and withdraw the lesser of the available liquidity and the
        // amount we have deployed
        uint256 deploymentAmount = getUnderlyingOhmBalance();
        uint256 availableLiquidity = ISilo(market).liquidity(address(OHM));
        uint256 amountToWithdraw = deploymentAmount > availableLiquidity
            ? availableLiquidity
            : deploymentAmount;

        // Withdraw OHM from Silo
        _withdraw(amountToWithdraw);
    }

    function _mintOhm(uint256 amount_) internal {
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    function _burnOhm(uint256 amount_) internal {
        OHM.increaseAllowance(address(MINTR), amount_);
        try MINTR.burnOhm(address(this), amount_) {} catch {}
    }

    function _update() internal {
        // Accrue interest on Silo
        ISilo(market).accrueInterest(address(OHM));

        // Get current total deposits and target total deposits
        ISilo.AssetStorage memory assetStorage = ISilo(market).assetStorage(address(OHM));
        uint256 currentDeployment = getUnderlyingOhmBalance();
        uint256 totalDeposits = assetStorage.totalDeposits;
        uint256 targetDeploymentAmount = getTargetDeploymentAmount();

        if (targetDeploymentAmount < totalDeposits) {
            // If the target deployment amount is less than the total deposits, then we need to withdraw the difference
            uint256 amountToWithdraw = totalDeposits - targetDeploymentAmount;
            if (amountToWithdraw > currentDeployment) amountToWithdraw = currentDeployment;

            if (amountToWithdraw > 0) _withdraw(amountToWithdraw);
        } else if (targetDeploymentAmount > totalDeposits) {
            // If the target deployment amount is greater than the total deposits, then we need to deposit the difference
            uint256 amountToDeposit = targetDeploymentAmount - totalDeposits;
            if (amountToDeposit > maximumToDeploy - ohmDeployed)
                amountToDeposit = maximumToDeploy - ohmDeployed;

            if (amountToDeposit > 0) _deposit(amountToDeposit);
        }
    }
}

