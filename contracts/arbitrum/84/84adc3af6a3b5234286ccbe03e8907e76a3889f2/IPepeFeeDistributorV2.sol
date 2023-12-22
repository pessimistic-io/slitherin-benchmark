//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { Group, GroupUpdate, Contract, ContractUpdate } from "./Structs.sol";

interface IPepeFeeDistributorV2 {
    function updateGroupAllocations() external;

    function updateContractAllocations() external;

    function allocateUsdcToGroup(uint8 groupId) external;

    function transferUsdcToContract(uint8 groupId, address contractAddress) external returns (uint256);

    function allocateUsdcToAllGroups() external;

    function transferUsdcToAllContracts() external;

    function transferUsdcToContractsByGroupId(uint8 groupId) external;

    function addGroup(
        GroupUpdate[] calldata update,
        string calldata name,
        uint16 groupShare,
        address contractAddress,
        uint16 contractShare
    ) external;

    function addContract(
        ContractUpdate[] memory existingContractsUpdate,
        uint8 groupId,
        address contractAddress,
        uint16 share
    ) external;

    function removeGroup(uint8 groupId, GroupUpdate[] memory existingGroups) external;

    function removeContract(uint8 groupId, address contractAddress, ContractUpdate[] memory existingContracts) external;

    function updateGroupShares(GroupUpdate[] memory existingGroups) external;

    function updateContractShares(uint8 groupId, ContractUpdate[] memory existingContracts) external;

    function contractPendingUsdcRewards(address contractAddress, uint8 groupId) external view returns (uint256);

    function retrieveTokens(address[] calldata _tokens, address to) external;

    function retrieve(address _token, address to) external;

    function getLastBalance() external view returns (uint256);

    function getAccumulatedUsdcPerGroup() external view returns (uint256);

    function getLastUpdatedContractsTimestamp() external view returns (uint48);

    function getLastUpdatedGroupsTimestamp() external view returns (uint48);

    function getContractIndex(uint8 groupdId, address _contract) external view returns (uint256);

    function getGroup(uint8 groupId) external view returns (Group memory);

    function getContracts(uint8 groupId) external view returns (Contract[] memory);

    function getGroupShareDebt(uint8 groupId) external view returns (int256);
}

