// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IAccount.sol";
import "./IProtocolsManager.sol";
import "./Constant.sol";

contract Account is IAccount, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public walletMain;
    address public walletOneCT;
    IProtocolsManager public protocolsManager;

    modifier onlyAccountOwner() {
        require(msg.sender == walletMain || msg.sender == walletOneCT, "Not account owner");
        _;
    }

    event Withdraw(address to, address token, uint amount);
    event ReplaceOneCT(address oldOneCT, address newOneCT);

    constructor(address main, address oneCT, IProtocolsManager manager) {
        require(main != address(0) && oneCT != Constant.ZERO_ADDRESS, "Invalid address");
        walletMain = main;
        walletOneCT = oneCT;
        protocolsManager = manager;
    }

    function tradeETH(string memory protocolName, bytes calldata data, uint value) external onlyAccountOwner nonReentrant {
        _trade(protocolName, data, value);
    }

    function tradeERC20(string memory protocolName, bytes calldata data) external onlyAccountOwner nonReentrant {
        _trade(protocolName, data, 0);
    }

    // Allow Eth deposit
    receive() external payable {}

    function withdrawETH(uint amount) external onlyAccountOwner nonReentrant {
        (bool success, ) = walletMain.call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdraw(walletMain, address(0), amount);
    }

    function withdrawERC20(address token, uint amount) external onlyAccountOwner nonReentrant {
        IERC20(token).safeTransfer(walletMain, amount); 
        emit Withdraw(walletMain, token, amount);
    }

    function replaceOneCT(address newOneCT) external {
        require(msg.sender == walletMain, "No rights");
        require(newOneCT != Constant.ZERO_ADDRESS, "Invalid address");
        emit ReplaceOneCT(walletOneCT, newOneCT);
        walletOneCT = newOneCT;
    }

    function approveERC20(string memory protocolName, address token, uint amount) external onlyAccountOwner {
        _setApprove(protocolName, token, amount);
    }

    function revokeApprovalERC20(string memory protocolName, address token) external onlyAccountOwner {
        _setApprove(protocolName, token, 0);
    }

    function query() external override view returns (address main, address oneCT) {
        main = walletMain;
        oneCT = walletOneCT;
    }

    function _trade(string memory name, bytes calldata data, uint value) private {
        (address protocol, bool allowed) = protocolsManager.query(name);
        require(protocol != Constant.ZERO_ADDRESS && allowed, "Protocol not allowed");

        (bool success, bytes memory result) = protocol.call{value: value}(data);
        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577 (return the original revert reason)
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }

    function _setApprove(string memory protocolName, address token, uint amount) private {
        (address contractAddress, bool allowed) = protocolsManager.query(protocolName);
        require(contractAddress != Constant.ZERO_ADDRESS && allowed, "Protocol not allowed");
        require(protocolsManager.isCurrencySupported(protocolName, token), "Currency not supported");
        IERC20(token).approve(contractAddress, amount);
    }
}

