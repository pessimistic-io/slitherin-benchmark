// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
    *******         **********     ***********     *****     ***********
    *      *        *              *                 *       *
    *        *      *              *                 *       *
    *         *     *              *                 *       *
    *         *     *              *                 *       *
    *         *     **********     *       *****     *       ***********
    *         *     *              *         *       *                 *
    *         *     *              *         *       *                 *
    *        *      *              *         *       *                 *
    *      *        *              *         *       *                 *
    *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/


pragma solidity ^0.8.13;

import "./SimpleERC20.sol";

/**
 * @notice LP token for priority pools
 *
 *         This lp token can be deposited into farming pool to get the premium income
 *         LP token has different generations and they are different in names
 *
 *         E.g.  PRI-LP-2-JOE-G1 and PRI-LP-2-JOE-G2
 *               They are both lp tokens for priority pool 2 (JOE pool)
 *               But with different generations, they have different weights in farming
 *
 *         Every time there is a report for the project and some payout are given out
 *         There will be a new generation of lp token
 *
 *         The weight will be set when the report happened
 *         and will depend on how much part are paid during that report
 */
contract PriorityPoolToken is SimpleERC20 {
    // Only minter and burner is Priority Pool
    address private priorityPool;

    modifier onlyPriorityPool() {
        require(msg.sender == priorityPool, "Only priority pool");
        _;
    }

    constructor(string memory _name) SimpleERC20(_name, "PRI-LP") {
        priorityPool = msg.sender;
    }

    function mint(address _user, uint256 _amount) external onlyPriorityPool {
        _mint(_user, _amount);
    }

    function burn(address _user, uint256 _amount) external onlyPriorityPool {
        _burn(_user, _amount);
    }
}

