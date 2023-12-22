// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IVault.sol";

interface IWETH {
    function deposit() external payable;

    function depositTo(address to) external payable;

    function transfer(address to, uint value) external returns (bool);

    function balanceOf(address) external returns (uint256);

    function withdraw(uint) external;
}

contract Rebalancer is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    IVault public vault;
    IWETH public weth;

    event Initialized(address indexed vault, address indexed weth);
    event SetVault(address indexed vault);
    event SetWeth(address indexed weth);
    event Rebalance(uint256 indexed amount);
    event WithdrawToken(address indexed token, uint256 indexed amount);

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        require(
            msg.sender == address(vault),
            "Eth deposit's only available for vault."
        );
        _rebalance(msg.value);
    }

    /// @notice Initialization
    /// @param _vault vault address
    /// @param _weth weth address
    function init(IVault _vault, IWETH _weth) external initializer {
        require(address(_vault) != address(0), "Invalid vault address");
        require(address(_weth) != address(0), "Invalid weth address");

        __Ownable_init();
        vault = _vault;
        weth = _weth;
        emit Initialized(address(vault), address(weth));
    }

    /// @notice Set vault
    /// @param _vault vault address
    function setVault(IVault _vault) external onlyOwner {
        require(address(_vault) != address(0), "Invalid vault address");

        vault = _vault;
        emit SetVault(address(vault));
    }

    /// @notice Set weth
    /// @param _weth weth address
    function setWeth(IWETH _weth) external onlyOwner {
        require(address(_weth) != address(0), "Invalid weth address");

        weth = _weth;
        emit SetWeth(address(weth));
    }

    /// @notice withdraw token for emergency
    /// @param token token address to withdraw
    function withdrawToken(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 amount = address(this).balance;
            (bool success, ) = _msgSender().call{value: amount}("");
            require(success, "eth withdraw failed");
            emit WithdrawToken(token, amount);
        } else {
            uint256 amount = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(_msgSender(), amount);
            emit WithdrawToken(token, amount);
        }
    }

    /// @notice Deposit amount of weth and send back to vault
    /// @param amount amount of weth to deposit
    function _rebalance(uint256 amount) internal {
        uint256 beforeBalance = weth.balanceOf(address(this));
        weth.deposit{value: amount}();
        uint256 afterBalance = weth.balanceOf(address(this));
        require(
            afterBalance - beforeBalance == amount,
            "WETH deposit amount error"
        );
        IERC20(address(weth)).safeTransfer(address(vault), amount);
        emit Rebalance(amount);
    }
}

