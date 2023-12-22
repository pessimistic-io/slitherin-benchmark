// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

// Library imports
import { LibPaymentUtils } from "./LibPaymentUtils.sol";

// Contract imports
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract BGPaymentFacet is WithModifiers, ReentrancyGuard {
    event PaymentMade(address account, uint256[] currency, uint256[] assets, uint256[] pricePerAsset,uint256[] amounts);

    // Currencies: 0 = ETH, 1 = Magic, 2 = USDC, 3 = gFLY
    function pay(uint256[] calldata currency, uint256[] calldata assets, uint256[] calldata pricePerAsset,uint256[] calldata amounts) external nonReentrant payable {
        LibPaymentUtils.pay(currency, assets, pricePerAsset, amounts, msg.value);
    }

    function getPaymentReceiver() external view returns (address) {
        return LibPaymentUtils.getPaymentReceiver();
    }

    function getUSDC() external view returns (address) {
        return LibPaymentUtils.getUSDC();
    }
}

