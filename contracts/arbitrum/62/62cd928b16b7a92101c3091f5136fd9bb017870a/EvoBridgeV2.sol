// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";

import "./IBridgeERC20.sol";

contract EvoBridgeV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Withdraw {
        bytes32 id;
        address token;
        uint amount;
        uint bonus;
        address payable recipient;
        uint[] feeAmounts;
        address[] feeTargets;
        bytes data;
    }

    event Deposited(address indexed sender, address indexed token, uint8 indexed to, uint amount, bool bonus, bytes recipient);
    event Withdrawn(bytes32 indexed id, address indexed token, address indexed recipient, uint amount);

    address public owner;
    mapping(bytes32 => bool) public isWithdrawn;
    mapping(address => bool) public isSigner;
    mapping(address => bool) public isSenderContract;
    mapping(address => bool) public isRecipientContract;
    mapping(address => bool) public isOwnedToken;

    constructor() {
        setOwner(address(1));
    }

    function setOwner(address newOwner) public {
        require(msg.sender == owner || owner == address(0), 'forbidden');
        require(newOwner != address(0), 'owner can not be zero');
        owner = newOwner;
    }

    function setIsOwnedToken(address token, bool _owned) external {
        require(msg.sender == owner, 'forbidden');
        isOwnedToken[token] = _owned;
    }

    function setSigner(address account, bool state) external {
        require(msg.sender == owner, 'forbidden');
        isSigner[account] = state;
    }

    function setSenderContract(address account, bool state) external {
        require(msg.sender == owner, 'forbidden');
        isSenderContract[account] = state;
    }

    function setRecipientContract(address account, bool state) external {
        require(msg.sender == owner, 'forbidden');
        isRecipientContract[account] = state;
    }

    function deposit(address token, uint amount, uint8 to, bool bonus, bytes calldata recipient) external payable nonReentrant() {
        require(tx.origin == msg.sender || isSenderContract[msg.sender], 'call from unauthorized contract');
        require(address(token) != address(0) && amount > 0 && recipient.length > 0, 'invalid input');

        if (address(token) == address(1)) {
            require(amount == msg.value, 'value must equal amount');
        } else {
            takeTokens(token, msg.sender, amount);
        }

        emit Deposited(msg.sender, address(token), to, amount, bonus, recipient);
    }

    function withdraw(Withdraw[] calldata ws) external nonReentrant() {
        require(isSigner[msg.sender], 'forbidden');

        for (uint i = 0; i < ws.length; i++) {
            Withdraw memory w = ws[i];

            require(!isWithdrawn[w.id], 'already withdrawn');
            isWithdrawn[w.id] = true;

            if (address(w.token) == address(1)) {
                require(address(this).balance >= w.amount, 'too low token balance');
                Address.sendValue(w.recipient, w.amount);
            } else {
                giveTokens(w.token, w.recipient, w.amount);
            }

            if (w.bonus > 0) {
                require(address(this).balance >= w.bonus, 'too low token balance for bonus');
                (bool success, ) = w.recipient.call{value: w.bonus}('');
                require(success || Address.isContract(w.recipient)); // allow fail on contracts
            }

            if (address(w.token) != address(1) && w.feeAmounts.length > 0) {
                for (uint j = 0; j < w.feeAmounts.length; j++) {
                    giveTokens(w.token, w.feeTargets[j], w.feeAmounts[j]);
                }
            }

            if (w.data.length > 0) {
                require(isRecipientContract[w.recipient], 'call to unauthorized contract');
                Address.functionCall(w.recipient, w.data, 'call to recipient contract failed');
            }

            emit Withdrawn(w.id, address(w.token), w.recipient, w.amount);
        }
    }

    receive() external payable {}

    function takeTokens(address token, address from, uint256 amount) internal {
        require(IERC20(token).balanceOf(from) >= amount, 'too low token balance');
        if (isOwnedToken[token]) {
            IBridgeERC20(token).burnFrom(from, amount);
        } else {
            IERC20(token).safeTransferFrom(from, address(this), amount);
        }
    }

    function giveTokens(address token, address to, uint256 amount) internal {
        if (isOwnedToken[token]) {
            IBridgeERC20(token).mint(to, amount);
        } else {
            require(IERC20(token).balanceOf(address(this)) >= amount, 'too low token balance');
            IERC20(token).safeTransfer(to, amount);
        }
    }
}

