// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./LendVault.sol";
import "./ILendVault.sol";
import "./IReserve.sol";
import "./IStrategyVault.sol";
import "./IOracle.sol";
import "./AccessControl.sol";
import "./AddressArray.sol";

/**
 * @notice Reserve acts as a buffer to provide instant liquidity to the lendVault
 * and as insurance in case borrowers are unable to pay back debts
 */
contract Reserve is AccessControl, ERC1155HolderUpgradeable, IReserve {
    using SafeERC20 for IERC20;
    using AddressArray for address[];

    uint public slippage;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     */
    function initialize(address _addressProvider, uint _slippage) external initializer {
        __AccessControl_init(_addressProvider);
        require(_slippage<=PRECISION, "E12");
        slippage = _slippage;
        __ERC1155Holder_init();
    }

    modifier onlyLendVault() {
        require(msg.sender==provider.lendVault(), "Unauthorized");
        _;
    }

    /// @inheritdoc IReserve
    function expectedBalance() external view returns (uint balance) {
        address[] memory strategyVaults = provider.getVaults();
        IOracle oracle = IOracle(provider.oracle());
        ILendVault lendVault = ILendVault(provider.lendVault());
        if (address(lendVault)==address(0)) return 0;
        address[] memory depositTokens = new address[](strategyVaults.length);
        for (uint i = 0; i<strategyVaults.length; i++) {
            address vault = strategyVaults[i];
            address depositToken = IStrategyVault(vault).depositToken();
            if (!depositTokens.exists(depositToken)) {
                depositTokens[i] = depositToken;
                uint tokenBalance = IERC20(depositToken).balanceOf(address(this));
                balance+=oracle.getValue(depositToken, tokenBalance);
            }
        }

        address[] memory lendVaultTokens = lendVault.getSupportedTokens();
        for (uint i = 0; i<lendVaultTokens.length; i++) {
            address token = lendVaultTokens[i];
            uint tokenBalance = lendVault.tokenBalanceOf(address(this), token);
            balance+=oracle.getValue(token, tokenBalance);
        }
    }

    /// @inheritdoc IReserve
    function requestFunds(address token, uint amount) external onlyLendVault returns (uint fundsSent) {
        uint balance = IERC20(token).balanceOf(address(this));
        if (amount<=balance) {
            IERC20(token).safeTransfer(msg.sender, amount);
            fundsSent = amount;
        } else {
            address[] memory strategyVaults = provider.getVaults();
            ISwapper swapper = ISwapper(provider.swapper());
            for (uint i = 0; i<strategyVaults.length; i++) {
                address vault = strategyVaults[i];
                address depositToken = IStrategyVault(vault).depositToken();
                uint depositTokenBalance = IERC20(depositToken).balanceOf(address(this));
                if (balance < amount) {
                    uint depositTokenNeeded = swapper.getAmountIn(depositToken, amount - balance, token);
                    _approve(address(swapper), depositToken, Math.min(depositTokenBalance, depositTokenNeeded));
                    swapper.swapExactTokensForTokens(depositToken, Math.min(depositTokenBalance, depositTokenNeeded), token, slippage);
                    balance = IERC20(token).balanceOf(address(this));
                } else {
                    break;
                }
            }
            IERC20(token).safeTransfer(msg.sender, Math.min(balance, amount));
            fundsSent = Math.min(balance, amount);
        }
    }

    /// @inheritdoc IReserve
    function burnLendVaultShares(address token, uint shares) external restrictAccess(GOVERNOR) {
        ILendVault(provider.lendVault()).withdrawShares(token, shares);
    }

    /// @inheritdoc IReserve
    function withdraw(address token, uint amount) external restrictAccess(GOVERNOR) {
        IERC20(token).safeTransfer(provider.governance(), amount);
    }

    /// @inheritdoc IReserve
    function setSlippage(uint _slippage) external restrictAccess(GOVERNOR) {
        require(_slippage<=PRECISION, "E12");
        slippage = _slippage;
    }

    /**
     * @notice Set approval to max for spender if approval isn't high enough
     */
    function _approve(address spender, address token, uint amount) public {
        uint allowance = IERC20(token).allowance(address(this), spender);
        if(allowance<amount) {
            IERC20(token).safeIncreaseAllowance(spender, 2**256-1-allowance);
        }
    }
}
