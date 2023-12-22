// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.12;

import "./IGasVault.sol";
import "./IOrchestrator.sol";
import "./IStrategyRegistry.sol";
import "./IVaultRegistry.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

/**
 * @dev vault for storing gas for each strategy. Nodes must still pay gas cost to call, but execution costs
 *  will come out of the gas account.
 */
contract GasVault is
    IGasVault,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Storage

    IOrchestrator public orchestrator;
    IStrategyRegistry public strategyRegistry;
    IVaultRegistry public vaultRegistry;

    /// @notice Mapping from vault address to gasInfo
    mapping(address => uint256) public ethBalances;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    /// @dev Permanently sets related addresses
    /// @param _orchestrator Address of the orchestrator contract
    /// @param _stratRegistry Address of the strategy registry contract
    /// @param _vaultRegistry Address of the vault registry contract
    function initialize(
        address _orchestrator,
        address _stratRegistry,
        address _vaultRegistry
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        require(_orchestrator != address(0), "address(0)");
        require(_stratRegistry != address(0), "address(0)");
        require(_vaultRegistry != address(0), "address(0)");
        orchestrator = IOrchestrator(_orchestrator);
        strategyRegistry = IStrategyRegistry(_stratRegistry);
        vaultRegistry = IVaultRegistry(_vaultRegistry);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier onlyOrchestrator() {
        require(
            msg.sender == address(orchestrator),
            "Only orchestrator can call this"
        );
        _;
    }

    /// @dev Deposit more eth to be used in jobs.
    ///      Can only be withdrawn by governance and the given vault,
    ///      so in most cases these funds are unretrievable.
    /// @param targetAddress address of the recipient of these gas funds
    function deposit(address targetAddress) external payable override {
        ethBalances[targetAddress] += msg.value;
        emit Deposited(msg.sender, targetAddress, msg.value);
    }

    /// @dev Normal withdraw function, normally used by keepers
    /// @param amount The amount to withdraw
    /// @param to Address to send the ether to
    function withdraw(
        uint256 amount,
        address payable to
    ) external override nonReentrant {
        ethBalances[msg.sender] -= amount;
        emit Withdrawn(msg.sender, to, amount);
        AddressUpgradeable.sendValue(to, amount);
    }

    /// @param targetAddress The address of the vault in question
    /// @param highGasEstimate An estimate of the highest reasonable gas price which
    ///                        a transaction will cost, in terms of wei.
    ///                        In other words, given a bad gas price,
    ///                        how many more times can a strategy be run.
    /// @return transactions Remaining, assuming upper limit estimate of gas price
    ///                      is used for the transaction
    function transactionsRemaining(
        address targetAddress,
        uint256 highGasEstimate
    ) external view override returns (uint256) {
        IVaultRegistry.VaultData memory vaultInfo = vaultRegistry
            .getVaultDetails(targetAddress);
        IStrategyRegistry.RegisteredStrategy memory info = strategyRegistry
            .getRegisteredStrategy(vaultInfo.tokenId);
        if (highGasEstimate > info.maxGasCost) {
            return 0;
        } else {
            uint256 totalWeiPerMethod = info.maxGasPerAction * highGasEstimate;
            return ethBalances[targetAddress] / totalWeiPerMethod;
        }
    }

    /// @dev Orchestrator calls this function in order to reimburse tx.origin for method gas.
    ///      First it checks that all parameters are correct (gas price isn't too high),
    ///      And then it returns as much gas as is available to use in the transaction.
    ///      Note that this function will revert if the gas price is too high for the strategy.
    ///      This should be checked by the keeper beforehand.
    /// @param _targetAddress Address actions will be performed on, and address paying gas for those actions.
    /// @return gasAvailable (representing amount of gas available per Method).
    function gasAvailableForTransaction(
        address _targetAddress
    ) external view returns (uint256) {
        // Get gas info
        IVaultRegistry.VaultData memory vaultInfo = vaultRegistry
            .getVaultDetails(_targetAddress);
        IStrategyRegistry.RegisteredStrategy memory info = strategyRegistry
            .getRegisteredStrategy(vaultInfo.tokenId);

        // Ensure requested gas use is acceptable.
        // wei / gas must be less than maxGasCost,
        // and GasVault must have enough ether allotted to pay for action.
        require(tx.gasprice <= info.maxGasCost, "Gas too expensive.");

        // Represents gas available per action. Gas cost of all methods must be <= this.
        uint256 gasAvailable = info.maxGasPerAction;
        require(
            ethBalances[_targetAddress] >= tx.gasprice * gasAvailable,
            "Insufficient ether deposited"
        );

        // Return gas available
        return gasAvailable;
    }

    /// @dev Note that keepers still have to pull their gas from the GasVault in order
    ///      to truly be reimbursed--until then the ETH is just sitting in the GasVault.
    /// @param targetAddress The address which the action was performed upon.
    ///                      The reimbursement will come from its gas fund.
    /// @param originalGas How much gas there was at the start of the action (before any action was called)
    /// @param jobHash The hash of the job which was performed.
    ///                All vaults other than DynamicJobs can only have one job,
    ///                so in this case jobHash will just be actionHash.
    function reimburseGas(
        address targetAddress,
        uint256 originalGas,
        bytes32 jobHash
    ) external onlyOrchestrator {
        // Calculate reimbursement amount
        uint256 gasUsed = originalGas - gasleft();
        uint256 ethUsed = (gasUsed * tx.gasprice);

        // Distribute funds
        ethBalances[targetAddress] -= ethUsed;
        unchecked {
            ethBalances[tx.origin] += ethUsed;
        }
        emit EtherUsed(targetAddress, ethUsed, jobHash);
    }
}

