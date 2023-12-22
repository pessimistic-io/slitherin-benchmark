// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {ERC20Burnable} from "./ERC20Burnable.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {ERC20} from "./ERC20.sol";

/**
 * @title PreLevelToken
 * @author LevelFinance
 * @notice PreLevelToken is intermediate token issues by protocol in place of usage incentive. User collect their preLVL to convert to LVL token in following ways:
 * - instant convert: with 30% fee in form of USDT. These amount of USDT will be sent to DAO and liquidity pool
 * - vesting: gradually convert preLVL to LVL in 1 year. After start vesting, user can claim their converted LVL or stop vesting at any time. The only requirement is they MUST
 * lock an amount of LVL to staking contract.
 */
contract PreLevelToken is Ownable2Step, ERC20Burnable {

    address public minter;

    constructor() Ownable2Step() ERC20("Pre Level Token", "preLVL") {}

    function mint(address _account, uint256 _amount) external {
        if (minter != msg.sender) revert Unauthorized();
        _mint(_account, _amount);
    }

    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        if (minter != _minter) {
            minter = _minter;
            emit MinterSet(_minter);
        }
    }

    // ======== ERRORS ========
    error Unauthorized();
    error ZeroAddress();

    // ======== EVENTS ========
    event MinterSet(address _minter);
}

