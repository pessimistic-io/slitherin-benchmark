// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.12;

/**
 * @dev Interface of the Orchestrator.
 */
interface IOrchestrator {
    enum ActionState {
        PENDING,
        COMPLETED
    }

    /**
     * @dev MUST trigger when actions are executed.
     * @param actionHash: keccak256(targetAddress, jobEpoch, calldatas) used to identify this action
     * @param from: the address of the keeper that executed this action
     * @param rewardPerAction: SteerToken reward for this action, to be supplied to operator nodes.
     */
    event ActionExecuted(
        bytes32 indexed actionHash,
        address from,
        uint256 rewardPerAction
    );
    event ActionFailed(bytes32 indexed actionHash);
    event Vote(
        bytes32 indexed actionHash,
        address indexed from,
        bool approved
    );

    // If an action is approved by >= approvalThresholdPercent members, it is approved
    function actionThresholdPercent() external view returns (uint256);

    // Address of GasVault, which is the contract used to recompense keepers for gas they spent executing actions
    function gasVault() external view returns (address);

    // Address of Keeper Registry, which handles keeper verification
    function keeperRegistry() external view returns (address);

    // Operator node action participation reward. Currently unused.
    function rewardPerAction() external view returns (uint256);

    /*
        bytes32 is hash of action. Calculated using keccak256(abi.encode(targetAddress, jobEpoch, calldatas))

        Action approval meaning:
        0: Pending
        1: Approved
        Both votes and overall approval status follow this standard.
    */
    function actions(bytes32) external view returns (ActionState);

    /*  
        actionHash => uint256 where each bit represents one keeper vote.
    */
    function voteBitmaps(bytes32) external view returns (uint256);

    /**
     * @dev initialize the Orchestrator
     * @param _keeperRegistry address of the keeper registry
     * @param _rewardPerAction is # of SteerToken to give to operator nodes for each completed action (currently unused)
     */
    function initialize(address _keeperRegistry, uint256 _rewardPerAction)
        external;

    /**
     * @dev allows owner to set/update gas vault address. Mainly used to resolve mutual dependency.
     */
    function setGasVault(address _gasVault) external;

    /**
     * @dev set the reward given to operator nodes for their participation in a strategy calculation
     * @param _rewardPerAction is amount of steer token to be earned as a reward, per participating operator node per action.
     */
    function setRewardPerAction(uint256 _rewardPerAction) external;

    /**
     * @dev vote (if you are a keeper) on a given action proposal
     * @param actionHash is the hash of the action to be voted on
     * @param vote is the vote to be cast. false: reject, true: approve. false only has an effect if the keeper previously voted true. It resets their vote to false.
     */
    function voteOnAction(bytes32 actionHash, bool vote) external;

    /**
     * @dev Returns true if an action with given `actionId` is approved by all existing members of the group.
     * It’s up to the contract creators to decide if this method should look at majority votes (based on ownership)
     * or if it should ask consent of all the users irrespective of their ownerships.
     */
    function actionApprovalStatus(bytes32 actionHash)
        external
        view
        returns (bool);

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
    ) external returns (ActionState);
}

