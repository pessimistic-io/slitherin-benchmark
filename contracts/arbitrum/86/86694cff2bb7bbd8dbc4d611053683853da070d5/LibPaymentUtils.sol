// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import "./SafeERC20.sol";

library LibPaymentUtils {
    using SafeERC20 for IERC20;

    event PaymentMade(address account, uint256[] currency, uint256[] assets, uint256[] pricePerAsset,uint256[] amounts);

    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    function pay(uint256[] calldata currency, uint256[] calldata assets, uint256[] calldata pricePerAsset,uint256[] calldata amounts, uint256 ethValue) internal {
        if((currency.length != assets.length) || (assets.length != pricePerAsset.length) || (pricePerAsset.length != amounts.length)) revert Errors.InvalidArrayLength();
        // Currencies: 0 = ETH, 1 = Magic, 2 = USDC, 3 = gFLY
        uint256[] memory expectedAmounts = new uint256[](4);
        for(uint256 i = 0; i < currency.length; i++) {
            if(currency[i] < 4) {
                expectedAmounts[currency[i]] += pricePerAsset[i] * amounts[i];
            } else {
                revert Errors.InvalidCurrency();
            }
        }
        if(ethValue != expectedAmounts[0]) revert Errors.InvalidEthAmount();
        (bool sent,) = payable(gs().paymentReceiver).call{value: ethValue}("");
        if(!sent) revert Errors.EthTransferFailed();
        IERC20(gs().magic).transferFrom(msg.sender, gs().paymentReceiver, expectedAmounts[1]);
        IERC20(gs().usdc).transferFrom(msg.sender, gs().paymentReceiver, expectedAmounts[2]);
        IERC20(gs().gFLY).transferFrom(msg.sender, gs().paymentReceiver, expectedAmounts[3]);
        emit PaymentMade(msg.sender, currency, assets, pricePerAsset, amounts);
    }

    function getPaymentReceiver() internal view returns (address) {
        return gs().paymentReceiver;
    }

    function getUSDC() internal view returns (address) {
        return gs().usdc;
    }
}

