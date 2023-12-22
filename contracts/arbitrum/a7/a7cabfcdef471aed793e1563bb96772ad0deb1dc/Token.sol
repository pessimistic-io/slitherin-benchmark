// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./Pausable.sol";

contract SLID is ERC20, ERC20Burnable, Ownable, Pausable {
    address public sushiSwapV2Pair;
    address public receiptFeeAddress1;
    address public receiptFeeAddress2;
    uint256 public sellFeeRate;
    uint256 public buyFeeRate;

    constructor() ERC20("Solid Finance", "SLID") {
        _mint(_msgSender(), 4000 * 10 ** decimals());
    }

    function updateExchangeFee(
        address _sushiSwapV2Pair,
        address _receiptFeeAddress1,
        address _receiptFeeAddress2,
        uint256 _sellFeeRate,
        uint256 _buyFeeRate
    ) external onlyOwner {
        sushiSwapV2Pair = _sushiSwapV2Pair;
        receiptFeeAddress1 = _receiptFeeAddress1;
        receiptFeeAddress2 = _receiptFeeAddress2;
        sellFeeRate = _sellFeeRate;
        buyFeeRate = _buyFeeRate;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        uint256 transferFeeRate = recipient == sushiSwapV2Pair
            ? sellFeeRate
            : (sender == sushiSwapV2Pair ? buyFeeRate : 0);

        if (transferFeeRate > 0 && sender != address(this) && recipient != address(this)) {
            uint256 _fee = (amount * transferFeeRate) / 10000;
            uint256 _fee1 = _fee / 2;
            uint256 _fee2 = _fee - _fee1;

            // Buy sell fee
            super._transfer(sender, receiptFeeAddress1, _fee1);
            super._transfer(sender, receiptFeeAddress2, _fee2);
            amount = amount - _fee;
        }

        super._transfer(sender, recipient, amount);
    }
}

