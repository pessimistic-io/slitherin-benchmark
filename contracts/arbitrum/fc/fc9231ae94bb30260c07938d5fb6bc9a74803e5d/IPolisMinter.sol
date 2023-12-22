//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {IPolis} from "./IPolis.sol";

interface IPolisMinter {
    error OnlyPolisMinterRole();

    event MintedWithPayment(address indexed to);

    function setPayment(IERC20 token, uint256 value, address wallet) external;

    function mintWithPayment() external;

    function polis() external view returns (IPolis);

    function paymentToken() external view returns (IERC20);

    function paymentValue() external view returns (uint256);
}

