// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import {EIP712} from "./EIP712.sol";
import {ECDSA} from "./ECDSA.sol";
import {IERC20} from "./IERC20.sol";

contract GPPrizePool is Ownable, Pausable, EIP712("GPPrizePool", "1") {
    event MoneyWithdrawn(address user, uint256 amount);
    event OrderFullfilled(uint256 indexed orderId, address user, uint256 amount);

    IERC20 public usdt;
    address public approvalSigner;
    // orderId => payment amount
    mapping(uint256 => uint256) public fulfilledOrders;
    bytes32 internal constant _ORDER_PAY_TYPE_HASH =
        keccak256("OrderPay(uint256 deadline,address user,uint256 orderId,uint256 amount)");

    constructor(address usdt_) {
        usdt = IERC20(usdt_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setApprovalSigner(address signer) external onlyOwner {
        approvalSigner = signer;
    }

    function withdraw(uint256 amount) external onlyOwner {
        usdt.transfer(_msgSender(), amount);
        emit MoneyWithdrawn(_msgSender(), amount);
    }

    function orderPay(
        uint256 deadline,
        uint256 orderId,
        uint256 amount,
        bytes calldata signature
    ) external whenNotPaused {
        require(amount > 0, "GPPrizePool: Amount must be greater than 0");
        require(deadline >= block.timestamp, "GPPrizePool: Signature is expired");
        require(fulfilledOrders[orderId] == 0, "GPPrizePool: Order is already used");
        require(
            _verifyPayOrderSigner(deadline, orderId, amount, signature),
            "GPPrizePool: Signature is invalid"
        );
        fulfilledOrders[orderId] = amount;
        usdt.transferFrom(_msgSender(), address(this), amount);
        emit OrderFullfilled(orderId, _msgSender(), amount);
    }

    function _verifyPayOrderSigner(
        uint256 deadline,
        uint256 orderId,
        uint256 amount,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_ORDER_PAY_TYPE_HASH, deadline, _msgSender(), orderId, amount))
        );
        return ECDSA.recover(digest, signature) == approvalSigner;
    }
}

