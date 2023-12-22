//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./console.sol";

import "./ECDSA.sol";

/**
 * This library is the logic and storage used for multi-sig ops
 */
library LibMultiSig {

    //initial multi-sig initialization settings
    struct MultiSigConfig {
        uint8 requiredSigs;
        uint32 timelockSeconds;
        address logic;
        address[] approvers;
    }

    //a pending change of some kind
    struct PendingChange {
        uint8 approvals;
        bytes32 sigHash;
        bytes4 selector;
        bytes fnData;
        uint allowedAfterTime;
    }

    //pending upgrade to contract logic
    struct PendingUpgrade {
        uint8 approvals;
        bytes32 sigHash;
        address newLogic;
        uint allowedAfterTime;
    }

    //pending resume request
    struct PendingResume {
        uint8 approvals;
        bytes32 sigHash;
        uint allowedAfterTime;
    }


    event ChangeRequested(address indexed approver, bytes4 selector, bytes32 sigHash, uint nonce, uint timelockExpiration);
    event UpgradeRequested(address indexed approver, address logic, bytes32 sigHash, uint timelockExpiration);
    event ResumeRequested(address indexed approvder, bytes32 sigHash);
    event LogicUpgraded(address indexed newLogic);
    event ResumedOperations();

    /**
     * The primary storage for MultiSig ops
     */
    struct MultiSigStorage {

        //whether the multi-sig is pausing all public operations
        bool paused;

        //number of sigs required to make changes
        uint8 requiredSigs;

        //the logic implementation for the proxy using this multi-sig
        address logic;

        //unique nonce for change sigs
        uint nonce;

        //how many seconds to wait before changes are allowed to be committed
        uint32 timelockSeconds;

        //pending logic upgrade.
        PendingUpgrade pendingUpgrade;

        //pending resume request waiting on sigs
        PendingResume pendingResume;

        //changes are pending function calls with timelock and sig requirement
        mapping(uint => PendingChange) pendingChanges;

        //whether a particular address signed off on a change hash yet
        mapping(bytes32 => address[]) signedChanges;

        //all approved change function call selectors are stored here. They are
        //check when the change function is called. It must be sig approved and
        //expire its timelock before it ends up here
        mapping(bytes4 => bool) approvedCalls;

        //all approved signers
        mapping(address => bool) approvedSigner;
    }

    /**
     * Intialize multi-sig settings
     */
    function initializeMultSig(MultiSigStorage storage ms, MultiSigConfig calldata config) public {
        require(ms.requiredSigs == 0, "Already initialized");
        require(config.requiredSigs > 1, "At least 2 signers required");
        require(config.approvers.length >= config.requiredSigs, "Need at least as many approvers as sigs required");
        require(config.timelockSeconds > 0, "Invalid timelock");
        require(config.logic != address(0), "Invalid logic address");
        ms.requiredSigs = config.requiredSigs;
        ms.logic = config.logic;
        ms.timelockSeconds = config.timelockSeconds;
        for(uint i=0;i<config.approvers.length;i=_incr(i)) {
            ms.approvedSigner[config.approvers[i]] = true;
        }
    }

    /****************************************************************************
     * Pause Logic
     *****************************************************************************/

     /**
      * Request that the contract resume normal operations.
      */
    function requestResume(MultiSigStorage storage ms) public {
        //make sure we're paused
        require(ms.paused, "Not currently paused");
        //create sighash from next nonce
        bytes32 sigHash = keccak256(abi.encode(ms.nonce, block.chainid));

        //mark sender as having signed the hash
        ms.signedChanges[sigHash].push(msg.sender);

        //immediate expiration so that it can be resumed right away once approved
        uint exp = block.timestamp;
        ms.pendingResume = PendingResume({
            approvals: 1,
            sigHash: sigHash,
            allowedAfterTime: exp
        });
        //increment for next op
        ++ms.nonce;
        emit ResumeRequested(msg.sender, sigHash);
    }

    /**
     * Cancel a request to resume operations
     */
    function cancelResume(MultiSigStorage storage ms) public {
        require(ms.pendingResume.allowedAfterTime > 0, "No pending resume");
        delete ms.pendingResume;
    }

    /**
     * Whether we can resume operations yet
     */
    function canResume(MultiSigStorage storage ms) public view returns (bool) {
        require(ms.pendingResume.allowedAfterTime > 0, "No pending resume");
        return ms.pendingResume.approvals + 1 >= ms.requiredSigs;
    }

    /**
     * Number of approvals needed to resume ops
     */
    function resumeSigsNeeded(MultiSigStorage storage ms) public view returns (uint8) {
        require(ms.pendingResume.allowedAfterTime > 0, "No pending resume");
        return ms.requiredSigs - ms.pendingResume.approvals;
    }

    /**
     * Delegated signature to resume operations
     */
    function delegatedApproveResume(MultiSigStorage storage ms, address signer, bytes calldata sig) public {
        //make sure signer is authorized
        require(ms.approvedSigner[signer], "Unauthorized signer");
        PendingResume storage pu = ms.pendingResume;
        require(pu.allowedAfterTime > 0, "No pending resume request");
        //and that their sig is valid
        address check = ECDSA.recover(_asMessage(pu.sigHash), sig);
        require(check == signer, "Invalid signature");
        //then actually resume
        _doApproveResume(ms, signer, pu);
    }

    /**
     * Approver approving resume ops
     */
    function approveResume(MultiSigStorage storage ms) public {
        PendingResume storage pu = ms.pendingResume;
        require(pu.allowedAfterTime > 0, "No pending resume request");
        _doApproveResume(ms, msg.sender, pu);
    }

    function _doApproveResume(MultiSigStorage storage ms, address signer, PendingResume storage pu) private {
        //make sure didn't sign already
        require(!_contains(ms.signedChanges[pu.sigHash],signer), "Signer already signed");
        //increment approvals
        ++pu.approvals;
        bytes32 sigHash = pu.sigHash;
        //see if we've hit threshold yt
        if(pu.approvals >= ms.requiredSigs) {
            //no longer paused
            ms.paused = false;
            //cleanup requests and signature history
            delete ms.signedChanges[sigHash];
            delete ms.pendingResume;
        } else {
            //if mark signer as approving resume
            ms.signedChanges[sigHash].push(signer);
        }
    }
    //--------------------------------------------------------------------------------


    /****************************************************************************
     * Upgrade logic
     *****************************************************************************/

     /**
      * Request that the underlying logic for this contract be upgraded
      */
    function requestUpgrade(MultiSigStorage storage ms, address logic) public {
        //ensure not setting incorrectly
        require(logic != address(0), "Invalid logic address");
        
        //hash of address and unique op nonce (and chain to prevent replays)
        bytes32 sigHash = keccak256(abi.encode(logic, ms.nonce, block.chainid));

        //mark sender as approving op
        ms.signedChanges[sigHash].push(msg.sender);

        //expiration is after timelock
        uint exp = block.timestamp + ms.timelockSeconds;
        ms.pendingUpgrade = PendingUpgrade({
            approvals: 1,
            sigHash: sigHash,
            newLogic: logic,
            allowedAfterTime: exp
        });

        //increment for next op
        ++ms.nonce;
        emit UpgradeRequested(msg.sender, logic, sigHash, exp);
    }

    /**
     * Cancel request to upgrade the contract logic
     */
    function cancelUpgrade(MultiSigStorage storage ms) public {
        delete ms.pendingUpgrade;
    }

    /**
     * Whether we can upgrade the logic yet
     */
    function canUpgrade(MultiSigStorage storage ms) public view returns (bool) {
        return ms.pendingUpgrade.allowedAfterTime > 0 &&
                ms.pendingUpgrade.allowedAfterTime < block.timestamp &&
                ms.pendingUpgrade.approvals + 1 >= ms.requiredSigs;
    }

    /**
     * Signatures needed to approve an upgrade
     */
    function upgradeSigsNeeded(MultiSigStorage storage ms) public view returns (uint8) {
        require(ms.pendingUpgrade.allowedAfterTime > 0, "No pending upgrade");
        return ms.requiredSigs - ms.pendingUpgrade.approvals;
    }

    /**
     * Delegate approval to upgrade the contract logic
     */
    function delegatedApproveUpgrade(MultiSigStorage storage ms, address signer, bytes calldata sig) public {
        //make sure signer is an approver
        require(ms.approvedSigner[signer], "Unauthorized signer");

        //make sure there is a valid upgrade pending
        PendingUpgrade storage pu = ms.pendingUpgrade;
        require(pu.allowedAfterTime > 0, "No pending change for that nonce");

        //make sure signature is valid
        address check = ECDSA.recover(_asMessage(pu.sigHash), sig);
        require(check == signer, "Invalid signature");

        //then approve the upgrade
        _doApproveUpgrade(ms, signer, pu);
    }

    /**
     * Approver calling to approve logic upgrade
     */
    function approveUpgrade(MultiSigStorage storage ms) public {
        //make sure upgrade is actually pending
        PendingUpgrade storage pu = ms.pendingUpgrade;
        require(pu.allowedAfterTime > 0, "No pending change for that nonce");
        _doApproveUpgrade(ms, msg.sender, pu);
    }

    /**
     * Perform logic upgrade.
     */
    function _doApproveUpgrade(MultiSigStorage storage ms, address signer, PendingUpgrade storage pu) private {
         //make sure we haven't already upgraded
        require(ms.logic != ms.pendingUpgrade.newLogic, "Already upgraded");
        
        //make sure signer hasn't signed already
        require(!_contains(ms.signedChanges[pu.sigHash],signer), "Signer already signed");
       
        //increment approval count
        ++pu.approvals;
        bytes32 sigHash = pu.sigHash;

        //if we've reached threshold and waited long enough
        if(pu.approvals >= ms.requiredSigs && pu.allowedAfterTime < block.timestamp) {
            //perform upgrade
            doUpgrade(ms, pu);
            //remove signatures for upgrade request
            delete ms.signedChanges[sigHash];
        } else {
            //mark signer as having approved
            ms.signedChanges[sigHash].push(signer);
        }
    }

    //perform upgrade
    function doUpgrade(MultiSigStorage storage ms, PendingUpgrade storage pu) private {
        //set new logic contract address
        ms.logic = pu.newLogic;
        //remove pending upgrade
        delete ms.pendingUpgrade;

        //tell world we've upgraded
        emit LogicUpgraded(ms.logic);
    }
    //--------------------------------------------------------------------------------





    /****************************************************************************
     * Config change
     *****************************************************************************/

     /**
      * Request that a setting be changed
      */
    function requestChange(MultiSigStorage storage ms, bytes calldata data) public {
        //make sure we have a valid selector to call
        require(data.length >= 4, "Invalid call data");

        //get the selector bytes
        bytes4 sel = bytes4(data[:4]);

        //hash call data with unique op nonce and chain
        bytes32 sigHash = keccak256(abi.encode(data, ms.nonce, block.chainid));

        //mark caller as already approved
        ms.signedChanges[sigHash].push(msg.sender);
        
        //expire after timelock
        uint exp = block.timestamp + ms.timelockSeconds;
        ms.pendingChanges[ms.nonce] = PendingChange({
            approvals: 1, //presumably the caller making the request is checked before lib used
            sigHash: sigHash,
            selector: sel,
            fnData: data,
            allowedAfterTime: exp
        });

        //emit the event of the requested change
        emit ChangeRequested(msg.sender, sel, sigHash, ms.nonce, exp);

        //make nonce unique for next run (after event emitted so everyone knows which nonce
        //the change applies to)
        ++ms.nonce;
    }

    /**
     * Cancel a specific change request
     */
    function cancelChange(MultiSigStorage storage ms, uint nonce) public {
        delete ms.pendingChanges[nonce];
    }

    /**
     * Whether we can apply a specific change
     */
    function canApplyChange(MultiSigStorage storage ms, uint nonce) public view   {
        PendingChange storage pc = ms.pendingChanges[nonce];
        //pending change is still pending
        require(pc.allowedAfterTime > 0, "No pending change for that nonce");
        //and we've waited long enough with one more sig to go
        require(pc.allowedAfterTime < block.timestamp && 
            pc.approvals + 1 >= ms.requiredSigs, "Not able to apply yet");
    }

    /**
     * The number of signatures required to apply a specific change
     */
    function changeSigsNeeded(MultiSigStorage storage ms, uint nonce) public view returns (uint) {
        //make sure valid change
        PendingChange storage pc = ms.pendingChanges[nonce];
        require(pc.allowedAfterTime > 0, "No pending change for nonce");
    
        return ms.requiredSigs - pc.approvals;
    }

    /**
     * Delegated approval for a specific change
     */
    function delegatedApproveChange(MultiSigStorage storage ms, uint nonce, address signer, bytes calldata sig) public {
        //make sure signer is authorized
        require(ms.approvedSigner[signer], "Unauthorized signer");

        //and change is still valid
        PendingChange storage pc = ms.pendingChanges[nonce];
        require(pc.allowedAfterTime > 0, "No pending change for that nonce");

        //and signer has valid signature
        address check = ECDSA.recover(_asMessage(pc.sigHash), sig);
        require(check == signer, "Invalid signature");

        //then do the change
        _doChangeApproval(ms, nonce, signer, pc);
    }

    /**
     * Approver calling to approve a specific change
     */
    function approveChange(MultiSigStorage storage ms, uint nonce) public {
        //Make sure caller is a signer
        require(ms.approvedSigner[msg.sender], "Unauthorized signer");

        //and that change is still valid
        PendingChange storage pc = ms.pendingChanges[nonce];
        require(pc.allowedAfterTime > 0, "No pending change for that nonce");

        //then apply change
        _doChangeApproval(ms, nonce, msg.sender, pc);
    }

    /**
     * Apply a pending change
     */
    function _doChangeApproval(MultiSigStorage storage ms, uint nonce, address caller, PendingChange storage pc) private {
        
        //make sure they haven't signed yet
        require(!_contains(ms.signedChanges[pc.sigHash], caller), "Already signed approval");
        
        //inrement total approvals
        ++pc.approvals;
        
        bytes4 sel = pc.selector;

        //see if we've met thresholds
        if(pc.approvals >= ms.requiredSigs && pc.allowedAfterTime < block.timestamp) {
            //mark the operation as being approved. This allows us to actually 
            //call the function that is marked with modifier checking for prior approval
            ms.approvedCalls[sel] = true;
            
            //invoke the actual function
            (bool success,bytes memory retData) = address(this).call(pc.fnData);
            if(success) {
                //only get rid of pending approval change if the call succeeded
                delete ms.pendingChanges[nonce];
                delete ms.signedChanges[pc.sigHash];
            } else {
                //otherwise, the approved call data will be retained and we can try again
                console.log("Change failed");
                console.logBytes(retData);
            }
            //no matter the outcome, always reset the approval 
            //so that no one can call the selector without approval going through
            delete ms.approvedCalls[sel];
        } else {
            //mark caller as having signed
            ms.signedChanges[pc.sigHash].push(caller);
        }
    }

    //utility function to see if an address is in an array of approvers
    function _contains(address[] storage ar, address tgt) private view returns (bool) {
        for(uint i=0;i<ar.length;i=_incr(i)) {
            if(ar[i] == tgt) {
                return true;
            }
        }
        return false;
    }

    //removes uint guard for incrementing counter
    function _incr(uint i) internal pure returns (uint) {
        unchecked { return i + 1; }
    }

    //convert sig hash to message signed by EOA/approver
    function _asMessage(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", h));
    }
}
