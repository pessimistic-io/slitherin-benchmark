// SPDX-License-Identifier: GPL-3.0
//author: Johnleouf21
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./Address.sol";
import "./Context.sol";
import "./Math.sol";
import "./Ownable.sol";
import "./PaymentSplitter.sol";

/**
 * @title VestingWallet
 * @dev This contract handles the vesting of Eth and ERC20 tokens for a given beneficiary. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 * The vesting schedule is customizable through the {vestedAmount} function.
 *
 * Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 */
contract VestingWallet is Context, Ownable, PaymentSplitter {

    uint64 private immutable _start;
    uint64 private immutable _duration = 10;

    address[] private _team = [
        0x7EEAaD9C49c5422Ea6B65665146187A66F22c48E,//John
        0x5A36055355AEA83a1008732255600d179299cbe4,//Tsukune
        0x1F6c2d226164acb8eac00c62e15E52a4499d50A4,//Amaury
        0x9f162Dd6605CF7c0beC7ccb624F91448f12FBa98,//Bobby
        0x2825a62be826Af3be1f48300fae9a825DbF4e907,//Bezo
        0xBB8A3435c6A42fF6576920805B36f578aeCa4b58//Gnosis
    ];

    //Shares of all the members of the team
    uint[] private _teamShares = [
        13,
        15,
        1,
        13,
        8,
        50
    ];

    uint private teamLength;

    /**
     * @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
     */
    constructor() PaymentSplitter(_team, _teamShares) {
        _start = 1700409600;//not possible to withdraw token before this timestamp
        teamLength = _team.length;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start() public view virtual returns (uint256) {
        return _start;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration() public view virtual returns (uint256) {
        return _duration;
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {TokensReleased} event.
     */
    function releaseToken(address token) public virtual {
        uint256 releasable = vestedAmount(token, uint64(block.timestamp)) / 5;
        for(uint i = 0 ; i < _team.length - 1 ; i++) {
            SafeERC20.safeTransfer(IERC20(token), _team[i], releasable);
        }
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address token, uint64 timestamp) public view virtual returns (uint256) {
        return _vestingSchedule(IERC20(token).balanceOf(address(this)), timestamp);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view virtual returns (uint256) {
        if (timestamp < start()) {
            return 0;
        } else if (timestamp > start() + duration()) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start())) / duration();
        }
    }

    function releaseAll() external {
        for(uint i = 0 ; i < teamLength ; i++) {
            release(payable(payee(i)));
        }
    }
}
