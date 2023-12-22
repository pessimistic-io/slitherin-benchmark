/*
    Copyright 2020 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {IController} from "./IController.sol";
import {Ownable} from "./Ownable.sol";
import {AddressArrayUtils} from "./AddressArrayUtils.sol";

/**


 *
 * The IntegrationRegistry holds state relating to the Modules and the integrations they are connected with.
 * The state is combined into a single Registry to allow governance updates to be aggregated to one contract.
 */
contract IdentityService is Ownable {
    using AddressArrayUtils for address[];

    modifier onlyValidSet(address _jasperVault) {
        _isSetValid(_jasperVault);
        _;
    }

    /* ============ Events ============ */

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IController public controller;
    address[] public accounts;
    mapping(address => uint8) public account_type;
    mapping(address => address[]) public funds;

    /* ============ Constructor ============ */

    /**
     * Initializes the controller
     *
     * @param _controller          Instance of the controller
     */
    constructor(IController _controller) public {
        controller = _controller;
    }

    /* ============ External Functions ============ */
    function set_account_type(address account, uint8 value) public onlyOwner {
        require(account != address(0), "Account address must exist.");
        account_type[account] = value;
    }

    function newFund(address account, address fund)
        public
        onlyOwner
        onlyValidSet(fund)
    {
        require(account != address(0), "Account address must exist.");
        require(funds[account].contains(fund) == false, "fund exist.");
        funds[account].push(fund);
        if (accounts.contains(account) == false) {
            accounts.push(account);
        }
    }

    function removeFund(address account, address fund)
        public
        onlyOwner
        onlyValidSet(fund)
    {
        require(account != address(0), "Account address must exist.");
        require(funds[account].contains(fund), "fund doesn't exist.");
        funds[account] = funds[account].remove(fund);
    }

    function removeAccount(address account) public onlyOwner {
        require(account != address(0), "Account address must exist.");
        accounts = accounts.remove(account);
    }

    function batchSet_account_type(
        address[] memory _accounts,
        uint8[] memory _values
    ) external onlyOwner {
        require(
            _accounts.length == _values.length,
            "Accounts and Values lengths mismatch"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            set_account_type(_accounts[i], _values[i]);
        }
    }

    function getFundsByAccount(address account)
        public
        view
        returns (address[] memory)
    {
        return funds[account];
    }

    function getAccounts() external view returns (address[] memory) {
        return accounts;
    }

    function _isSetValid(address _jasperVault) internal view returns (bool) {
        return controller.isSet(_jasperVault);
    }
}

