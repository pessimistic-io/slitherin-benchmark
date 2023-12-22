// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
import "./SidGiftCardRegistrar.sol";
import "./ISidPriceOracle.sol";
import "./SidGiftCardVoucher.sol";
import "./ReentrancyGuard.sol";

contract SidGiftCardController is Ownable, ReentrancyGuard {
    SidGiftCardRegistrar public registrar;
    ISidPriceOracle public priceOracle;
    SidGiftCardVoucher public voucher;
    
    constructor(SidGiftCardRegistrar _registrar, ISidPriceOracle _priceOracle, SidGiftCardVoucher _voucher) {
        registrar = _registrar;
        priceOracle = _priceOracle;
        voucher = _voucher;
    }

    function price(uint256[] calldata ids, uint256[] calldata amounts) external view returns (uint256) {
        return priceOracle.giftcard(ids, amounts).base;
    }

    function batchRegister(uint256[] calldata ids, uint256[] calldata amounts) nonReentrant external payable {
        require(voucher.isValidVoucherIds(ids), "Invalid voucher id");
        uint256 cost = priceOracle.giftcard(ids, amounts).base;
        require(msg.value >= cost, "Insufficient funds");
        registrar.batchRegister(msg.sender, ids, amounts);
        // Refund any extra payment
        if (msg.value > cost) {
            (bool sent, ) = msg.sender.call{value: msg.value - cost}("");
            require(sent, "Failed to send Ether");
        }
    }

    function setNewPriceOracle(ISidPriceOracle _priceOracle) public onlyOwner {
        priceOracle = _priceOracle;
    }
    
    function withdraw() public onlyOwner nonReentrant {
        (bool sent, ) = owner().call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }
}

