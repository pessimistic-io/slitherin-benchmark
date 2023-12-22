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
import { Math } from "./Math.sol";
import { SafeMath } from "./SafeMath.sol";
import { CompoundReward } from "./CompoundReward.sol";

// interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { ILodeReward, ILodeComp, ILodeTroller } from "./ILodeStar.sol";
import { IComet } from "./ICompound.sol";
import { OpenOceanAggregator } from "./OpenOceanAggregator.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";
import { IFlashLoans } from "./IFlashLoans.sol";
import { IERC20Extended } from "./IERC20Extended.sol";
import { IFactorLeverageVault } from "./IFactorLeverageVault.sol";

contract CompoundLeverageStrategy is
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
    //                         Events
    // =============================================================

    event LeverageAdded(uint256 amount, uint256 debt);
    event LeverageRemoved(uint256 debt);
    event LeverageClosed(uint256 assetBalance, uint256 debtBalance);
    event AssetSwitched(address newAsset, uint256 balance);
    event Withdraw(uint256 amount);
    event Repay(uint256 amount);
    event Supply(uint256 amount);
    event Borrow(uint256 amount);
    event WithdrawTokenInCaseStuck(address tokenAddress, uint256 amount);
    event RewardClaimed(uint256 amount);
    event RewardClaimedSupply(uint256 amount);
    event RewardClaimedRepay(uint256 amount);
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

    // balancer
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // =============================================================
    //                         Storages
    // =============================================================

    uint256 private _positionId;

    IERC721 private _vaultManager;

    IERC20 private _asset;

    IERC20 private _debtToken;

    address public _assetPool;

    address public _debtPool;

    uint8 private flMode; // 1 = addLeverage, 2 = removeLeverage, 3 = switch asset, 4 = switch debt

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
        _assetPool = _assetPoolAddress;
        _debtPool = _debtPoolAddress;
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
        return _assetPool;
    }

    function debtPool() public view returns (address) {
        return _debtPool;
    }

    function assetBalance() public view returns (uint256) {
        (uint128 balance, ) = IComet(_assetPool).userCollateral(address(this), asset());
        return uint256(balance);
    }

    function debtBalance() public view returns (uint256) {
        return IComet(_debtPool).borrowBalanceOf(address(this));
    }

    function owner() public view returns (address) {
        return _vaultManager.ownerOf(_positionId);
    }

    function addLeverage(uint256 amount, uint256 debt, bytes calldata data) external onlyOwner {
        // If user is sending assets to leverage
        if (amount > 0) {
            _asset.safeTransferFrom(msg.sender, address(this), amount);
            _asset.approve(_assetPool, amount);
            IComet(_assetPool).supply(asset(), amount);
        }

        // If there's a debt operation
        if (debt > 0) {
            // execute flashloan
            bytes memory params = abi.encode(debt, data);
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
        (uint256 amount, bytes memory data) = abi.decode(params, (uint256, bytes));

        // Use the flashloaned amount (debt token) to swap to the asset token

        // swap debt to asset
        // the only solution to convert from memory to calldata
        uint256 outAmountDebt = this.swapBySelf(debtToken(), asset(), amount, data);

        // Deposit the swapped assets to earn interest or add as collateral
        _asset.approve(_assetPool, outAmountDebt);
        IComet(_assetPool).supply(asset(), outAmountDebt);

        // Borrow the equivalent amount using our new collateral
        _debtToken.approve(_debtPool, amount + feeAmount);
        IComet(_debtPool).withdraw(debtToken(), amount + feeAmount); // Compound borrow

        // Repay the flashloan debt using the amount we borrowed
        _debtToken.safeTransfer(balancerVault, amount + feeAmount);
    }

    function removeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw the asset -> swap the asset -> borrow to repay the flashloan

        // execute flashloan
        bytes memory params = abi.encode(amount, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 2;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        // safeTransfer to owner
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransfer(owner(), balance);

        emit LeverageRemoved(amount);
    }

    function _flRemoveLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, bytes memory data) = abi.decode(params, (uint256, bytes));

        uint256 flashLoanAmount = debtBalance(); // assuming the flashloan equal debt balance

        // repay
        IERC20(debtToken()).approve(address(_debtPool), flashLoanAmount);
        IComet(_debtPool).supply(debtToken(), flashLoanAmount);

        // withdraw
        IComet(_assetPool).withdraw(asset(), amount);

        // swap asset to debt
        uint256 outAmount = this.swapBySelf(asset(), debtToken(), amount, data);
        // you can't swap asset more than debt value
        if (outAmount > flashLoanAmount) revert AMOUNT_TOO_MUCH();

        uint256 remainingFlashLoanAmount = flashLoanAmount - _debtToken.balanceOf(address(this));

        // borrow
        IComet(_debtPool).withdraw(debtToken(), remainingFlashLoanAmount + feeAmount);
        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, flashLoanAmount + feeAmount);
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

    function supply(uint256 amount) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset()).approve(_assetPool, amount);

        IComet(_assetPool).supply(asset(), amount);
        emit Supply(amount);
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

    function borrow(uint256 amount) external onlyOwner {
        IERC20(debtToken()).approve(_debtPool, amount);
        IComet(_debtPool).withdraw(debtToken(), amount);
        IERC20(debtToken()).safeTransfer(msg.sender, amount);
        emit Borrow(amount);
    }

    function repay(uint256 amount) external onlyOwner {
        IERC20(debtToken()).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(debtToken()).approve(_debtPool, amount);
        IComet(_debtPool).supply(debtToken(), amount);

        emit Repay(amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        IComet(_assetPool).withdraw(asset(), amount);
        uint256 contractBalance = IERC20(asset()).balanceOf(address(this));
        uint256 withdrawAmount = amount > contractBalance ? contractBalance : amount;
        IERC20(asset()).safeTransfer(owner(), withdrawAmount);

        emit Withdraw(withdrawAmount);
    }

    function switchAsset(address newAsset, uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to a new asset -> supply the new asset -> borrow to repay the flashloan

        // check if newAsset exist
        if (IFactorLeverageVault(vaultManager()).assets(newAsset) == address(0)) revert INVALID_ASSET();

        // execute flashloan
        bytes memory params = abi.encode(newAsset, amount, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 3;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;
    }

    function _flSwitchAsset(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (address newAsset, uint256 amount, bytes memory data) = abi.decode(params, (address, uint256, bytes));

        uint256 currentDebtBalance = debtBalance();

        // repay all debt
        IERC20(debtToken()).approve(address(_debtPool), debtBalance());
        IComet(_debtPool).supply(debtToken(), debtBalance());

        // withdraw all
        IComet(_assetPool).withdraw(asset(), assetBalance());

        // swap asset to new asset
        this.swapBySelf(asset(), newAsset, amount, data);

        // change asset and pool to new one
        _asset = IERC20(newAsset);
        _assetPool = IFactorLeverageVault(vaultManager()).assets(newAsset);

        // supply the new asset
        _asset.approve(_assetPool, IERC20(_asset).balanceOf(address(this)));
        IComet(_assetPool).supply(address(_asset), IERC20(_asset).balanceOf(address(this)));

        // borrow
        IComet(_debtPool).withdraw(debtToken(), currentDebtBalance + feeAmount);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, currentDebtBalance + feeAmount);

        emit AssetSwitched(newAsset, assetBalance());
    }

    function closeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to repay the flash loan

        // notes: if amount > debt value then the all position become debtToken
        // for example, when ETH/USDC closes the leverage can be withdrawn as ETH or USDC

        uint256 assetPosition = assetBalance();
        uint256 debtPosition = debtBalance();

        // execute flashloan
        bytes memory params = abi.encode(amount, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 5;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        uint256 closedAsset = IERC20(asset()).balanceOf(address(this));
        uint256 closedDebt = IERC20(debtToken()).balanceOf(address(this));

        // transfer asset and debt token to owner
        IERC20(asset()).safeTransfer(owner(), closedAsset);
        IERC20(debtToken()).safeTransfer(owner(), closedDebt);

        emit LeverageClosed(closedAsset, closedDebt);
    }

    function _flCloseLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, bytes memory data) = abi.decode(params, (uint256, bytes));

        uint256 flashLoanAmount = debtBalance();

        // repay
        IERC20(debtToken()).approve(_debtPool, debtBalance());
        IComet(_debtPool).supply(debtToken(), debtBalance());

        IComet(_assetPool).withdraw(asset(), assetBalance());

        // swap asset to debt
        this.swapBySelf(asset(), debtToken(), amount, data);

        // // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, flashLoanAmount + feeAmount);
    }

    function withdrawTokenInCaseStuck(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == assetPool() || tokenAddress == debtPool()) revert INVALID_TOKEN();
        IERC20(tokenAddress).safeTransfer(owner(), amount);
        emit WithdrawTokenInCaseStuck(tokenAddress, amount);
    }

    function version() external pure returns (string memory) {
        return '0.1';
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // check if the new implementation is registered
        if (IFactorLeverageVault(vaultManager()).isRegisteredUpgrade(_getImplementation(), newImplementation) == false)
            revert('INVALID_UPGRADE');
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
        if (flMode == 5) _flCloseLeverage(params, feeAmount);
    }

    // =============================================================
    //                      modifiers
    // =============================================================

    function claimRewards() external onlyOwner {
        uint256 fee = IFactorLeverageVault(vaultManager()).claimRewardFee();
        uint256 feeScale = IFactorLeverageVault(vaultManager()).FEE_SCALE();
        address factorFeeRecipient = IFactorLeverageVault(vaultManager()).feeRecipient();
        uint256 transferedAmount = CompoundReward.claimReward(fee, feeScale, factorFeeRecipient);
        emit RewardClaimed(transferedAmount);
    }

    function claimRewardsSupply(uint256 amountOutMinimum) external onlyOwner {
        uint256 fee = IFactorLeverageVault(vaultManager()).claimRewardFee();
        uint256 feeScale = IFactorLeverageVault(vaultManager()).FEE_SCALE();
        address factorFeeRecipient = IFactorLeverageVault(vaultManager()).feeRecipient();
        uint256 transferedAmount = CompoundReward.claimRewardsSupply(
            _assetPool,
            asset(),
            fee,
            feeScale,
            factorFeeRecipient,
            amountOutMinimum
        );
        emit RewardClaimedSupply(transferedAmount);
    }

    function claimRewardsRepay(uint256 amountOutMinimum) external onlyOwner {
        uint256 fee = IFactorLeverageVault(vaultManager()).claimRewardFee();
        uint256 feeScale = IFactorLeverageVault(vaultManager()).FEE_SCALE();
        address factorFeeRecipient = IFactorLeverageVault(vaultManager()).feeRecipient();
        uint256 transferedAmount = CompoundReward.claimRewardsRepay(
            _debtPool,
            debtToken(),
            fee,
            feeScale,
            factorFeeRecipient,
            amountOutMinimum
        );
        emit RewardClaimedRepay(transferedAmount);
    }

    modifier onlyOwner() {
        if (msg.sender != _vaultManager.ownerOf(_positionId)) revert NOT_OWNER();
        _;
    }
}

