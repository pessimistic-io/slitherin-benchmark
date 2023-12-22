// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import { IGasVault } from "./IGasVault.sol";
import { IOrchestrator } from "./IOrchestrator.sol";
import { IKeeperRegistry } from "./IKeeperRegistry.sol";
import "./ContextUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

/*
    note there is no current on-chain method for slashing misbehaving strategies. The worst misbehaving strategies can do is trigger repeated calls to this contract.

    note This contract relies on the assumption that jobs can only be created by vault and strategy creators. The most serious incorrect target addresses (the orchestrator
    address and the gasVault address) are blocked, but other vaults are protected by the keepers themselves.
 */
contract Orchestrator is IOrchestrator, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant actionThresholdPercent = 51; // If an action is approved by >= approvalThresholdPercent members, it is approved

    //Used for differentiating actions which needs time-sensitive data
    string private constant salt = "$$";

    // Address of GasVault, which is the contract used to recompense keepers for gas they spent executing actions
    address public gasVault;

    // Address of Keeper Registry, which handles keeper verification
    address public keeperRegistry;

    // Operator node action participation reward. Currently unused.
    uint256 public rewardPerAction;

    /*
        bytes32 is hash of action. Calculated using keccak256(abi.encode(targetAddress, jobEpoch, calldatas))

        Action approval meaning:
        0: Pending
        1: Approved
        Both votes and overall approval status follow this standard.
    */
    mapping(bytes32 => ActionState) public actions;

    /*  
        actionHash => uint256 where each bit represents one keeper vote.
    */
    mapping(bytes32 => uint256) public voteBitmaps;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    /**
     * @dev initialize the Orchestrator
     * @param _keeperRegistry address of the keeper registry
     * @param _rewardPerAction is # of SteerToken to give to operator nodes for each completed action (currently unused)
     */
    function initialize(
        address _keeperRegistry,
        uint256 _rewardPerAction
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        require(_keeperRegistry != address(0), "address(0)");
        keeperRegistry = _keeperRegistry;
        rewardPerAction = _rewardPerAction;
    }

    /**
     * @dev allows owner to set/update gas vault address. Mainly used to resolve mutual dependency.
     */
    function setGasVault(address _gasVault) external onlyOwner {
        require(_gasVault != address(0), "address(0)");
        gasVault = _gasVault;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev set the reward given to operator nodes for their participation in a strategy calculation
     * @param _rewardPerAction is amount of steer token to be earned as a reward, per participating operator node per action.
     */
    function setRewardPerAction(uint256 _rewardPerAction) external onlyOwner {
        rewardPerAction = _rewardPerAction;
    }

    /**
     * @dev vote (if you are a keeper) on a given action proposal
     * @param actionHash is the hash of the action to be voted on
     * @param vote is the vote to be cast. false: reject, true: approve. false only has an effect if the keeper previously voted true. It resets their vote to false.
     */
    function voteOnAction(bytes32 actionHash, bool vote) public {
        // Get voter keeper license, use to construct bitmap. Revert if no license.
        uint256 license = IKeeperRegistry(keeperRegistry).checkLicense(
            msg.sender
        );
        uint256 bitmap = 1 << license;
        if (vote) {
            // Add vote to bitmap through OR
            voteBitmaps[actionHash] |= bitmap;
        } else {
            // Remove vote from bitmap through And(&) and negated bitmap(~bitmap).
            voteBitmaps[actionHash] &= ~bitmap;
        }
        emit Vote(actionHash, msg.sender, vote);
    }

    /**
     * @dev Returns true if an action with given `actionId` is approved by all existing members of the group.
     * It’s up to the contract creators to decide if this method should look at majority votes (based on ownership)
     * or if it should ask consent of all the users irrespective of their ownerships.
     */
    function actionApprovalStatus(
        bytes32 actionHash
    ) public view returns (bool) {
        /*
            maxLicenseId represents the number at which the below for loop should stop checking the bitmap for votes. It's 1 greater than the last keeper's
            bitmap number so that the loop ends after handling the last keeper.
        */
        uint256 maxLicenseId = IKeeperRegistry(keeperRegistry)
            .maxNumKeepers() + 1;
        uint256 yesVotes;
        uint256 voteDifference;
        uint256 voteBitmap = voteBitmaps[actionHash];
        for (uint256 i = 1; i != maxLicenseId; ++i) {
            // Get bit which this keeper has control over
            voteDifference = 1 << i;

            // If the bit at this keeper's position has been flipped to 1, they approved this action
            if ((voteBitmap & voteDifference) == voteDifference) {
                ++yesVotes;
            }
        }

        // Check current keeper count to get threshold
        uint256 numKeepers = IKeeperRegistry(keeperRegistry)
            .currentNumKeepers();

        // If there happen to be no keepers, div by zero error will happen here, preventing actions from being executed.
        return ((yesVotes * 100) / numKeepers >= actionThresholdPercent);
    }

    /**
     * @dev Executes the action referenced by the given `actionId` as long as it is approved actionThresholdPercent of group.
     * The executeAction executes all methods as part of given action in an atomic way (either all should succeed or none should succeed).
     * Once executed, the action should be set as executed (state=3) so that it cannot be executed again.

     * @param targetAddress is the address which will be receiving the action's calls.
     * @param jobEpoch is the job epoch of this action.
     * @param calldatas is the COMPLETE calldata of each method to be called
     * note that the hash is created using the sliced calldata, but here it must be complete or the method will revert.
     * @param timeIndependentLengths--For each calldata, the number of bytes that is NOT time-sensitive. If no calldatas are time-sensitive, just pass an empty array.
     * @param jobHash is the identifier for the job this action is related to. This is used for DynamicJobs to identify separate jobs to the subgraph.
     * @return actionState corresponding to post-execution action state. Pending if execution failed, Completed if execution succeeded.
     */
    function executeAction(
        address targetAddress,
        uint256 jobEpoch,
        bytes[] calldata calldatas,
        uint256[] calldata timeIndependentLengths,
        bytes32 jobHash
    ) external returns (ActionState) {
        // Make sure this action is approved and has not yet been executed
        bytes32 actionHash;
        if (timeIndependentLengths.length == 0) {
            // If none of the data is time-sensitive, just use passed in calldatas
            actionHash = keccak256(
                abi.encode(targetAddress, jobEpoch, calldatas)
            );
        } else {
            // If some of it is time-sensitive, create a new array using timeIndependentLengths to represent what was originally passed in, then compare that hash instead
            uint256 calldataCount = timeIndependentLengths.length;

            // Construct original calldatas
            bytes[] memory timeIndependentCalldatas = new bytes[](
                calldataCount
            );
            for (uint256 i; i != calldataCount; ++i) {
                timeIndependentCalldatas[i] = calldatas[
                    i
                ][:timeIndependentLengths[i]];
            }

            // Create hash from sliced calldatas
            actionHash = keccak256(
                abi.encode(
                    targetAddress,
                    jobEpoch,
                    timeIndependentCalldatas,
                    salt
                )
            );
        }

        // Ensure action has not yet been executed
        require(
            actions[actionHash] == ActionState.PENDING,
            "Action already executed"
        );

        // Make sure this action isn't illegal (must be checked here, since elsewhere the contract only knows the action hash)
        require(targetAddress != address(this), "Invalid target address");
        require(targetAddress != gasVault, "Invalid target address");

        // Set state to completed
        actions[actionHash] = ActionState.COMPLETED;

        // Have this keeper vote for action. This also checks that the caller is a keeper.
        voteOnAction(actionHash, true);

        // Check action approval status, execute accordingly.
        bool actionApproved = actionApprovalStatus(actionHash);
        if (actionApproved) {
            // Set aside gas for this action. Keeper will be reimbursed ((originalGas - [gas remaining when returnGas is called]) * gasPrice) wei.
            uint256 originalGas = gasleft();

            // Execute action
            (bool success, ) = address(this).call{ // Check gas available for this transaction. This call will fail if gas available is insufficient or this call's gas price is too high.
                gas: IGasVault(gasVault).gasAvailableForTransaction(
                    targetAddress
                )
            }(
                abi.encodeWithSignature(
                    "_executeAction(address,bytes[])",
                    targetAddress,
                    calldatas
                )
            );

            // Reimburse keeper for gas used, whether action execution succeeded or not. The reimbursement will be stored inside the GasVault.
            IGasVault(gasVault).reimburseGas(
                targetAddress,
                originalGas,
                jobHash == bytes32(0) ? actionHash : jobHash // If a jobhash was passed in, use that. Otherwise use the action hash.
            );

            // Record result
            if (success) {
                emit ActionExecuted(actionHash, _msgSender(), rewardPerAction);
                return ActionState.COMPLETED;
            } else {
                emit ActionFailed(actionHash);
                // Set state to pending
                actions[actionHash] = ActionState.PENDING;
                return ActionState.PENDING;
            }
        } else {
            // If action is not approved, revert.
            revert("Votes lacking; state still pending");
        }
    }

    function _executeAction(
        address targetAddress,
        bytes[] calldata calldatas
    ) external {
        require(
            msg.sender == address(this),
            "Only Orchestrator can call this function"
        );

        bool success;
        uint256 calldataCount = calldatas.length;
        for (uint256 i; i != calldataCount; ++i) {
            (success, ) = targetAddress.call(calldatas[i]);

            // If any method fails, the action will revert, reverting all other methods but still pulling gas used from the GasVault.
            require(success);
        }
    }
}

