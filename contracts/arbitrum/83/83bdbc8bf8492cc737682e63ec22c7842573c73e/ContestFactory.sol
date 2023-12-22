// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Ownable } from "./Ownable.sol";
import { ConfigStore } from "./ConfigStore.sol";
import { Contest } from "./Contest.sol";
import { ContestStaker } from "./ContestStaker.sol";
import { ISpire } from "./ISpire.sol";

// Deploys new Contests and transfers ownership of them to the deployer. Also registers the contract with a
// contest staker contract so that the contests can freeze and unfreeze user stakes. This contract deploys the
// contest staker upon construction so this contract owns the staker contract.

error InvalidSpireAddress();

interface IContestFactory {
    function deployNewContest(
        uint256 minimumContestTime,
        uint256 approvedEntryThreshold,
        ConfigStore _configStore
    )
        external
        returns (address);
    function addStakeableTokenId(address stakedContract, uint256 tokenId) external;
    function removeStakedContract(address stakedContract) external;
    function removeStakeableTokenId(address stakedContract, uint256 tokenId) external;
}

contract ContestFactory is IContestFactory, ContestStaker {
    address private _spire;

    modifier onlyContract() {
        ISpire(_spire).checkContractRole(msg.sender);
        _;
    }

    event SetSpireAddress(address indexed spireAddress);

    constructor(
        address spire,
        address _stakedContract,
        uint256[] memory _stakeableTokenIds
    )
        ContestStaker(_stakedContract, _stakeableTokenIds) // solhint-disable-next-line no-empty-blocks
    {
        if (spire == address(0)) revert InvalidSpireAddress();
        _spire = spire;
        emit SetSpireAddress(_spire);
    }

    function addStakeableTokenId(address stakedContract, uint256 tokenId) external override onlyContract {
        _addStakeableTokenId(stakedContract, tokenId);
    }

    function removeStakedContract(address stakedContract) external override onlyContract {
        _removeStakedContract(stakedContract);
    }

    function removeStakeableTokenId(address stakedContract, uint256 tokenId) external override onlyContract {
        _removeStakeableTokenId(stakedContract, tokenId);
    }

    // Anyone can call this function to deploy a new Contest that sets the caller as the owner of the new Contest.
    // This should be called by the Spire contract but there is no harm if anyone calls it.
    function deployNewContest(
        uint256 minimumContestTime,
        uint256 approvedEntryThreshold,
        ConfigStore _configStore
    )
        external
        override
        returns (address)
    {
        address contest = address(
            new Contest(
            minimumContestTime,
            approvedEntryThreshold,
            _configStore
            )
        );
        _registerContest(address(contest));
        Ownable(contest).transferOwnership(msg.sender);
        return address(contest);
    }
}

