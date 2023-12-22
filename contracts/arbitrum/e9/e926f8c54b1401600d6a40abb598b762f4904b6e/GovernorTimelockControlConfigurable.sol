//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import "./IGovernorTimelock.sol";
import "./Governor.sol";
import "./GovernanceErrors.sol";
import "./CoraTimelockController.sol";

/**
 * @notice Modified version of OZ {GovernorTimelockControl} that allows timelock delay configurations depending on the action to be executed
 * while still keeping compatibility with anything that already supports the Openzeppelin Governance module
 *
 */
abstract contract GovernorTimelockControlConfigurable is IGovernorTimelock, Governor {
  CoraTimelockController private _timelock;
  mapping(uint256 => bytes32) private _timelockIds;
  address _messageRelayer;
  mapping(bytes4 => DelayType) private _functionsDelays;
  uint256 private _defaultDelay;
  uint256 private _shortDelay;
  uint256 private _longDelay;

  enum DelayType
  // we do not need it here but we keep it at the first slot so when
  // _functionsDelays is queried, if an entry does not exist in the mapping (and returns 0)
  // will be the same than setting it to DEFAULT
  //
  {
    DEFAULT,
    // short delay type is used for emergency proposals
    // in order for a proposal to have a SHORT delay, all functions calls must have the SHORT delay type
    // This is to avoid having a malicious proposal bypass the timelock by including just a pause function after
    // the malicious operation
    SHORT,
    // long delay type is used to operations like recovering funds from the pool
    // as long as 1 function call belongs to this type, the whole proposal will have a LONG delay
    // This is to avoid a malicious DAO to include any actions PLUS recovering funds from the pool
    // and bypass the long timelock to give users time to recover their positions
    LONG
  }

  /**
   * @dev Emitted when the timelock controller used for proposal execution is modified.
   */
  event TimelockChange(address oldTimelock, address newTimelock);

  /**
   * @dev Set the timelock and configure timelocks for function signatures
   *
   */
  constructor(
    CoraTimelockController timelockAddress,
    address messageRelayer,
    bytes4[] memory functionSignatures,
    DelayType[] memory functionsDelays,
    uint256 defaultDelay,
    uint256 shortDelay,
    uint256 longDelay
  ) {
    _defaultDelay = defaultDelay;
    _shortDelay = shortDelay;
    _longDelay = longDelay;
    _messageRelayer = messageRelayer;
    if (functionSignatures.length != functionsDelays.length) {
      revert DaoInvalidDelaysConfiguration();
    }
    for (uint256 i = 0; i < functionSignatures.length; i++) {
      _functionsDelays[functionSignatures[i]] = functionsDelays[i];
    }

    // selectors are not visible at this point
    _functionsDelays[bytes4(keccak256("updateLongDelay(uint256)"))] = DelayType.LONG;
    _functionsDelays[bytes4(keccak256("updateDefaultDelay(uint256)"))] = DelayType.LONG;
    _functionsDelays[bytes4(keccak256("updateShortDelay(uint256)"))] = DelayType.LONG;
    _functionsDelays[bytes4(keccak256("addDelayConfiguration(bytes4[],bytes4[],bytes4[])"))] =
      DelayType.LONG;

    _updateTimelock(timelockAddress);
  }

  function addDelayConfiguration(
    bytes4[] memory signaturesLongDelay,
    bytes4[] memory signaturesShortDelay,
    bytes4[] memory signaturesDefaultDelay
  ) external onlyGovernance {
    for (uint256 i = 0; i < signaturesLongDelay.length; i++) {
      _functionsDelays[signaturesLongDelay[i]] = DelayType.LONG;
    }
    for (uint256 i = 0; i < signaturesShortDelay.length; i++) {
      _functionsDelays[signaturesShortDelay[i]] = DelayType.SHORT;
    }
    for (uint256 i = 0; i < signaturesDefaultDelay.length; i++) {
      _functionsDelays[signaturesDefaultDelay[i]] = DelayType.DEFAULT;
    }
  }

  function updateShortDelay(uint256 newDelay) external onlyGovernance {
    _shortDelay = newDelay;
  }

  function updateDefaultDelay(uint256 newDelay) external onlyGovernance {
    _defaultDelay = newDelay;
  }

  function updateLongDelay(uint256 newDelay) external onlyGovernance {
    _longDelay = newDelay;
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(IERC165, Governor)
    returns (bool)
  {
    return
      interfaceId == type(IGovernorTimelock).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @dev Overridden version of the {Governor-state} function with added support for the `Queued` status.
   */
  function state(uint256 proposalId)
    public
    view
    virtual
    override(IGovernor, Governor)
    returns (ProposalState)
  {
    ProposalState status = super.state(proposalId);
    if (status != ProposalState.Succeeded) {
      return status;
    }

    // core tracks execution, so we just have to check if successful proposal have been queued.
    bytes32 queueid = _timelockIds[proposalId];
    if (queueid == bytes32(0)) {
      return status;
    } else if (_timelock.isOperationDone(queueid)) {
      return ProposalState.Executed;
    } else if (_timelock.isOperationPending(queueid)) {
      return ProposalState.Queued;
    } else {
      return ProposalState.Canceled;
    }
  }

  /**
   * @dev Public accessor to check the address of the timelock
   */
  function timelock() public view virtual override returns (address) {
    return address(_timelock);
  }

  /**
   * @dev Public accessor to check the eta of a queued proposal
   */
  function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
    uint256 eta = _timelock.getTimestamp(_timelockIds[proposalId]);
    return eta == 1 ? 0 : eta; // _DONE_TIMESTAMP (1) should be replaced with a 0 value
  }

  /**
   * @dev Function to queue a proposal to the timelock.
   */
  function queue(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) public virtual override returns (uint256) {
    uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
    require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

    uint256 delay = _getDelay(targets, calldatas);
    _timelockIds[proposalId] =
      _timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
    _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

    emit ProposalQueued(proposalId, block.timestamp + delay);

    return proposalId;
  }

  /**
   * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
   * must be proposed, scheduled, and executed through governance proposals.
   *
   * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
   */
  function updateTimelock(CoraTimelockController newTimelock) external virtual onlyGovernance {
    _updateTimelock(newTimelock);
  }

  function _updateTimelock(CoraTimelockController newTimelock) private {
    emit TimelockChange(address(_timelock), address(newTimelock));
    _timelock = newTimelock;
  }

  function updateMessageRelayer(address newMessageRelayer) external onlyGovernance {
    _messageRelayer = newMessageRelayer;
  }

  /**
   * @dev This functions validates that a proposal containing a LONG timelock only has 1 action
   *
   * This is to prevent malicious DAO proposals in a scenario similar to the following:
   * 1. A malicious DAO pauses the protocol (SHORT timelock)
   * 2. The protocol is paused, users can not withdraw their funds
   * 3. The malicious DAO creates a proposal that will: i) unpause, ii) recover funds (LONG timelock)
   *    the users can see the malicious DAO proposal, they would have time to withdraw their funds because of the LONG timelock,
   *    but they can not do it because the contract is paused
   * 4. The proposal eventually gets executed, which will unpause the contracts and steal funds from all users
   *
   * By having this restriction, a proposal where funds will be recovered in a malicious way bypassing the long timelock can not be done
   */
  function _validateProposal(address[] memory targets, bytes[] memory calldatas)
    internal
    view
    returns (bool)
  {
    for (uint256 i = 0; i < calldatas.length; i++) {
      bytes4 sig = _calldataFunctionSignature(targets[i], calldatas[i]);
      if (_functionsDelays[sig] == DelayType.LONG) {
        return calldatas.length == 1;
      }
    }
    return true;
  }

  /**
   * @dev Function used to calculate the timelock delay based on the actions the proposal is trying to eventually execute
   *      If there is ONE function with DelayType == LONG delay, we return _longDelay
   *      If ALL functions have DelayType == SHORT, we return _shortDelay
   *      Otherwise, we return _defaultDelay
   *
   */
  function _getDelay(address[] memory targets, bytes[] memory calldatas)
    internal
    view
    returns (uint256)
  {
    // if there are no functions to execute in a proposal, it won't use the SHORT delay
    // it will also NOT enter the loop, which means the DEFAULT delay will be used
    bool isShortDelay = calldatas.length > 0;
    for (uint256 i = 0; i < calldatas.length; i++) {
      address target = targets[i];
      bytes4 sig = _calldataFunctionSignature(target, calldatas[i]);

      DelayType delay = _functionsDelays[sig];
      if (delay == DelayType.LONG) {
        return _longDelay;
      }
      if (delay != DelayType.SHORT) {
        isShortDelay = false;
      }
    }
    return isShortDelay == true ? _shortDelay : _defaultDelay;
  }

  function _calldataFunctionSignature(address _target, bytes memory _calldata)
    internal
    view
    returns (bytes4)
  {
    bytes4 sig = bytes4(_calldata);
    if (_target == _messageRelayer) {
      // in this case, we have some multichain actions, calling:
      // MessageRelayer.sendMessage(string memory _destinationChain, string memory _destinationAddress, bytes memory _payload)
      // target would be the message relayer address
      // calldata will contain:
      // [keccak256("sendMessage(...)) - 4 bytes][string _destinationChain - X bytes][string _destinationAddress - X bytes][payload - X bytes]
      // we need to slice the array to keep only the bytes after the sendMessage 4 bytes selector, so we can use abi.decode(string,string,bytes)
      // and extract the selector of the actual function that will be executed on the target at the child chain

      bytes memory targetCalldata = _slice(_calldata, 4, _calldata.length - 4);
      (,, bytes memory internalPayload) = abi.decode(targetCalldata, (string, string, bytes));
      sig = bytes4(internalPayload);
    }
    return sig;
  }

  /**
   * @dev Overridden execute function that run the already queued proposal through the timelock.
   */
  function _execute(
    uint256, /* proposalId */
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override {
    _timelock.executeBatch{ value: msg.value }(targets, values, calldatas, 0, descriptionHash);
  }

  /**
   * @dev Overridden version of the {Governor-_cancel} function to cancel the timelocked proposal if it as already
   * been queued.
   */
  // This function can reenter through the external call to the timelock, but we assume the timelock is trusted and
  // well behaved (according to TimelockController) and this will not happen.
  // slither-disable-next-line reentrancy-no-eth
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override returns (uint256) {
    uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

    if (_timelockIds[proposalId] != 0) {
      _timelock.cancel(_timelockIds[proposalId]);
      delete _timelockIds[proposalId];
    }

    return proposalId;
  }

  /**
   * @dev Address through which the governor executes action. In this case, the timelock.
   */
  function _executor() internal view virtual override returns (address) {
    return address(_timelock);
  }

  // From the great Gonçalo Sá: https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
  function _slice(bytes memory _bytes, uint256 _start, uint256 _length)
    private
    pure
    returns (bytes memory)
  {
    require(_length + 31 >= _length, "slice_overflow");
    require(_bytes.length >= _start + _length, "slice_outOfBounds");

    bytes memory tempBytes;

    assembly {
      switch iszero(_length)
      case 0 {
        // Get a location of some free memory and store it in tempBytes as
        // Solidity does for memory variables.
        tempBytes := mload(0x40)

        // The first word of the slice result is potentially a partial
        // word read from the original array. To read it, we calculate
        // the length of that partial word and start copying that many
        // bytes into the array. The first word we copy will start with
        // data we don't care about, but the last `lengthmod` bytes will
        // land at the beginning of the contents of the new array. When
        // we're done copying, we overwrite the full first word with
        // the actual length of the slice.
        let lengthmod := and(_length, 31)

        // The multiplication in the next line is necessary
        // because when slicing multiples of 32 bytes (lengthmod == 0)
        // the following copy loop was copying the origin's length
        // and then ending prematurely not copying everything it should.
        let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
        let end := add(mc, _length)

        for {
          // The multiplication in the next line has the same exact purpose
          // as the one above.
          let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
        } lt(mc, end) {
          mc := add(mc, 0x20)
          cc := add(cc, 0x20)
        } { mstore(mc, mload(cc)) }

        mstore(tempBytes, _length)

        //update free-memory pointer
        //allocating the array padded to 32 bytes like the compiler does now
        mstore(0x40, and(add(mc, 31), not(31)))
      }
      //if we want a zero-length slice let's just return a zero-length array
      default {
        tempBytes := mload(0x40)
        //zero out the 32 bytes slice we are about to return
        //we need to do it because Solidity does not garbage collect
        mstore(tempBytes, 0)

        mstore(0x40, add(tempBytes, 0x20))
      }
    }

    return tempBytes;
  }
}

