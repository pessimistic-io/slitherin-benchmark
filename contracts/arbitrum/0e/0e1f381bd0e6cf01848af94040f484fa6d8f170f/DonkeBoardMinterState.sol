//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./IDonkeBoardMinter.sol";
import "./IDonkeBoard.sol";
import "./AdminableUpgradeable.sol";

abstract contract DonkeBoardMinterState is
    Initializable,
    IDonkeBoardMinter,
    AdminableUpgradeable
{
    event DonkeBoardMint(address indexed _owner, uint256 _batchSize);
    error InsufficientBalance(uint _balance, uint _price);

    IDonkeBoard public donkeBoard;
    IERC20Upgradeable public magicToken;
    // team wallet address for magic withdraw
    address public treasuryAddress;

    mapping(address => uint256) public addressToHasClaimedAmount;

    bytes32 public merkleRoot;

    uint8 public maxBatchSize;

    function __DonkeBoardMinterState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        maxBatchSize = 20;
    }
}

