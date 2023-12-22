//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./ITreasury.sol";
import "./AdminableUpgradeable.sol";
import "./IMasterOfCoin.sol";
import "./IAtlasMine.sol";
import "./IMagic.sol";

abstract contract TreasuryState is Initializable, ITreasury, ERC1155HolderUpgradeable, AdminableUpgradeable {

    event Withdraw(address indexed _token, address indexed _to, uint256 _amt);

    IMasterOfCoin public masterOfCoin;
    IAtlasMine public atlasMine;
    IMagic public magic;

    // Utilization needed to power bridgeworld. 100% = 1 * 10**18
    uint256 public utilNeededToPowerBW;

    // number from 0-100
    uint256 public percentMagicToMine;

    function __TreasuryState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        // 30%
        utilNeededToPowerBW = 3 * 10**17;
        percentMagicToMine = 33;
    }
}
