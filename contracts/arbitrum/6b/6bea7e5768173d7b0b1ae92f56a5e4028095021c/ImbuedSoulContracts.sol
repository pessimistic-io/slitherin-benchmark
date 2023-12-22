//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ImbuedSoulState.sol";

abstract contract ImbuedSoulContracts is Initializable, ImbuedSoulState {

    function __ImbuedSoulContracts_init() internal initializer {
        ImbuedSoulState.__ImbuedSoulState_init();
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function setPayment(
        address _magicAddress,
        address _paymentAddress,
        uint256 _paymentAmount)
    external
    onlyAdminOrOwner
    {
        magic = IMagic(_magicAddress);
        paymentAddress = _paymentAddress;
        magicCost = _paymentAmount;

        emit PaymentConfig(paymentAddress, magicCost);
    }

    modifier paymentIsSet() {
        require(isPaymentSet(), "ImbuedSoul: Payment isn't set");
        _;
    }

    function isPaymentSet() public view returns(bool) {
        return paymentAddress != address(0) &&
            address(magic) != address(0);
    }
}

