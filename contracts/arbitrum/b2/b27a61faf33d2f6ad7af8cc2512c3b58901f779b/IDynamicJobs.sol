// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.12;

interface IDynamicJobs {
    event JobExecuted(bytes32 jobHash, address executor);
    event JobRegistered(
        bytes[] jobInfo,
        address[] targetAddresses,
        bytes32 jobHash,
        string name,
        string ipfsForJobDetails
    );
    event JobToggledByCreator(bytes32 jobHash, uint256 toggle);

    function registerJob(
        bytes[] calldata _userProvidedData,
        address[] calldata _targetAddresses,
        string calldata _name,
        string calldata _ipfsForJobDetails
    ) external;

    function registerJobAndDepositGas(
        bytes[] calldata _userProvidedData,
        address[] calldata _targetAddresses,
        string calldata _name,
        string calldata _ipfsForJobDetails
    ) external payable;

    function executeJob(
        address[] calldata _targetAddresses,
        bytes[] calldata _userProvidedData,
        bytes[] calldata _strategyProvidedData
    ) external;

    function setJobState(bytes32 _jobHash, uint256 _toggle) external;

    function withdrawGas(uint256 _amount, address payable to) external;
}

