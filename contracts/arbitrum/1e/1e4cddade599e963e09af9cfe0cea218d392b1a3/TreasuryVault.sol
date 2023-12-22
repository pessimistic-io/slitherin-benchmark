// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Strategy Vault.
 * @author  André Ferreira

  * @dev    VERSION: 1.0
 *          DATE:    2023.08.29
*/

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract TreasuryVault is Ownable {
    using SafeERC20 for IERC20;

    event TreasuryCreated(address creator, address treasuryAddress);
    event EtherReceived(address indexed sender, uint256 amount);
    event ERC20Received(address indexed sender, uint256 amount, address asset);
    event NativeWithdrawal(address indexed owner, uint256 amount);
    event ERC20Withdrawal(
        address indexed owner,
        address indexed token,
        uint256 amount
    );

    constructor() {
        emit TreasuryCreated(msg.sender, address(this));
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    function withdrawNative(uint256 _amount) public onlyOwner {
        require(_amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = owner().call{value: _amount}("");
        require(success, "Ether transfer failed");
        emit NativeWithdrawal(owner(), _amount);
    }

    function depositERC20(uint256 _amount, address _asset) public {
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        emit ERC20Received(msg.sender, _amount, _asset);
    }

    function withdrawERC20(
        address _tokenAddress,
        uint256 _amount
    ) public onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        require(
            _amount <= token.balanceOf(address(this)),
            "Insufficient balance"
        );
        (bool success, ) = _tokenAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                owner(),
                _amount
            )
        );
        require(success, "Token transfer failed");
        emit ERC20Withdrawal(owner(), _tokenAddress, _amount);
    }
}

