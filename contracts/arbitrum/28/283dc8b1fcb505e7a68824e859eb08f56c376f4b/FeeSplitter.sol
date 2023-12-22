// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Initializable.sol";
import "./PaymentSplitterUpgradeable.sol";

contract FeeSplitter is Initializable, PaymentSplitterUpgradeable {
    
    function initialize(
        address _communityWallet,
        address _treasureWallet,
        uint256 _communityShare,
        uint256 _treasureShare
    ) external initializer {
        address[] memory payees = new address[](2);
        uint256[] memory shares = new uint256[](2);

        payees[0] = _communityWallet;
        payees[1] = _treasureWallet;
        shares[0] = _communityShare;
        shares[1] = _treasureShare;

        PaymentSplitterUpgradeable.__PaymentSplitter_init(payees, shares);
    }
}
