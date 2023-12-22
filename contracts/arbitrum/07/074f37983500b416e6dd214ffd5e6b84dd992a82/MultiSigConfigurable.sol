//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibStorage.sol";

/**
 * This contract aims to mitigate concerns over a single EOA upgrading or making
 * config changes to deployed contracts. It essentially requires that N-signatures 
 * approve any config change along with a timelock before the change can be applied.
 * 
 * The intent is for the community to have more awareness/insight into the changes being
 * made and why. The timelock period gives the community an opportunity to voice concerns
 * so that any pending change can be cancelled for reconsideration.
 *
 * The way this works is changes are associated with an underlying function selector. 
 * That selector will not be callable until at least the minimum signatures are provided
 * approving the change. Once approvals are provided, and enough time has ellapsed, 
 * the underlying change function is called and the approval is cleared for the next 
 * change.
 *
 * Pausing is also supported such that it can only be called by an approver. Pause function 
 * is an emergency and is immediately enforced without multiple signatures. Resume requires 
 * multiple parties to resume operations.
 */
abstract contract MultiSigConfigurable {
    
    using LibMultiSig for LibMultiSig.MultiSigStorage;

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);

    event RequiredSigChanged(uint newReq);
    event ChangeRequested(address indexed approver, bytes4 selector, bytes32 sigHash, uint nonce, uint timelockExpiration);
    event UpgradeRequested(address indexed approver, address logic, bytes32 sigHash, uint timelockExpiration);

    event LogicUpgraded(address indexed newLogic);

    event Paused(address indexed caller);
    event ResumeRequested(address indexed approvder, bytes32 sigHash);
    event ResumedOperations();

    /**
     * Modifier to check whether a specific function has been approved by required signers
     */
    modifier afterApproval(bytes4 selector) {
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        require(ms.approvedCalls[selector], "Not approved to call");
        _;
    }

    /**
     * Only an approver can call the function with this modifier
     */
    modifier onlyApprover() {
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        require(ms.approvedSigner[msg.sender], "Unauthorized");
        _;
    }

    /**
     * Function is only callable when contract is not paused
     */
    modifier notPaused() {
        require(!LibStorage.getMultiSigStorage().paused, "Not while paused");
        _;
    }
    
    /**
     * Validate and initialize the multi-sig stored configuration settings. This is 
     * only callable once after deployment.
     */
    function initializeMSConfigurable(LibMultiSig.MultiSigConfig memory config) public {
        LibStorage.getMultiSigStorage().initializeMultSig(config);
    }

    /**
     * Add a signer to the multi-sig
     */
    function addSigner(address signer) public onlyApprover {
        require(address(0) != signer, "Invalid signer");
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        ms.approvedSigner[signer] = true;
        emit SignerAdded(signer);
    }

    /** 
     * Remove a signer from the multi-sig
     */
    function removeSigner(address signer) public onlyApprover {
        require(address(0) != signer, "Invalid signer");
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        delete ms.approvedSigner[signer];
        emit SignerRemoved(signer);
    }

    /**
     * Make an adjustment to the minimum number of signers. This requires approval 
     * from signers as well as a timelock delay.
     */
    function setRequiredSigs(uint8 sigs) public afterApproval(this.setRequiredSigs.selector) {
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        ms.requiredSigs = sigs;
        emit RequiredSigChanged(sigs);
    }

    /****************************************************************************
     * Pause logic
     *****************************************************************************/
    /** 
     * Pause is immediately enforced by a single approver
     */
    function pause() public onlyApprover {
        LibMultiSig.MultiSigStorage storage ms = LibStorage.getMultiSigStorage();
        ms.paused = true;
        emit Paused(msg.sender);
    }

    /**
     * Determine if the contract is paused
     */
    function isPaused() public view returns (bool) {
        return LibStorage.getMultiSigStorage().paused;
    }

    /**
     * Request that the contract resume operations.
     */
    function requestResume() public onlyApprover {
        LibStorage.getMultiSigStorage().requestResume();
    }

    /**
     * Cancel a resume request
     */
    function cancelResume() public onlyApprover {
        LibStorage.getMultiSigStorage().cancelResume();
    }

    function resumeSigsNeeded() public view returns(uint8) {
        return LibStorage.getMultiSigStorage().resumeSigsNeeded();
    }

    function delegatedApproveResume(address signer, bytes calldata sig) public onlyApprover {
        LibStorage.getMultiSigStorage().delegatedApproveResume(signer, sig);
    }

    function approveResume() public onlyApprover {
        LibStorage.getMultiSigStorage().approveResume();
    }
    //END PAUSE LOGIC---------------------------------------------------------------
    



    /****************************************************************************
     * Upgrade logic
     *****************************************************************************/
    
    /**
     * Request that the multi-sig's underlying logic change. This registers a requirements
     * for signers to approve the upgrade.
     */
    function requestUpgrade(address logic) public onlyApprover {
        LibStorage.getMultiSigStorage().requestUpgrade(logic);
    }

    /**
     * Whether a pending upgrade has sufficieint signatures and enough time has ellapsed
     */
    function canUpgrade() public view returns (bool) {
        return LibStorage.getMultiSigStorage().canUpgrade();
    }

    /**
     * The number of signatures needed for an upgrade
     */
    function upgradeSignaturesNeeded() public view returns (uint) {
        return LibStorage.getMultiSigStorage().upgradeSigsNeeded();
    }

    /**
     * Manual call to approve a pending upgrade.
     */
    function approveUpgrade() public onlyApprover {
        LibStorage.getMultiSigStorage().approveUpgrade();
    }

    /**
     * A delegated approval for an upgrade. The signed hash is derived from events 
     * emitted when upgrade was requested.
     */
    function delegatedApproveUpgrade(address signer, bytes calldata sig) public onlyApprover {
        LibStorage.getMultiSigStorage().delegatedApproveUpgrade(signer, sig);
    }
    //END UPGRADE LOGIC---------------------------------------------------------------



    /****************************************************************************
     * Change logic
     *****************************************************************************/

    /**
     * Request a change be made to the contract settings. The details of what is changed 
     * are embedded in the calldata. This should be the function call that will be executed
     * on this contract once approval is settled.
     */
    function requestChange(bytes calldata data) public onlyApprover {
        LibStorage.getMultiSigStorage().requestChange(data);
    }

    /**
     * Cancel a pending change using the nonce that was provided in the event emitted
     * when the change was requested.
     */
    function cancelChange(uint nonce) public onlyApprover {
        LibStorage.getMultiSigStorage().cancelChange(nonce);
    }

    /**
     * Whether a change can be applied. The nonce is emitted as part of the request change event.
     */
    function canApplyChange(uint nonce) public view {
        return LibStorage.getMultiSigStorage().canApplyChange(nonce);
    }

    /**
     * Number of signatures needed to approve a specific change.
     */
    function changeSigsNeeded(uint nonce) public view returns (uint) {
        return LibStorage.getMultiSigStorage().changeSigsNeeded(nonce);
    }

    /**
     * Delegated approval for a specific change.
     */
    function delegatedApproveChange(uint nonce, address signer, bytes calldata sig) public onlyApprover {
        LibStorage.getMultiSigStorage().delegatedApproveChange(nonce, signer, sig);
    }

    /**
     * Direct approve for a specific change.
     */
    function approveChange(uint nonce) public onlyApprover {
        LibStorage.getMultiSigStorage().approveChange(nonce);
    }
    //END CHANGE LOGIC---------------------------------------------------------------

}
