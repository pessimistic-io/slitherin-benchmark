pragma solidity ^0.8.0;
import "./IWETH.sol";
import "./BoringERC20.sol";

abstract contract MintSaleBase {
    using BoringERC20 for IERC20;
    IWETH public immutable WETH;
    constructor(IWETH WETH_) {
        WETH = WETH_;
    }
    function getPayment(IERC20 paymentToken, uint256 amount) internal {
        if (address(paymentToken) == address(WETH)) {
            WETH.deposit{value: amount}();
        } else {
            paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        }
    }
}
