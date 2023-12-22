// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// inheritances
import { ILeverageStrategy } from "./ILeverageStrategy.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

// libraries
import { SafeERC20 } from "./SafeERC20.sol";
import { OpenOceanAggregator } from "./OpenOceanAggregator.sol";
import { Math } from "./Math.sol";
import { SafeMath } from "./SafeMath.sol";
import { SiloReward } from "./SiloReward.sol";

// interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC20Extended } from "./IERC20Extended.sol";
import { IERC721 } from "./IERC721.sol";
import { IFlashLoans } from "./IFlashLoans.sol";
import { ISiloStrategy, ISiloLens, ISiloIncentiveController, ISiloToken, ISiloRepository } from "./ISiloStrategy.sol";
import { IFactorLeverageVault } from "./IFactorLeverageVault.sol";

contract SiloLeverageStrategy is
    Initializable,
    ILeverageStrategy,
    IFlashLoanRecipient,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // =============================================================
    //                         Libraries
    // =============================================================

    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeMath for uint256;

    // =============================================================
    //                         Enum
    // =============================================================

    enum RewardType {
        Silo,
        Arb
    }

    // =============================================================
    //                         Events
    // =============================================================

    event LeverageAdded(uint256 amount, uint256 debt);
    event LeverageRemoved(uint256 debt);
    event LeverageClosed(uint256 amount, uint256 debt);
    event AssetSwitched(address newAsset, uint256 balance);
    event DebtSwitched(address newDebt, uint256 balance);
    event Withdraw(uint256 amount);
    event Repay(uint256 amount);
    event Supply(uint256 amount);
    event Borrow(uint256 amount);
    event WithdrawTokenInCaseStuck(address tokenAddress, uint256 amount);
    event RewardClaimed(uint256 amount, address token);
    event RewardClaimedSupply(uint256 amount, address token);
    event RewardClaimedRepay(uint256 amount, address token);
    event LeverageChargeFee(uint256 amount);

    // =============================================================
    //                         Errors
    // =============================================================

    error NOT_OWNER();
    error NOT_BALANCER();
    error NOT_SELF();
    error INVALID_ASSET();
    error INVALID_DEBT();
    error INVALID_TOKEN();
    error AMOUNT_TOO_MUCH();

    // =============================================================
    //                         Constants
    // =============================================================
    // Silo
    address public constant provider = 0x8658047e48CC09161f4152c79155Dac1d710Ff0a; //Silo Repository
    address public constant siloIncentive = 0x4999873bF8741bfFFB0ec242AAaA7EF1FE74FCE8; // Silo Incenctive
    address public constant siloToken = 0x0341C0C0ec423328621788d4854119B97f44E391; // Silo Token
    address public constant siloLens = 0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47; // Silo Lens

    // balancer
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // WETH
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // =============================================================
    //                         Storages
    // =============================================================

    uint256 private _positionId;

    IERC721 private _vaultManager;

    IERC20 private _asset;

    IERC20 private _debtToken;

    IERC20 public _assetPool;

    IERC20 public _debtPool;

    uint8 private flMode; // 1 = addLeverage, 2 = removeLeverage, 3 = switch asset, 4 = switch debt, 5 = close leverage

    // =============================================================
    //                      Functions
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 __positionId,
        address _vaultManagerAddress,
        address _assetAddress,
        address _debtAddress,
        address _assetPoolAddress,
        address _debtPoolAddress
    ) public initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _positionId = __positionId;
        _vaultManager = IERC721(_vaultManagerAddress);
        _asset = IERC20(_assetAddress);
        _debtToken = IERC20(_debtAddress);
        _assetPool = IERC20(_assetPoolAddress);
        _debtPool = IERC20(_debtPoolAddress);
    }

    function vaultManager() public view returns (address) {
        return address(_vaultManager);
    }

    function positionId() public view returns (uint256) {
        return _positionId;
    }

    function asset() public view returns (address) {
        return address(_asset);
    }

    function debtToken() public view returns (address) {
        return address(_debtToken);
    }

    function assetPool() public view returns (address) {
        return address(_assetPool);
    }

    function debtPool() public view returns (address) {
        return address(_debtPool);
    }

    function assetBalance() public view returns (uint256) {
        address poolAddress = ISiloToken(assetPool()).silo();

        return
            ISiloLens(siloLens).balanceOfUnderlying(
                ISiloLens(siloLens).totalDepositsWithInterest(poolAddress, asset()),
                assetPool(),
                address(this)
            );
    }

    function debtBalance() public view returns (uint256) {
        address poolAddress = ISiloToken(debtPool()).silo();

        return
            ISiloLens(siloLens).balanceOfUnderlying(
                ISiloLens(siloLens).totalBorrowAmountWithInterest(poolAddress, debtToken()),
                debtPool(),
                address(this)
            );
    }

    function owner() public view returns (address) {
        return _vaultManager.ownerOf(_positionId);
    }

    function addLeverage(uint256 amount, uint256 debt, bytes calldata data) external onlyOwner {
        // process = flashloan the expected debt -> swap the expected debt to asset -> supply the asset -> borrow to repay the flashloan
        address poolAddress = ISiloToken(assetPool()).silo();

        if (amount > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

            // supply
            IERC20(asset()).approve(poolAddress, amount);
            ISiloStrategy(poolAddress).deposit(asset(), amount, false);
        }

        if (debt > 0) {
            // execute flashloan
            bytes memory params = abi.encode(debt, poolAddress, data);
            address[] memory tokens = new address[](1);
            tokens[0] = debtToken();
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = debt;
            flMode = 1;
            IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
            flMode = 0;
        }

        emit LeverageAdded(amount, debt);
    }

    function _flAddLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, address poolAddress, bytes memory data) = abi.decode(params, (uint256, address, bytes));

        // swap debt to asset
        // the only solution to convert from memory to calldata
        uint256 outAmountDebt = this.swapBySelf(debtToken(), asset(), amount, data);

        // supply
        IERC20(asset()).approve(poolAddress, outAmountDebt);
        ISiloStrategy(poolAddress).deposit(asset(), outAmountDebt, false);

        // borrow
        ISiloStrategy(poolAddress).borrow(debtToken(), amount + feeAmount);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, amount + feeAmount);
    }

    function removeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw the asset -> swap the asset -> borrow to repay the flashloan

        address poolAddress = ISiloToken(assetPool()).silo();

        ISiloStrategy(poolAddress).accrueInterest(debtToken());

        uint256 repayAmount = _getRepayAmount(poolAddress);

        // execute flashloan
        bytes memory params = abi.encode(amount, repayAmount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = repayAmount;

        flMode = 2;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        // transfer to owner
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransfer(owner(), balance);

        emit LeverageRemoved(amount);
    }

    function _flRemoveLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, uint256 repayAmount, address poolAddress, bytes memory data) = abi.decode(
            params,
            (uint256, uint256, address, bytes)
        );

        // repay
        IERC20(debtToken()).approve(poolAddress, repayAmount);
        ISiloStrategy(poolAddress).repay(debtToken(), repayAmount);

        // withdraw
        ISiloStrategy(poolAddress).withdraw(asset(), amount, false);

        // swap asset to debt
        uint256 outAmount = this.swapBySelf(asset(), debtToken(), amount, data);

        // you can't swap asset more than debt value
        if (outAmount > repayAmount) revert AMOUNT_TOO_MUCH();

        uint256 remainingFlashLoanAmount = repayAmount - _debtToken.balanceOf(address(this));

        // borrow
        ISiloStrategy(poolAddress).borrow(debtToken(), remainingFlashLoanAmount + feeAmount);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, repayAmount + feeAmount);
    }

    function switchAsset(address newAsset, uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to a new asset -> supply the new asset -> borrow to repay the flashloan

        // check if newAsset exist
        if (IFactorLeverageVault(vaultManager()).assets(newAsset) == address(0)) revert INVALID_ASSET();

        address poolAddress = ISiloToken(assetPool()).silo();

        ISiloStrategy(poolAddress).accrueInterest(debtToken());

        uint256 repayAmount = _getRepayAmount(poolAddress);

        // execute flashloan
        bytes memory params = abi.encode(newAsset, repayAmount, amount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = repayAmount;

        flMode = 3;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;
    }

    function _flSwitchAsset(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (address newAsset, uint256 repayAmount, uint256 amount, address poolAddress, bytes memory data) = abi.decode(
            params,
            (address, uint256, uint256, address, bytes)
        );

        // repay all debt
        IERC20(debtToken()).approve(poolAddress, repayAmount);
        ISiloStrategy(poolAddress).repay(debtToken(), repayAmount);

        // withdraw all
        ISiloStrategy(poolAddress).withdraw(asset(), type(uint256).max, false);

        // swap asset to new asset
        this.swapBySelf(asset(), newAsset, amount, data);
        // change asset and pool to new one
        _asset = IERC20(newAsset);
        _assetPool = IERC20(IFactorLeverageVault(vaultManager()).assets(newAsset));

        // supply the new asset
        IERC20(asset()).approve(poolAddress, IERC20(asset()).balanceOf(address(this)));
        ISiloStrategy(poolAddress).deposit(asset(), IERC20(asset()).balanceOf(address(this)), false);

        // borrow
        ISiloStrategy(poolAddress).borrow(debtToken(), repayAmount + feeAmount);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, repayAmount + feeAmount);

        emit AssetSwitched(newAsset, assetBalance());
    }

    function switchDebt(address newDebtToken, uint256 newDebt, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> borrow a new debt -> swap the new debt to repay the flash loan

        // check if newDebtToken exist
        if (IFactorLeverageVault(vaultManager()).debts(newDebtToken) == address(0)) revert INVALID_DEBT();

        address poolAddress = ISiloToken(assetPool()).silo();

        ISiloStrategy(poolAddress).accrueInterest(debtToken());

        uint256 repayAmount = _getRepayAmount(poolAddress);

        // execute flashloan
        bytes memory params = abi.encode(newDebtToken, repayAmount, newDebt, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = repayAmount;

        flMode = 4;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;
    }

    function _flSwitchDebt(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (address newDebtToken, uint256 repayAmount, uint256 newDebt, address poolAddress, bytes memory data) = abi
            .decode(params, (address, uint256, uint256, address, bytes));
        address oldDebtToken = debtToken();

        // repay all debt
        IERC20(debtToken()).approve(poolAddress, repayAmount);
        ISiloStrategy(poolAddress).repay(debtToken(), repayAmount);

        _debtToken = IERC20(newDebtToken);
        _debtPool = IERC20(IFactorLeverageVault(vaultManager()).debts(newDebtToken));

        // borrow
        ISiloStrategy(poolAddress).borrow(debtToken(), newDebt + feeAmount);

        // swap new debt to flashloan
        this.swapBySelf(debtToken(), oldDebtToken, IERC20(_debtToken).balanceOf(address(this)), data);

        // repay Flashloan
        IERC20(oldDebtToken).safeTransfer(balancerVault, repayAmount + feeAmount);

        emit DebtSwitched(newDebtToken, assetBalance());
    }

    function closeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to repay the flash loan

        // notes: if amount > debt value then the all position become debtToken
        // for example, when wstETH/USDC closes the leverage can be withdrawn as wstETH or USDC
        address poolAddress = ISiloToken(assetPool()).silo();

        ISiloStrategy(poolAddress).accrueInterest(debtToken());

        uint256 repayAmount = _getRepayAmount(poolAddress);

        // execute flashloan
        bytes memory params = abi.encode(amount, repayAmount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = repayAmount;

        flMode = 5;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        uint256 closedAsset = IERC20(asset()).balanceOf(address(this));
        uint256 closedDebt = IERC20(debtToken()).balanceOf(address(this));

        // transfer asset & debt token to owner
        IERC20(asset()).safeTransfer(owner(), closedAsset);
        IERC20(debtToken()).safeTransfer(owner(), closedDebt);

        emit LeverageClosed(closedAsset, closedDebt);
    }

    function _flCloseLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, uint256 repayAmount, address poolAddress, bytes memory data) = abi.decode(
            params,
            (uint256, uint256, address, bytes)
        );

        // repay
        IERC20(debtToken()).approve(poolAddress, repayAmount);
        ISiloStrategy(poolAddress).repay(debtToken(), repayAmount);

        ISiloStrategy(poolAddress).withdraw(asset(), type(uint256).max, false);

        // swap asset to debt
        this.swapBySelf(asset(), debtToken(), amount, data);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, repayAmount + feeAmount);
    }

    function swapBySelf(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata data
    ) public returns (uint256) {
        if (msg.sender != address(this)) revert NOT_SELF();
        uint256 outAmount = OpenOceanAggregator.swap(tokenIn, tokenOut, amount, data);
        uint256 feeCharge = leverageFeeCharge(outAmount, tokenOut);
        return outAmount - feeCharge;
    }

    function leverageFeeCharge(uint256 amount, address token) internal returns (uint256) {
        uint256 leverageFee = IFactorLeverageVault(vaultManager()).leverageFee();
        uint256 feeScale = IFactorLeverageVault(vaultManager()).FEE_SCALE();
        address factorFeeRecipient = IFactorLeverageVault(vaultManager()).feeRecipient();
        uint256 depositFeeAmount = amount.mul(leverageFee).div(feeScale);

        IERC20(token).safeTransfer(factorFeeRecipient, depositFeeAmount);

        emit LeverageChargeFee(depositFeeAmount);

        return depositFeeAmount;
    }

    function _getRepayAmount(address poolAddress) internal view returns (uint256) {
        uint256 repayShare = _debtPool.balanceOf(address(this));
        uint256 debtTokenTotalSupply = _debtPool.totalSupply();
        uint256 totalBorrowed = ISiloLens(siloLens).totalBorrowAmount(poolAddress, debtToken());

        return toAmountRoundUp(repayShare, totalBorrowed, debtTokenTotalSupply);
    }

    function toAmountRoundUp(uint256 share, uint256 totalAmount, uint256 totalShares) internal pure returns (uint256) {
        return SiloReward.toAmountRoundUp(share, totalAmount, totalShares);
    }

    function supply(uint256 amount) external onlyOwner {
        SiloReward.supply(asset(), amount, getPoolAddress());
        emit Supply(amount);
    }

    function borrow(uint256 amount) external onlyOwner {
        SiloReward.borrow(debtToken(), amount, getPoolAddress());
        emit Borrow(amount);
    }

    function repay(uint256 amount) external onlyOwner {
        SiloReward.repay(debtToken(), amount, getPoolAddress());
        emit Repay(amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        SiloReward.withdraw(asset(), assetPool(), amount, getPoolAddress());
        emit Withdraw(amount);
    }

    function getPoolAddress() internal view returns (address) {
        return ISiloToken(assetPool()).silo();
    }

    function withdrawTokenInCaseStuck(address tokenAddress, uint256 amount) external onlyOwner {
        SiloReward.withdrawTokenInCaseStuck(tokenAddress, amount, assetPool(), debtPool());

        emit WithdrawTokenInCaseStuck(tokenAddress, amount);
    }

    /// @notice Claims rewards based on the specified reward type.
    /// @param rewardType The type of reward to claim (Silo or Arb).
    /// @dev Emits the RewardClaimed event upon successful execution.
    ///      Reverts if an invalid reward type is specified.
    function claimRewards(RewardType rewardType) external onlyOwner {
        (uint256 fee, uint256 feeScale, address factorFeeRecipient) = _getVaultDetails();

        if (rewardType == RewardType.Silo) {
            uint256 transferredAmount = SiloReward.claimReward(
                SiloReward.siloIncentive,
                SiloReward.siloToken,
                fee,
                feeScale,
                factorFeeRecipient
            );
            emit RewardClaimed(transferredAmount, SiloReward.siloToken);
        } else if (rewardType == RewardType.Arb) {
            uint256 transferredAmount = SiloReward.claimReward(
                SiloReward.siloIncentiveSTIP,
                SiloReward.arb,
                fee,
                feeScale,
                factorFeeRecipient
            );
            emit RewardClaimed(transferredAmount, SiloReward.arb);
        } else {
            revert('Invalid reward type');
        }
    }

    /// @notice Claims supply rewards based on the specified reward type and supplies them to a pool.
    /// @param rewardType The type of reward to claim (Silo or Arb).
    /// @param amountOutMin The minimum amount of out tokens expected to be received when swapping.
    /// @dev Emits the RewardClaimedSupply event upon successful execution.
    ///      Reverts if an invalid reward type is specified.
    function claimRewardsSupply(RewardType rewardType, uint256 amountOutMin) external onlyOwner {
        (uint256 fee, uint256 feeScale, address factorFeeRecipient, address poolAddress) = _getVaultAndPoolDetails();

        address incentiveContractAddress;
        address rewardToken;

        if (rewardType == RewardType.Silo) {
            incentiveContractAddress = SiloReward.siloIncentive;
            rewardToken = SiloReward.siloToken;
        } else if (rewardType == RewardType.Arb) {
            incentiveContractAddress = SiloReward.siloIncentiveSTIP;
            rewardToken = SiloReward.arb;
        } else {
            revert('Invalid reward type');
        }

        uint256 transferredAmount = SiloReward.claimRewardsSupply(
            incentiveContractAddress,
            rewardToken,
            asset(),
            fee,
            feeScale,
            factorFeeRecipient,
            amountOutMin,
            poolAddress
        );

        emit RewardClaimedSupply(transferredAmount, rewardToken);
    }

    /// @notice Claims repay rewards based on the specified reward type and uses them to repay debt.
    /// @param rewardType The type of reward to claim (Silo or Arb).
    /// @param amountOutMin The minimum amount of out tokens expected to be received when swapping.
    /// @dev Emits the RewardClaimedRepay event upon successful execution.
    ///      Reverts if an invalid reward type is specified.
    function claimRewardsRepay(RewardType rewardType, uint256 amountOutMin) external onlyOwner {
        (uint256 fee, uint256 feeScale, address factorFeeRecipient, address poolAddress) = _getVaultAndPoolDetails();

        address incentiveContractAddress;
        address rewardToken;

        if (rewardType == RewardType.Silo) {
            incentiveContractAddress = SiloReward.siloIncentive;
            rewardToken = SiloReward.siloToken;
        } else if (rewardType == RewardType.Arb) {
            incentiveContractAddress = SiloReward.siloIncentiveSTIP;
            rewardToken = SiloReward.arb;
        } else {
            revert('Invalid reward type');
        }
        uint256 transferredAmount = SiloReward.claimRewardsRepay(
            incentiveContractAddress,
            rewardToken,
            debtToken(),
            fee,
            feeScale,
            factorFeeRecipient,
            amountOutMin,
            poolAddress
        );
        emit RewardClaimedRepay(transferredAmount, rewardToken);
    }

    function _getVaultDetails() internal view returns (uint256 fee, uint256 feeScale, address factorFeeRecipient) {
        IFactorLeverageVault vault = IFactorLeverageVault(vaultManager());
        fee = vault.claimRewardFee();
        feeScale = vault.FEE_SCALE();
        factorFeeRecipient = vault.feeRecipient();
    }

    function _getVaultAndPoolDetails()
        internal
        view
        returns (uint256 fee, uint256 feeScale, address factorFeeRecipient, address poolAddress)
    {
        (fee, feeScale, factorFeeRecipient) = _getVaultDetails();
        poolAddress = ISiloToken(assetPool()).silo();
    }

    function version() external pure returns (string memory) {
        return '0.3';
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes calldata params
    ) external override nonReentrant {
        if (msg.sender != balancerVault) revert NOT_BALANCER();
        uint256 feeAmount = 0;
        if (feeAmounts.length > 0) {
            feeAmount = feeAmounts[0];
        }
        if (flMode == 1) _flAddLeverage(params, feeAmount);
        if (flMode == 2) _flRemoveLeverage(params, feeAmount);
        if (flMode == 3) _flSwitchAsset(params, feeAmount);
        if (flMode == 4) _flSwitchDebt(params, feeAmount);
        if (flMode == 5) _flCloseLeverage(params, feeAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // check if the new implementation is registered
        if (IFactorLeverageVault(vaultManager()).isRegisteredUpgrade(_getImplementation(), newImplementation) == false)
            revert('INVALID_UPGRADE');
    }

    // =============================================================
    //                      modifiers
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != _vaultManager.ownerOf(_positionId)) revert NOT_OWNER();
        _;
    }
}

