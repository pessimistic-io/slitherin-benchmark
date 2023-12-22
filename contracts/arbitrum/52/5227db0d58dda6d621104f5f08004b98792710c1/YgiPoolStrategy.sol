pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./UniswapV3Utils.sol";
import "./ITokenStrategy.sol";
import "./IEthStrategy.sol";
import "./IRldVault.sol";
import "./IRldEthVault.sol";
import "./IRldBaseVault.sol";
import "./IWETH.sol";
import "./Stoppable.sol";

contract YgiPoolStrategy is Ownable, Stoppable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 constant MULTIPLIER = 10 ** 18;

    address public ygiInputToken;
    address public uniRouter;
    address public weth;

    struct Route {
        address[] aToBRoute;
        uint24[] aToBFees;
        bytes path;
    }

    struct YgiComponent {
        address inputToken;
        address vault;
        uint256 allocation;
        Route route;
        Route backRoute;
    }

    uint256 totalAllocation;

    YgiComponent[] public ygiComponents;
    uint256 DIVISOR;

    //todo: actually use this
    uint256 public lastPoolDepositTime;
    mapping(address => mapping(address => uint256)) public userToVaultToAmount;

    event Deposit(uint256 deposited);
    event Withdraw(uint256 withdrawRatio, uint256 withdrawAmount);
    event WithdrawFailureSkipped();

    constructor(
        address _inputToken,
        address _uniRouter,
        address _weth
    ) {
        uniRouter = _uniRouter;
        ygiInputToken = _inputToken;
        DIVISOR = 10 ** ERC20(_inputToken).decimals();
        weth = _weth;
        _giveAllowance(uniRouter, ygiInputToken);
    }

    function rebalance(address _vault, uint256 amount) public onlyOwner {
        YgiComponent storage componentToRebalance = ygiComponents[getIndex(_vault)];
        IBaseStrategy(IRldBaseVault(componentToRebalance.vault).strategy()).withdraw(amount);
        uint256 withdrawnBalance = IERC20(componentToRebalance.inputToken).balanceOf(address(this));
        if (withdrawnBalance > 0) {
            swapTokens(withdrawnBalance, componentToRebalance.backRoute);
        }
        depositLeftOverInputTokens();
    }

    function depositLeftOverInputTokens() internal {
        uint256 inputTokenAmount = IERC20(ygiInputToken).balanceOf(address(this));
        if (inputTokenAmount > 0) {
            // todo: handle vaults that have different input/output than their strategies
            for (uint i = 0; i < ygiComponents.length; i++) {
                uint256 allocation = ygiComponents[i].allocation;
                uint256 amount = (inputTokenAmount * (allocation * MULTIPLIER / totalAllocation)) / MULTIPLIER;
                uint amountReceived = swapTokens(amount, ygiComponents[i].route);
                if (amountReceived > 0) {
                    address strategy = IRldBaseVault(ygiComponents[i].vault).strategy();
                    if (IBaseStrategy(strategy).inputToken() == address(0)) {
                        IWETH(weth).withdraw(amountReceived);
                        IEthStrategy(strategy).deposit{value: amountReceived}();
                    } else {
                        IERC20(ygiComponents[i].inputToken).safeTransfer(strategy, amountReceived);
                        ITokenStrategy(strategy).deposit();
                    }
                }
            }
        }
    }

    function getIndex(address _vault) public view returns (uint256) {
        for (uint i = 0; i < ygiComponents.length; i++) {
            if (ygiComponents[i].vault == _vault) {
                return i;
            }
        }
        revert("Vault not found");
    }

    function registerYgiComponent(
        address inputToken,
        address vaultAddress,
        uint256 allocation,
        address[] memory _route,
        uint24[] memory _fee,
        address[] memory _backRoute,
        uint24[] memory _backFee
    ) public onlyOwner {
        Route memory route = Route(_route, _fee, UniswapV3Utils.routeToPath(_route, _fee));
        Route memory backRoute = Route(_backRoute, _backFee, UniswapV3Utils.routeToPath(_backRoute, _backFee));
        YgiComponent memory ygiComponent = YgiComponent(
            inputToken,
            vaultAddress,
            allocation,
            route,
            backRoute
        );
        totalAllocation += allocation;
        ygiComponents.push(ygiComponent);
        _giveAllowance(uniRouter, inputToken);
        _giveAllowance(vaultAddress, inputToken);
    }

    function deregisterYgiComponent(
        address _vault,
        bool skipOnFail
    ) public onlyOwner {
        uint256 i = getIndex(_vault);
        YgiComponent storage component = ygiComponents[i];
        totalAllocation -= component.allocation;
        sunsetStrategy(component, skipOnFail);
        ygiComponents[i] = ygiComponents[ygiComponents.length - 1];
        ygiComponents.pop();
        depositLeftOverInputTokens();
    }

    function sunsetStrategy(YgiComponent storage component, bool skipOnFail) internal {
        IRldBaseVault vault = IRldBaseVault(component.vault);
        uint256 balance = vault.balanceOf(address(this));

        try vault.withdraw(balance) {
            // check if ygiInputToken is inputToken
            uint256 withdrawnBalance = IERC20(component.inputToken).balanceOf(address(this));
            if (withdrawnBalance > 0) {
                swapTokens(withdrawnBalance, component.backRoute);
            }
        } catch {
            if (!skipOnFail) {
                revert("WithdrawAll failed");
            }
        }
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint _totalAmount) public nonReentrant whenNotStopped {
        IERC20(ygiInputToken).safeTransferFrom(msg.sender, address(this), _totalAmount);
        for (uint i = 0; i < ygiComponents.length; i++) {
            uint256 allocation = ygiComponents[i].allocation;
            uint256 amount = (_totalAmount * (allocation * MULTIPLIER / totalAllocation)) / MULTIPLIER;
            uint amountReceived = swapTokens(amount, ygiComponents[i].route);
            if (amountReceived > 0) {
                uint256 vaultBalanceBefore = IRldBaseVault(ygiComponents[i].vault).balanceOf(address(this));
                if (ygiComponents[i].inputToken == address(0)) {
                    IWETH(weth).withdraw(amountReceived);
                    IRldEthVault(ygiComponents[i].vault).deposit{value: amountReceived}();
                } else {
                    IRldVault(ygiComponents[i].vault).deposit(amountReceived);
                }
                uint256 vaultBalanceAfter = IRldBaseVault(ygiComponents[i].vault).balanceOf(address(this));
                userToVaultToAmount[msg.sender][address(ygiComponents[i].vault)] += vaultBalanceAfter - vaultBalanceBefore;
            }
        }
        lastPoolDepositTime = block.timestamp;
        emit Deposit(_totalAmount);
    }

    function swapTokens(uint256 amount, Route memory route) internal returns (uint256) {
        if (route.path.length == 0) {
            return amount;
        }
        if (amount > 0) {
            return UniswapV3Utils.swap(uniRouter, route.path, amount);
        }
        return 0;
    }

    function _giveAllowance(address spender, address token) internal {
        if (IERC20(token).allowance(address(this), spender) < type(uint).max) {
            IERC20(token).safeApprove(spender, type(uint).max);
        }
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _ratio, bool skipOnWithdrawFail, bool withdrawIndividual) external nonReentrant {
        require(_ratio <= DIVISOR, "Ratio too high");
        uint256 withdrawnTotalAmount = 0;
        for (uint i = 0; i < ygiComponents.length; i++) {
            IRldBaseVault vault = IRldBaseVault(ygiComponents[i].vault);
            uint256 balance = userToVaultToAmount[msg.sender][address(vault)];
            uint256 amountToWithdraw = balance * _ratio / DIVISOR;

            uint256 vaultBalanceBefore = vault.balanceOf(address(this));
            //todo check this again: seeems insecure??
            try vault.withdraw(amountToWithdraw) {
                uint256 vaultBalanceAfter = vault.balanceOf(address(this));
                userToVaultToAmount[msg.sender][address(ygiComponents[i].vault)] -= vaultBalanceBefore - vaultBalanceAfter;
            } catch {
                if (!skipOnWithdrawFail) {
                    revert("Withdrawal failed");
                } else {
                    emit WithdrawFailureSkipped();
                }
            }

            if (!withdrawIndividual) {
                uint256 withdrawnBalance = IERC20(ygiComponents[i].inputToken).balanceOf(address(this));
                if (withdrawnBalance > 0) {
                    withdrawnTotalAmount += swapTokens(withdrawnBalance, ygiComponents[i].backRoute);
                }
            }
        }

        if (withdrawIndividual) {
            for (uint i = 0; i < ygiComponents.length; i++) {
                uint256 withdrawnBalance = IERC20(ygiComponents[i].inputToken).balanceOf(address(this));
                IERC20(ygiComponents[i].inputToken).transfer(msg.sender, withdrawnBalance);
            }
        } else {
            IERC20(ygiInputToken).safeTransfer(msg.sender, withdrawnTotalAmount);
            emit Withdraw(_ratio, withdrawnTotalAmount);
        }
    }

    function setUniRouter(address _uniRouter) external onlyOwner {
        uniRouter = _uniRouter;
    }

    function panic() public onlyOwner {
        stop();
    }

    function stop() public onlyOwner {
        _stop();
    }

    function resume() public onlyOwner {
        _resume();
    }
}

