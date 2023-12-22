//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { Group, GroupUpdate, Contract, ContractUpdate } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeFeeDistributorV2 } from "./IPepeFeeDistributorV2.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeFeeDistributorV2 is IPepeFeeDistributorV2, Ownable2Step {
    using SafeERC20 for IERC20;
    uint16 public constant BPS_DIVISOR = 10_000; ///@dev basis points divisor. Also acts as the total staked for all groups and all contracts per group.
    IERC20 public immutable usdcToken;

    uint256 public accumulatedUsdcPerGroup; ///@dev usdc accumulated per total group stake (10_000).
    uint256 public lastBalance; ///@dev last balance of the contract.
    uint48 public lastAllocatedGroupsTimestamp; ///@dev last time the rewards per groups were updated.
    uint48 public lastAllocatedContractsTimestamp; ///@dev last time the rewards per contracts were updated.
    uint8 public groupCount; ///@dev total number of groups, also acts as Id.
    mapping(uint8 groupId => Group) public groups; ///@dev groups.
    mapping(uint8 groupId => Contract[]) public contracts; ///@dev contracts per group.
    mapping(uint8 groupId => mapping(address contractAddress => uint256 index)) public contractIndex; ///@dev index of the contract in the contracts array.

    event ContractAdded(uint8 indexed groupId, string name, address indexed contractAddress, uint16 feeShare);
    event ContractRemoved(uint8 indexed groupId, string name, address indexed contractAddress, uint16 feeShare);
    event GroupAdded(uint8 indexed groupId, string indexed groupName, uint256 indexed newShare);
    event GroupRemoved(uint8 indexed groupId, string indexed groupName, uint16 indexed previousShare);
    event GroupSharesUpdated(GroupUpdate[] indexed groupUpdates);
    event ContractSharesUpdated(uint8 indexed groupId, ContractUpdate[] indexed contractUpdates);
    event UpdatedGroupsAllocation(uint256 indexed accumulatedUsdcPerGroup);
    event UpdatedContractsAllocation(
        uint8 indexed groupId,
        string groupName,
        uint256 usdcDistributable,
        uint256 accumulatedUsdcPerContract,
        uint48 timestamp
    );
    event UsdcAllocatedToGroup(uint8 indexed groupId, uint256 indexed amountAllocated);
    event UsdcTransferredToContract(
        uint8 indexed groupId,
        address indexed contractAddress,
        uint256 indexed amountAllocated
    );

    constructor(address _usdcToken, address staking, address lockUp, address plsAccumulator) {
        usdcToken = IERC20(_usdcToken);

        //initialize groups
        Contract memory stakingContracts = Contract({
            totalUsdcReceived: 0,
            contractShareDebt: 0,
            contractAddress: staking,
            feeShare: BPS_DIVISOR,
            groupId: 1
        });

        Contract memory lockUpContracts = Contract({
            totalUsdcReceived: 0,
            contractShareDebt: 0,
            contractAddress: lockUp,
            feeShare: BPS_DIVISOR,
            groupId: 2
        });

        Contract memory plsAccumulatorContracts = Contract({
            totalUsdcReceived: 0,
            contractShareDebt: 0,
            contractAddress: plsAccumulator,
            feeShare: BPS_DIVISOR,
            groupId: 3
        });

        contracts[1].push(stakingContracts);
        contracts[2].push(lockUpContracts);
        contracts[3].push(plsAccumulatorContracts);
        contractIndex[1][staking] = 0;
        contractIndex[2][lockUp] = 0;
        contractIndex[3][plsAccumulator] = 0;

        groups[1] = Group({
            totalUsdcDistributed: 0,
            accumulatedUsdcPerContract: 0,
            pendingGroupUsdc: 0,
            lastGroupBalance: 0,
            shareDebt: 0,
            name: "STAKING",
            feeShare: 1_000,
            groupId: 1
        });

        groups[2] = Group({
            totalUsdcDistributed: 0,
            accumulatedUsdcPerContract: 0,
            pendingGroupUsdc: 0,
            lastGroupBalance: 0,
            shareDebt: 0,
            name: "LOCKUP",
            feeShare: 3_000,
            groupId: 2
        });

        groups[3] = Group({
            totalUsdcDistributed: 0,
            accumulatedUsdcPerContract: 0,
            pendingGroupUsdc: 0,
            lastGroupBalance: 0,
            shareDebt: 0,
            name: "PLSACCUMULATOR",
            feeShare: 6_000,
            groupId: 3
        });

        groupCount = 3;
    }

    ///@dev updates accumulated usdc group. I.e usdc per 10_000 (total stake of groups).
    function updateGroupAllocations() public override {
        if (uint48(block.timestamp) > lastAllocatedGroupsTimestamp) {
            uint256 contractBalance = usdcToken.balanceOf(address(this));
            uint256 diff = contractBalance - lastBalance;
            if (diff != 0) {
                accumulatedUsdcPerGroup += diff / BPS_DIVISOR;
                emit UpdatedGroupsAllocation(accumulatedUsdcPerGroup);
                lastBalance = contractBalance;
            }
            lastAllocatedGroupsTimestamp = uint48(block.timestamp);
        }
    }

    ///@dev updates accumulated usdc per contract per group. I.e usdc per 10_000 (total stake of contracts per group).
    function updateContractAllocations() public override {
        allocateUsdcToAllGroups();

        if (uint48(block.timestamp) > lastAllocatedContractsTimestamp) {
            uint8 i = 1;
            for (; i <= groupCount; ) {
                Group memory group = groups[i];
                Contract[] memory contractDetails = contracts[i];

                if (group.pendingGroupUsdc != 0 && contractDetails.length != 0) {
                    uint256 diff = group.pendingGroupUsdc - group.lastGroupBalance;

                    if (diff != 0) {
                        groups[i].accumulatedUsdcPerContract += diff / BPS_DIVISOR;

                        emit UpdatedContractsAllocation(
                            i,
                            group.name,
                            group.pendingGroupUsdc,
                            diff / BPS_DIVISOR,
                            uint48(block.timestamp)
                        );
                    }
                }

                unchecked {
                    ++i;
                }
            }

            lastAllocatedContractsTimestamp = uint48(block.timestamp);
        }
    }

    ///@dev updates pending usdc of a group (amount sharable by contracts in that group).
    ///@param groupId id of the group to update.
    function allocateUsdcToGroup(uint8 groupId) public override {
        updateGroupAllocations();
        Group memory groupDetails = groups[groupId];
        int256 accumulatedGroupUsdc = int256(groupDetails.feeShare * accumulatedUsdcPerGroup);
        uint256 pendingGroupUsdc = uint256(accumulatedGroupUsdc - groupDetails.shareDebt);

        if (pendingGroupUsdc != 0) {
            groups[groupId].shareDebt = accumulatedGroupUsdc;

            groups[groupId].pendingGroupUsdc += pendingGroupUsdc;

            emit UsdcAllocatedToGroup(groupId, pendingGroupUsdc);
        }
    }

    ///@dev transfers usdc to a contract in a group.
    ///@param groupId id of the group to update.
    ///@param contractAddress address of the contract to transfer usdc to.
    function transferUsdcToContract(uint8 groupId, address contractAddress) public override returns (uint256) {
        updateContractAllocations();

        if (contracts[groupId].length == 0) return 0;

        Group memory groupDetails = groups[groupId];
        uint256 contractIndex_ = contractIndex[groupId][contractAddress];
        Contract memory contractDetails = contracts[groupId][contractIndex_];

        if (contractDetails.contractAddress != contractAddress) return 0;

        int256 accumulatedContractUsdc = int256(contractDetails.feeShare * groupDetails.accumulatedUsdcPerContract);
        uint256 pendingContractUsdc = uint256(accumulatedContractUsdc - contractDetails.contractShareDebt);

        if (pendingContractUsdc != 0) {
            contracts[groupId][contractIndex_].contractShareDebt = accumulatedContractUsdc;
            contracts[groupId][contractIndex_].totalUsdcReceived += pendingContractUsdc;

            groups[groupId].totalUsdcDistributed += pendingContractUsdc;
            groups[groupId].lastGroupBalance = groupDetails.pendingGroupUsdc - pendingContractUsdc;
            groups[groupId].pendingGroupUsdc -= pendingContractUsdc;
            lastBalance -= pendingContractUsdc;

            require(usdcToken.transfer(contractAddress, pendingContractUsdc), "transfer failed");

            emit UsdcTransferredToContract(groupId, contractAddress, pendingContractUsdc);
        }
        return pendingContractUsdc;
    }

    ///@dev updates pending usdc for all groupa.
    function allocateUsdcToAllGroups() public override {
        uint8 i = 1;
        for (; i <= groupCount; ) {
            allocateUsdcToGroup(i);
            unchecked {
                ++i;
            }
        }
    }

    ///@dev transfers usdc to all contracts in all groups.
    function transferUsdcToAllContracts() public override {
        uint8 i = 1; ///@notice updated

        for (; i <= groupCount; ) {
            transferUsdcToContractsByGroupId(i);

            unchecked {
                ++i;
            }
        }
    }

    ///@dev transfers usdc to all contracts in a group.
    ///@param groupId id in question.
    function transferUsdcToContractsByGroupId(uint8 groupId) public override {
        require(contracts[groupId].length != 0, "TRANSFER: no contracts");

        allocateUsdcToGroup(groupId);
        uint256 i;
        Contract[] memory contractDetails = contracts[groupId];
        uint256 contractCount = contractDetails.length;

        for (; i < contractCount; ) {
            transferUsdcToContract(groupId, contractDetails[i].contractAddress);

            unchecked {
                ++i;
            }
        }
    }

    ///@param update array of GroupUpdate struct to update the share of the existing groups.
    ///@param name name of the new group.
    ///@param groupShare share of the new group.
    ///@param contractAddress address of the contract to be added to the new group.
    ///@param contractShare share of the contract to be added to the new group.
    function addGroup(
        GroupUpdate[] calldata update,
        string calldata name,
        uint16 groupShare,
        address contractAddress,
        uint16 contractShare
    ) external override onlyOwner {
        require(groupShare != 0 && groupShare <= BPS_DIVISOR, "invalid groupShare");
        require(bytes(name).length != 0, "invalid name");

        uint8 updateLength = uint8(update.length);
        require(updateLength == groupCount, "invalid update length");

        updateGroupAllocations();

        uint16 newTotalShare;
        uint8 i;
        for (; i < updateLength; ) {
            GroupUpdate memory currentUpdate = update[i];
            newTotalShare += uint16(update[i].newShare);

            require(currentUpdate.groupId != 0 && currentUpdate.groupId <= groupCount, "invalid groupId");
            require(currentUpdate.newShare != 0, "invalid groupShare");

            uint16 existingShare = groups[currentUpdate.groupId].feeShare;
            if (existingShare != currentUpdate.newShare) {
                groups[currentUpdate.groupId].feeShare = currentUpdate.newShare;
            }
            unchecked {
                ++i;
            }
        }
        require(newTotalShare + groupShare == BPS_DIVISOR, "invalid groupShare");

        uint8 newGroupId = ++groupCount;
        groups[newGroupId] = Group({
            totalUsdcDistributed: 0,
            accumulatedUsdcPerContract: 0,
            pendingGroupUsdc: 0,
            lastGroupBalance: 0,
            shareDebt: int256(BPS_DIVISOR * accumulatedUsdcPerGroup),
            name: name,
            feeShare: groupShare,
            groupId: newGroupId
        });

        emit GroupAdded(newGroupId, name, groupShare);

        ContractUpdate[] memory existingContractsUpdate = new ContractUpdate[](0);
        addContract(existingContractsUpdate, newGroupId, contractAddress, contractShare);
    }

    ///@param existingContractsUpdate array of ContractUpdate struct to update the share of the existing contracts.
    ///@param groupId id of the group to which the contract is to be added.
    ///@param contractAddress address of the contract to be added to the group.
    ///@param share share of the contract to be added to the group.
    function addContract(
        ContractUpdate[] memory existingContractsUpdate,
        uint8 groupId,
        address contractAddress,
        uint16 share
    ) public override onlyOwner {
        require(groupId != 0 || groupId <= groupCount, "invalid groupId");
        require(share != 0 && share <= BPS_DIVISOR, "invalid share");
        require(contractAddress != address(0), "invalid address");

        Contract[] memory currentContracts = contracts[groupId];

        require(existingContractsUpdate.length == currentContracts.length, "invalid contracts length");

        if (currentContracts.length == 0) {
            require(share == BPS_DIVISOR, "invalid share");
        }

        updateContractAllocations();

        uint256 lengthUpdate = existingContractsUpdate.length;
        uint16 newTotalShare;

        uint256 i;
        for (; i < lengthUpdate; ) {
            ContractUpdate memory currentUpdate = existingContractsUpdate[i];

            require(currentUpdate.contractAddress != address(0), "!invalid");
            require(currentUpdate.newShare != 0, "invalid share");
            require(currentContracts[i].contractAddress != contractAddress, "contract already added");

            newTotalShare += existingContractsUpdate[i].newShare;

            uint256 contractIndex_ = contractIndex[groupId][currentUpdate.contractAddress];
            if (contractIndex_ == 0) {
                require(
                    currentContracts[contractIndex_].contractAddress == currentUpdate.contractAddress,
                    "contract not found"
                );
            }

            uint16 existingShare = currentContracts[contractIndex_].feeShare;

            if (existingShare != currentUpdate.newShare) {
                contracts[groupId][contractIndex_].feeShare = currentUpdate.newShare;
            }

            unchecked {
                ++i;
            }
        }
        require(newTotalShare + share == BPS_DIVISOR, "invalid share");

        contractIndex[groupId][contractAddress] = currentContracts.length;

        contracts[groupId].push(
            Contract({
                totalUsdcReceived: 0,
                contractShareDebt: int256(BPS_DIVISOR * groups[groupId].accumulatedUsdcPerContract),
                contractAddress: contractAddress,
                feeShare: share,
                groupId: groupId
            })
        );
        emit ContractAdded(groupId, groups[groupId].name, contractAddress, share);
    }

    ///@param groupId id of the group to which the contract is to be removed.
    ///@param existingGroups array of GroupUpdate struct to update the share of the existing groups minus the group to be removed.
    function removeGroup(uint8 groupId, GroupUpdate[] memory existingGroups) public override onlyOwner {
        require(groupId != 0 && groupId <= groupCount, "invalid groupId");
        require(existingGroups.length == groupCount - 1, "invalid update length");

        Group memory group = groups[groupId];

        transferUsdcToContractsByGroupId(groupId);

        uint16 newTotalShare;
        uint256 lengthGroup = existingGroups.length;

        uint256 i;

        for (; i < lengthGroup; ) {
            require(existingGroups[i].groupId != 0 && existingGroups[i].groupId <= groupCount, "invalid groupId");
            require(existingGroups[i].newShare != 0, "invalid groupShare");

            newTotalShare += existingGroups[i].newShare;

            if (existingGroups[i].groupId != groupId) {
                groups[existingGroups[i].groupId].feeShare = existingGroups[i].newShare;
                groups[existingGroups[i].groupId].shareDebt = int256(
                    existingGroups[i].newShare * accumulatedUsdcPerGroup
                );
            }

            unchecked {
                ++i;
            }
        }
        require(newTotalShare == BPS_DIVISOR, "invalid groupShare");

        delete groups[groupId];
        delete contracts[groupId];
        --groupCount;

        emit GroupRemoved(groupId, group.name, group.feeShare);
    }

    ///@param groupId id of the group to which the contract is to be removed.
    ///@param contractAddress address of the contract to be removed from the group.
    ///@param existingContracts array of ContractUpdate struct to update the share of the existing contracts minus the contract to be removed.
    function removeContract(
        uint8 groupId,
        address contractAddress,
        ContractUpdate[] memory existingContracts
    ) public override onlyOwner {
        Contract[] memory groupContracts = contracts[groupId];

        require(groupContracts.length != 0, "no contracts");
        require(contractAddress != address(0), "!invalid");
        require(existingContracts.length == groupContracts.length - 1, "invalid update length");

        transferUsdcToContractsByGroupId(groupId);

        uint16 newTotalShare;
        uint256 contractsCount = groupContracts.length;
        uint256 i;
        uint256 updateLength = existingContracts.length;
        for (; i < updateLength; ) {
            require(existingContracts[i].contractAddress != address(0), "!invalid");
            require(existingContracts[i].newShare != 0, "invalid share");
            newTotalShare += existingContracts[i].newShare;

            uint256 contractIndex_ = contractIndex[groupId][existingContracts[i].contractAddress];

            if (contractIndex_ == 0) {
                require(
                    groupContracts[contractIndex_].contractAddress == existingContracts[i].contractAddress,
                    "contract not found"
                );
            }

            contracts[groupId][contractIndex_].feeShare = existingContracts[i].newShare;
            contracts[groupId][contractIndex_].contractShareDebt = int256(
                existingContracts[i].newShare * groups[groupId].accumulatedUsdcPerContract
            );

            unchecked {
                ++i;
            }
        }

        require(newTotalShare == BPS_DIVISOR, "invalid share");

        uint256 removeContractIndex = contractIndex[groupId][contractAddress];
        Contract memory contract_ = groupContracts[removeContractIndex];

        contracts[groupId][removeContractIndex] = contracts[groupId][contractsCount - 1];
        contracts[groupId].pop();

        emit ContractRemoved(groupId, groups[groupId].name, contractAddress, contract_.feeShare);
    }

    ///@param updateGroups array of GroupUpdate struct to update the share of the existing groups.
    function updateGroupShares(GroupUpdate[] memory updateGroups) public override onlyOwner {
        ///allocate the usdc to the groups based on the share before.
        require(updateGroups.length == groupCount, "invalid update length");

        allocateUsdcToAllGroups();

        uint16 newTotalShare;
        uint256 lengthGroup = updateGroups.length;

        uint256 i;

        for (; i < lengthGroup; ) {
            require(updateGroups[i].groupId != 0 && updateGroups[i].groupId <= groupCount, "invalid groupId");
            require(updateGroups[i].newShare != 0, "invalid groupShare");

            newTotalShare += updateGroups[i].newShare;

            uint16 existingShare = groups[updateGroups[i].groupId].feeShare;

            if (existingShare != updateGroups[i].newShare) {
                groups[updateGroups[i].groupId].feeShare = updateGroups[i].newShare;
                groups[updateGroups[i].groupId].shareDebt = int256(updateGroups[i].newShare * accumulatedUsdcPerGroup);
            }

            unchecked {
                ++i;
            }
        }
        require(newTotalShare == BPS_DIVISOR, "invalid groupShare");

        emit GroupSharesUpdated(updateGroups);
    }

    ///@param groupId id of the group to which the contract is to be updated.
    ///@param existingContracts array of ContractUpdate struct to update the share of the existing contracts.
    function updateContractShares(uint8 groupId, ContractUpdate[] memory existingContracts) public override onlyOwner {
        Contract[] memory groupContracts = contracts[groupId];

        require(groupContracts.length != 0, "no contracts");
        require(existingContracts.length == groupContracts.length, "invalid update length");

        uint16 newTotalShare;
        uint256 contractsLength = groupContracts.length;
        uint256 j;

        for (; j < contractsLength; ) {
            transferUsdcToContract(groupId, groupContracts[j].contractAddress);

            unchecked {
                ++j;
            }
        }

        uint256 i;
        for (; i < contractsLength; ) {
            require(existingContracts[i].contractAddress != address(0), "!invalid");
            require(existingContracts[i].newShare != 0, "invalid share");

            newTotalShare += existingContracts[i].newShare;

            uint256 contractIndex_ = contractIndex[groupId][existingContracts[i].contractAddress];

            if (contractIndex_ == 0) {
                require(
                    groupContracts[contractIndex_].contractAddress == existingContracts[i].contractAddress,
                    "contract not found"
                );
            }

            uint16 existingShare = contracts[groupId][contractIndex_].feeShare;

            if (existingShare != existingContracts[i].newShare) {
                contracts[groupId][contractIndex_].feeShare = existingContracts[i].newShare;
                contracts[groupId][contractIndex_].contractShareDebt = int256(
                    existingContracts[i].newShare * groups[groupId].accumulatedUsdcPerContract
                );
            }

            unchecked {
                ++i;
            }
        }
        require(newTotalShare == BPS_DIVISOR, "invalid share");

        emit ContractSharesUpdated(groupId, existingContracts);
    }

    ///@dev FD-V2 will receive other tokens as fee, this function is to retrieve those tokens.
    function retrieve(address _token, address to) external override onlyOwner {
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(to).call{ value: address(this).balance }("");
            require(success, "ETH retrival failed");
        }

        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    function getContractIndex(uint8 groupdId, address _contract) external view override returns (uint256) {
        return contractIndex[groupdId][_contract];
    }

    function getGroup(uint8 groupId) external view override returns (Group memory) {
        return groups[groupId];
    }

    function getContracts(uint8 groupId) external view override returns (Contract[] memory) {
        return contracts[groupId];
    }

    function getGroupShareDebt(uint8 groupId) external view override returns (int256) {
        return groups[groupId].shareDebt;
    }

    function getLastBalance() external view override returns (uint256) {
        return lastBalance;
    }

    function getAccumulatedUsdcPerGroup() external view override returns (uint256) {
        return accumulatedUsdcPerGroup;
    }

    function getLastUpdatedGroupsTimestamp() external view override returns (uint48) {
        return lastAllocatedGroupsTimestamp;
    }

    function getLastUpdatedContractsTimestamp() external view override returns (uint48) {
        return lastAllocatedContractsTimestamp;
    }
}

