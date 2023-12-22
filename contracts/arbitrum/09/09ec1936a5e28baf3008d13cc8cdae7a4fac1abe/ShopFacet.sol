// SPDX-License-Identifier: None
pragma solidity 0.8.10;

import "./console.sol";
import "./IERC20.sol";
import {WithStorage, WithModifiers} from "./LibStorage.sol";
import "./LibPrices.sol";
import {LibAccessControl} from "./LibAccessControl.sol";

/**
 * Handles all purchases done to the protocol
 */

contract ShopFacet is WithStorage, WithModifiers {
    event FoundersPackPurchased(
        address indexed owner,
        uint256 indexed characterNumber
    );

    // event TeamFoundersPackPurchased(address indexed owner);

    function purchaseFoundersPack() external payable pausable {
        require(_ss().foundersPackPurchaseAllowed, "Purchase disabled");

        uint256 cost = getFoundersPackFullCost();

        require(
            msg.value >= ((cost * 960) / 1000) &&
                msg.value <= (cost * 1040) / 1000,
            "Payment amount missmatch"
        );

        payable(_acs().forgerAddress).transfer(
            (cost * _ss().botsFeePercentage) / 200
        );
        payable(_acs().borisAddress).transfer(
            (cost * _ss().botsFeePercentage) / 200
        );

        _ss().purchasedFoundersPackByAddress[msg.sender] = true;
        uint256 characterNumber = ++_ss().purchasedFoundersPacksCount;

        emit FoundersPackPurchased(msg.sender, characterNumber);
    }

    // function purchaseTeamFoundersPack(address recipient)
    //     external
    //     payable
    //     pausable
    //     roleOnly(LibAccessControl.Roles.ADMIN)
    // {
    //     require(_ss().foundersPackPurchaseAllowed, "Purchase disabled");

    //     uint256 cost = getFoundersPackFullCost();

    //     require(
    //         msg.value >= ((cost * 960) / 1000) &&
    //             msg.value <= (cost * 1040) / 1000,
    //         "Payment amount missmatch"
    //     );

    //     payable(_acs().forgerAddress).transfer(
    //         (cost * _ss().botsFeePercentage) / 200
    //     );
    //     payable(_acs().borisAddress).transfer(
    //         (cost * _ss().botsFeePercentage) / 200
    //     );

    //     _ss().purchasedFoundersPackByAddress[recipient] = true;

    //     emit TeamFoundersPackPurchased(recipient);
    // }

    // Returns the USD cost of a foundersPack (x1000 for precision)
    function getFoundersPackUsdCost() public view returns (uint32) {
        return _ss().foundersPackUsdCost;
    }

    function getFoundersPackCost() public view returns (uint256) {
        return
            LibPrices.getPerDollarTokenPrice(
                getFoundersPackUsdCost(),
                _ps().nativeTokenPriceInUsd
            );
    }

    function getFoundersPackPurchaseGasOffset() public view returns (uint256) {
        return _ss().foundersPackGasOffset;
    }

    function getFoundersPackFullCost() public view returns (uint256) {
        return getFoundersPackCost() + getFoundersPackPurchaseGasOffset();
    }

    function getPurchasedFoundersPackByAddress(address purchaser)
        external
        view
        returns (bool purchased)
    {
        return _ss().purchasedFoundersPackByAddress[purchaser];
    }

    function getPurchasedFoundersPacksCount()
        external
        view
        returns (uint256 count)
    {
        return _ss().purchasedFoundersPacksCount;
    }

    function getFoundersPackPurchaseAllowed()
        external
        view
        returns (bool allowed)
    {
        return _ss().foundersPackPurchaseAllowed;
    }
}

