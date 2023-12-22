// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./IHarvester.sol";

error ContractsNotSet();

contract VerifyHarvesterStake is OwnableUpgradeable {
    IHarvester public harvester;

    function initialize() external initializer {
        __Ownable_init();
    }

    function balanceOf(address owner) external view returns (uint256 balance) {
        IHarvester.GlobalUserDeposit memory user = harvester
            .getUserGlobalDeposit(owner);

        return user.globalDepositAmount;
    }

    function setContracts(address harvester_) external onlyOwner {
        harvester = IHarvester(harvester_);
    }

    modifier contractsAreSet() {
        if (!areContractsSet()) {
            revert ContractsNotSet();
        }

        _;
    }

    function areContractsSet() public view returns (bool) {
        return address(harvester) != address(0);
    }
}

