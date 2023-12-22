//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

///@author @JayusJay || https://github.com/jayusjay
contract MultiSend is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event MultiSendErc20(address indexed sender, address indexed token, address[] recipients, uint256[] amounts);
    event MultiSendEth(address indexed sender, address[] recipients, uint256[] amounts);
    event ExcessEthReturned(address indexed sender, uint256 amount);
    event Sweep(address indexed token, address indexed recipient, uint256 erc20Amount, uint256 ethAmount);

    event EthSentToUser(address indexed user, uint256 amount);

    /**
     * @notice Send ERC20 tokens to multiple recipients
     * @notice Sender must have approved this contract to spend the ERC20 tokens in their wallet
     *! @notice DO NOT SEND ERC20 TOKENS DIRECTLY TO THIS CONTRACT else anyone can sweep them
     * @param token The address of the ERC20 token to send
     * @param recipients The addresses of the recipients
     * @param amounts The amounts to send to each recipient respectively.
     */
    function multiSendErc20(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant {
        require(recipients.length == amounts.length, "MultiSend: Invalid input");
        require(token != address(0), "MultiSend: Invalid token");
        IERC20 erc20 = IERC20(token);

        uint256 i;
        uint256 recipientsCount = recipients.length;
        for (; i < recipientsCount; ) {
            require(recipients[i] != address(0), "MultiSend: Invalid recipient");
            require(amounts[i] != 0, "MultiSend: Invalid amount");
            erc20.safeTransferFrom(msg.sender, recipients[i], amounts[i]);

            unchecked {
                ++i;
            }
        }

        emit MultiSendErc20(msg.sender, token, recipients, amounts);
    }

    /**
     * @notice Send ETH to multiple recipients
     * @notice DO NOT SEND ETH DIRECTLY TO THIS CONTRACT else anyone can sweep them, use the msg.value field instead
     * @param recipients The addresses of the recipients
     * @param amounts The amounts to send to each recipient respectively.
     * @param strict If true, revert if any of the transfers fail. If false, continue with the rest of the transfers.
     */
    function multiSendEth(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bool strict
    ) external payable nonReentrant {
        require(recipients.length == amounts.length, "MultiSend: Invalid input");
        require(msg.value != 0, "MultiSend: Insufficient ETH");

        uint256 i;
        uint256 recipientsCount = recipients.length;
        for (; i < recipientsCount; ) {
            require(recipients[i] != address(0), "MultiSend: Invalid recipient");
            require(amounts[i] != 0, "MultiSend: Invalid amount");
            (bool sent, ) = payable(recipients[i]).call{ value: amounts[i] }("");

            if (strict) {
                require(sent, "MultiSend: Failed to send ETH");
            }

            if (sent) {
                emit EthSentToUser(recipients[i], amounts[i]);
            } else emit EthSentToUser(recipients[i], 0);

            unchecked {
                ++i;
            }
        }

        uint256 excessEth = address(this).balance;
        if (excessEth != 0) {
            (bool success, ) = payable(msg.sender).call{ value: excessEth }("");
            //solhint-disable-next-line reason-string
            require(success, "MultiSend: Failed to return excess ETH");
            emit ExcessEthReturned(msg.sender, excessEth);
        }

        emit MultiSendEth(msg.sender, recipients, amounts);
    }

    function sweep(address token) external onlyOwner nonReentrant {
        require(token != address(0), "MultiSend: Invalid token");
        IERC20 erc20 = IERC20(token);
        uint256 erc20Balance = erc20.balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        if (erc20Balance != 0) {
            erc20.safeTransfer(msg.sender, erc20.balanceOf(address(this)));
        }

        if (ethBalance != 0) {
            (bool success, ) = payable(msg.sender).call{ value: ethBalance }("");
            require(success, "MultiSend: Failed to sweep ETH");
        }

        emit Sweep(token, msg.sender, erc20Balance, ethBalance);
    }

    /// @notice Fallback function to allow this contract to receive ETH from other contracts
    receive() external payable {}
}

