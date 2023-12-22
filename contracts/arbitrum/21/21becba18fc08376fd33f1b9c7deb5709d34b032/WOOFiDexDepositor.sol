// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

// OpenZeppelin Contracts
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

// Uniswap Periphery
import {TransferHelper} from "./TransferHelper.sol";

// Local Contracts
import {IWooRouterV2} from "./IWooRouterV2.sol";
import {IWOOFiDexDepositor} from "./IWOOFiDexDepositor.sol";
import {IWOOFiDexVault} from "./IWOOFiDexVault.sol";

/// @title WOOFi Dex Depositor for Local Chain Swap to Deposit
contract WOOFiDexDepositor is IWOOFiDexDepositor, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /* ----- Constants ----- */

    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    address public wooRouter;

    bool public orderlyFeeToggle;

    mapping(address => address) public woofiDexVaults; // token address => WOOFiDexVault address

    receive() external payable {}

    /* ----- Constructor ----- */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _wooRouter) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        wooRouter = _wooRouter;
    }

    /* ----- Functions ----- */

    function swap(
        address payable to,
        Infos calldata infos,
        VaultDeposit calldata vaultDeposit
    ) external payable whenNotPaused nonReentrant {
        require(to != address(0), "WOOFiDexDepositor: to not allow");
        require(
            infos.fromToken != address(0) && infos.toToken != address(0),
            "WOOFiDexDepositor: infos.token not allow"
        );
        require(woofiDexVaults[infos.toToken] != address(0), "WOOFiDexDepositor: woofiDexVault not allow");

        address sender = _msgSender();
        uint256 toAmount;

        if (infos.fromToken == NATIVE_PLACEHOLDER) {
            uint256 nativeAmount = msg.value;
            require(infos.fromAmount <= nativeAmount, "WOOFiDexDepositor: nativeAmount not enough");
            toAmount = IWooRouterV2(wooRouter).swap{value: infos.fromAmount}(
                infos.fromToken,
                infos.toToken,
                infos.fromAmount,
                infos.minToAmount,
                payable(address(this)),
                to
            );
        } else {
            TransferHelper.safeTransferFrom(infos.fromToken, sender, address(this), infos.fromAmount);
            TransferHelper.safeApprove(infos.fromToken, address(wooRouter), infos.fromAmount);
            toAmount = IWooRouterV2(wooRouter).swap(
                infos.fromToken,
                infos.toToken,
                infos.fromAmount,
                infos.minToAmount,
                payable(address(this)),
                to
            );
        }

        IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = _depositTo(
            to,
            infos.toToken,
            infos.orderlyNativeFees,
            vaultDeposit,
            toAmount
        );

        emit WOOFiDexSwap(
            sender,
            to,
            infos.fromToken,
            infos.fromAmount,
            infos.toToken,
            infos.minToAmount,
            toAmount,
            infos.orderlyNativeFees,
            vaultDepositFE.accountId,
            vaultDepositFE.brokerHash,
            vaultDepositFE.tokenHash,
            vaultDepositFE.tokenAmount
        );
    }

    function _depositTo(
        address to,
        address toToken,
        uint256 orderlyNativeFees,
        VaultDeposit memory vaultDeposit,
        uint256 tokenAmount
    ) internal returns (IWOOFiDexVault.VaultDepositFE memory) {
        IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = IWOOFiDexVault.VaultDepositFE(
            vaultDeposit.accountId,
            vaultDeposit.brokerHash,
            vaultDeposit.tokenHash,
            uint128(tokenAmount)
        );
        address woofiDexVault = woofiDexVaults[toToken];
        uint256 depositToFees = orderlyFeeToggle ? orderlyNativeFees : 0;
        if (toToken == NATIVE_PLACEHOLDER) {
            IWOOFiDexVault(woofiDexVault).testWoofiDeposit{value: tokenAmount + depositToFees}(to, vaultDepositFE);
        } else {
            TransferHelper.safeApprove(toToken, woofiDexVault, tokenAmount);
            if (depositToFees == 0) {
                IWOOFiDexVault(woofiDexVault).testWoofiDeposit(to, vaultDepositFE);
            } else {
                IWOOFiDexVault(woofiDexVault).testWoofiDeposit{value: depositToFees}(to, vaultDepositFE);
            }
        }

        return vaultDepositFE;
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WOOFiDexDepositor: _wooRouter cant be zero");
        wooRouter = _wooRouter;
    }

    function setOrderlyFeeToggle(bool _orderlyFeeToggle) external onlyOwner {
        orderlyFeeToggle = _orderlyFeeToggle;
    }

    function setWOOFiDexVault(address token, address woofiDexVault) external onlyOwner {
        require(woofiDexVault != address(0), "WOOFiDexDepositor: woofiDexVault cant be zero");
        woofiDexVaults[token] = woofiDexVault;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        address sender = _msgSender();
        if (stuckToken == NATIVE_PLACEHOLDER) {
            TransferHelper.safeTransferETH(sender, address(this).balance);
        } else {
            uint256 amount = IERC20Upgradeable(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, sender, amount);
        }
    }
}

