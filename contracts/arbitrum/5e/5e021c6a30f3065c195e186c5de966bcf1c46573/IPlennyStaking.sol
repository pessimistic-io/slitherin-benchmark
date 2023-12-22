// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyStaking {

    function plennyBalance(address addr) external view returns (uint256);

    function decreasePlennyBalance(address dapp, uint256 amount, address to) external;

    function increasePlennyBalance(address dapp, uint256 amount, address from) external;

}
