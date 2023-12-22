// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./IHarvester.sol";

error ContractsNotSet();

contract VerifyHarvesterStake is OwnableUpgradeable {
    IHarvester public harvester;
    string public name;

    function initialize(address harvester_, string calldata name_)
        external
        initializer
    {
        __Ownable_init();

        harvester = IHarvester(harvester_);
        name = name_;
    }

    function balanceOf(address owner) external view returns (uint256 cap) {
        return harvester.getUserDepositCap(owner);
    }
}

