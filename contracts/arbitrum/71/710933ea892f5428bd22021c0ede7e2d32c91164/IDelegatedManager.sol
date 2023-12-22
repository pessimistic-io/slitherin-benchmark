// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IDelegatedManager {
     function jasperVault() external view returns (address);
     function owner() external view returns(address);
}

