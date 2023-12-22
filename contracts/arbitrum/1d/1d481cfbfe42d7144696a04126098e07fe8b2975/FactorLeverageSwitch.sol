// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
// inheritances
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Ownable } from "./Ownable.sol";
import { ILeverageStrategy } from "./ILeverageStrategy.sol";

// libraries
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { OpenOceanAggregator } from "./OpenOceanAggregator.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";

// interfaces
import { IStrategy } from "./IStrategy.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Extended } from "./IERC20Extended.sol";
import { IERC721 } from "./IERC721.sol";
import { IFlashLoans } from "./IFlashLoans.sol";

interface IFactorLeverageVault {
    function createPosition(address asset, address debt) external returns (uint256 id, address vault);

    function positions(uint256) external view returns (address);
}

contract FactorLeverageSwitch is IFlashLoanRecipient, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    // =============================================================
    //                          Events
    // =============================================================

    event LeverageSwitched(
        address vault,
        address strategy,
        uint256 positionId,
        address newVault,
        address newStrategy,
        uint256 newPositionId
    );

    // =============================================================
    //                          Errors
    // =============================================================

    error NOT_BALANCER();
    error NOT_WHITELISTED();
    error INVALID_ASSET();
    error INVALID_DEBT();
    error INVALID_ASSET_BALANCE();
    error INVALID_DEBT_BALANCE();
    error INVALID_POSITION_VAULT();
    error DEBT_STILL_THERE();
    // =============================================================
    //                         Constants
    // =============================================================

    // balancer
    uint256 public constant FEE_SCALE = 1e18;
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 public switchFee;
    address public feeRecipient;
    mapping(address => bool) public vaultWhitelist;

    // =============================================================
    //                      Functions
    // =============================================================

    constructor(address _feeRecipient) {
        switchFee = 1e16;
        feeRecipient = _feeRecipient;
    }

    function setLeverageFee(uint256 newFee) external onlyOwner {
        require(newFee <= FEE_SCALE, 'Invalid fee');
        switchFee = newFee;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    function setVaultWhitelist(address vault, bool status) external onlyOwner {
        vaultWhitelist[vault] = status;
    }

    function switchLeverage(address vault, uint256 positionId, address newVault, bytes calldata data) external {
        IERC721(vault).transferFrom(msg.sender, address(this), positionId);

        // get position vault address
        address positionVault = IFactorLeverageVault(vault).positions(positionId);
        address owner = msg.sender;
        address asset = ILeverageStrategy(positionVault).asset();
        uint256 assetBalance = ILeverageStrategy(positionVault).assetBalance();
        address debtToken = ILeverageStrategy(positionVault).debtToken();
        uint256 debtBalance = ILeverageStrategy(positionVault).debtBalance();

        bytes memory params = abi.encode(
            vault,
            positionId,
            positionVault,
            newVault,
            asset,
            assetBalance,
            debtToken,
            debtBalance,
            owner
        );
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance + 10 ** IERC20Extended(debtToken).decimals();

        // execute flashloan
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
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
        (
            address vault,
            uint256 positionId,
            address positionVault,
            address newVault,
            address asset,
            uint256 assetBalance,
            address debtToken,
            uint256 debtBalance,
            address owner
        ) = abi.decode(params, (address, uint256, address, address, address, uint256, address, uint256, address));
        if (!vaultWhitelist[vault]) revert NOT_WHITELISTED();
        if (!vaultWhitelist[newVault]) revert NOT_WHITELISTED();
        if (ILeverageStrategy(positionVault).asset() != asset) revert INVALID_ASSET();
        if (ILeverageStrategy(positionVault).debtToken() != debtToken) revert INVALID_DEBT();
        if (ILeverageStrategy(positionVault).assetBalance() != assetBalance) revert INVALID_ASSET_BALANCE();
        if (ILeverageStrategy(positionVault).debtBalance() != debtBalance) revert INVALID_DEBT_BALANCE();
        if (IFactorLeverageVault(vault).positions(positionId) != positionVault) revert INVALID_POSITION_VAULT();
        IERC20(debtToken).safeApprove(positionVault, debtBalance);

        // repay all debt with flashloan
        ILeverageStrategy(positionVault).repay(debtBalance);
        if (ILeverageStrategy(positionVault).debtBalance() > 0) {
            ILeverageStrategy(positionVault).repay(debtBalance);
        }
        if (ILeverageStrategy(positionVault).debtBalance() > 0) {
            revert DEBT_STILL_THERE();
        }

        ILeverageStrategy(positionVault).withdraw(assetBalance);

        // create a new position on new vault
        (uint256 newPositionId, address newPositionVault) = IFactorLeverageVault(newVault).createPosition(
            asset,
            debtToken
        );

        IERC20(asset).safeApprove(newPositionVault, assetBalance);

        // supply to new vault
        uint256 assetFeeAmount = assetBalance.mul(switchFee).div(FEE_SCALE);
        IERC20(asset).safeTransfer(feeRecipient, assetFeeAmount);

        ILeverageStrategy(newPositionVault).supply(assetBalance - assetFeeAmount);
        ILeverageStrategy(newPositionVault).borrow(
            debtBalance + feeAmount + 10 ** IERC20Extended(debtToken).decimals()
        );

        // repay debt Flashloan
        IERC20(debtToken).safeTransfer(
            balancerVault,
            debtBalance + feeAmount + 10 ** IERC20Extended(debtToken).decimals()
        );

        // send new vuault to user
        IERC721(newVault).transferFrom(address(this), owner, newPositionId - 1);

        // send old vault to user
        IERC721(vault).transferFrom(address(this), owner, positionId);
        emit LeverageSwitched(
            vault,
            address(ILeverageStrategy(positionVault)),
            positionId,
            newVault,
            address(ILeverageStrategy(newPositionVault)),
            newPositionId - 1
        );
    }
}

