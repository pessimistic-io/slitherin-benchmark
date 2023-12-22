pragma solidity 0.8.12;

import {Ownable} from "./Ownable.sol";
import {ECDSA} from "./ECDSA.sol";
import "./SafeTransferLib.sol";

contract BridgeFeeProvider is Ownable {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;
    using ECDSA for bytes32;

    address private immutable widoRouter;
    address private immutable verifyingSigner;

    mapping(address => uint256) public nonces;

    error InvalidSignature();
    error ExpiredSignature();
    error SenderNotApproved();
    error InvalidAddress();

    constructor(address _widoRouter, address _verifyingSigner) {
        if (_widoRouter == address(0) || _verifyingSigner == address(0)) {
            revert InvalidAddress();
        }
        widoRouter = _widoRouter;
        verifyingSigner = _verifyingSigner;
    }

    receive() external payable {}

    function swap(
        address user,
        address token,
        uint256 amount,
        uint256 exchangeAmount,
        uint256 deadline,
        bytes memory signature
    ) external {
        _requireFromWidoRouter();

        if (deadline < block.timestamp) {
            revert ExpiredSignature();
        }

        uint256 nonce = nonces[user];
        _verifySignature(user, token, amount, exchangeAmount, nonce, deadline, signature);

        nonces[user] = nonce + 1;

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        msg.sender.safeTransferETH(exchangeAmount);
    }

    function withdrawTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = ERC20(token).balanceOf(address(this));
            if (balance > 0) {
                ERC20(token).safeTransfer(msg.sender, balance);
            }
        }
    }

    function withdrawNative() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function getHash(
        address user,
        address token,
        uint256 amount,
        uint256 exchangeAmount,
        uint256 nonce,
        uint256 deadline
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(user, token, amount, exchangeAmount, nonce, deadline));
    }

    function _verifySignature(
        address user,
        address token,
        uint256 amount,
        uint256 exchangeAmount,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) internal view {
        bytes32 _hash = getHash(user, token, amount, exchangeAmount, nonce, deadline);

        if (verifyingSigner != _hash.toEthSignedMessageHash().recover(signature)) {
            revert InvalidSignature();
        }
    }

    function _requireFromWidoRouter() internal view {
        if (msg.sender != widoRouter) {
            revert SenderNotApproved();
        }
    }
}

