// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import { IDynamicJobs } from "./IDynamicJobs.sol";
import { IKeeperRegistry } from "./IKeeperRegistry.sol";
import { IGasVault } from "./IGasVault.sol";
import { IOrchestrator } from "./IOrchestrator.sol";
import "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract DynamicJobs is Initializable, OwnableUpgradeable, IDynamicJobs {
    // Storage

    address public keeperRegistry;
    address public orchestrator;
    address public creator;
    uint256 public gasBalance;
    address public gasVault;

    /// @dev The mapping of jobState has 3 possiblities
    ///      1) 0 means not registered
    ///      2) 1 means registered and paused
    ///      3) 2 means unpaused and registered (active)
    mapping(bytes32 => uint256) public jobState;

    // Constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    function initialize(
        address _vaultManager,
        address _orchestrator,
        address, // Steer multisig not used here
        bytes calldata // no need for extra params
    ) external initializer {
        // Fetch gas vault and keeper registry from orchestrator
        keeperRegistry = IOrchestrator(_orchestrator).keeperRegistry();
        gasVault = IOrchestrator(_orchestrator).gasVault();

        __Ownable_init();
        creator = _vaultManager;
        orchestrator = _orchestrator;
    }

    /// @dev Use this function to register jobs.
    /// @param _userProvidedData are the calldatas that are provided by the user at the registration time.
    /// @param _targetAddresses are the addresses of the contracts on which the jobs needs to be executed.
    /// @param _name should be the name of the job.
    /// @param _ipfsForJobDetails is the ipfs hash containing job details like the interval for job execution.
    function registerJob(
        bytes[] calldata _userProvidedData,
        address[] calldata _targetAddresses,
        string calldata _name,
        string calldata _ipfsForJobDetails
    ) external {
        // Validate param length
        require(
            _userProvidedData.length == _targetAddresses.length,
            "Wrong Address Count"
        );

        // Only vault owner can register jobs for this vault
        require(creator == msg.sender || tx.origin == creator, "Unauthorized");

        // Record job hash
        bytes32 jobHash = keccak256(
            abi.encode(_userProvidedData, _targetAddresses)
        );

        // Job is currently unpaused
        jobState[jobHash] = 2;

        // Emit job details so that they can be used offchain
        emit JobRegistered(
            _userProvidedData,
            _targetAddresses,
            jobHash,
            _name,
            _ipfsForJobDetails
        );
    }

    /// @dev Use this function to register jobs and deposit gas in one call
    /// @dev Send the amount of gas that is needed to be deposited as msg.value.
    /// @param _userProvidedData are the calldatas that are provided by the user at the registration time.
    /// @param _targetAddresses are the addresses of the contracts on which the jobs needs to be executed.
    /// @param _name is the name of the job.
    /// @param _ipfsForJobDetails is the ipfs hash containing job details like the interval for job execution.
    function registerJobAndDepositGas(
        bytes[] calldata _userProvidedData,
        address[] calldata _targetAddresses,
        string calldata _name,
        string calldata _ipfsForJobDetails
    ) external payable {
        // Register job
        require(
            _userProvidedData.length == _targetAddresses.length,
            "Wrong Address Count"
        );
        require(creator == msg.sender, "Unauthorized");
        bytes32 jobHash = keccak256(
            abi.encode(_userProvidedData, _targetAddresses)
        );
        jobState[jobHash] = 2;
        emit JobRegistered(
            _userProvidedData,
            _targetAddresses,
            jobHash,
            _name,
            _ipfsForJobDetails
        );

        // Deposit gas
        IGasVault(gasVault).deposit{ value: msg.value }(address(this));
    }

    /// @dev Use this function to execute Jobs.
    /// @dev Only Orchestrator can call this function.
    /// @param _userProvidedData are the calldatas that are provided by the user at the registration time.
    /// @param _strategyProvidedData are the encoded parameters sent on the time of creation or execution of action in orchestrator according to the strategy.
    /// @param _targetAddresses are the addresses of the contracts on which the jobs needs to be executed.
    function executeJob(
        address[] calldata _targetAddresses,
        bytes[] calldata _userProvidedData,
        bytes[] calldata _strategyProvidedData
    ) external {
        bytes32 _jobHash = keccak256(
            abi.encode(_userProvidedData, _targetAddresses)
        );

        // Ensure passed params match user registered job
        require(jobState[_jobHash] == 2, "Paused or Not Registered");

        // Ensure that job is not paused
        require(msg.sender == orchestrator, "Unauthorized");

        uint256 jobCount = _targetAddresses.length;

        bytes memory completeData;
        bool success;
        for (uint256 i; i != jobCount; ++i) {
            completeData = abi.encodePacked(
                _userProvidedData[i],
                _strategyProvidedData[i]
            );
            (success, ) = _targetAddresses[i].call(completeData);

            // Revert if this method failed, thus reverting all methods in this job
            require(success);
        }
        emit JobExecuted(_jobHash, msg.sender);
    }

    /// @dev Use this function to pause or unpause a job
    /// @param _jobHash is the keccak of encoded parameters and target addresses
    /// @param _toggle pass 1 to pause the job and pass 2 to unpause the job
    function setJobState(bytes32 _jobHash, uint256 _toggle) external {
        require(creator == msg.sender, "Access Denied");
        require(_toggle == 1 || _toggle == 2, "Invalid");
        jobState[_jobHash] = _toggle;
        emit JobToggledByCreator(_jobHash, _toggle);
    }

    /// @dev Use this function to withdraw gas associated to this vault
    /// @dev Only creator of this vault can call this function
    /// @param _amount is the amount of ether in wei that creator of this contract wants to pull out
    /// @param to is the address at which the creator wants to pull the deposited ether out
    function withdrawGas(uint256 _amount, address payable to) external {
        require(msg.sender == creator, "Not Creator");
        IGasVault(gasVault).withdraw(_amount, to);
    }
}

