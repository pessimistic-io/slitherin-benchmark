// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "./FrontEndRewarder.sol";

import "./IKarsha.sol";
import "./IStaking.sol";
import "./ITreasury.sol";
import "./INoteKeeper.sol";

abstract contract NoteKeeper is INoteKeeper, FrontEndRewarder {

  mapping(address => Note[]) public notes; // user deposit data
  mapping(address => mapping(uint256 => address)) private noteTransfers; // change note ownership

  IKarsha internal immutable karsha;
  IStaking internal immutable staking;
  ITreasury internal treasury;

  constructor (
    IPanaAuthority _authority,
    IERC20 _pana,
    IKarsha _karsha,
    IStaking _staking,
    ITreasury _treasury
  ) FrontEndRewarder(_authority, _pana) {
    karsha = _karsha;
    staking = _staking;
    treasury = _treasury;
  }

  // if treasury address changes on authority, update it
  function updateTreasury() external {
    require(
      msg.sender == authority.governor() ||
      msg.sender == authority.guardian() ||
      msg.sender == authority.policy(),
      "Only authorized"
    );
    treasury = ITreasury(authority.vault());
  }

/* ========== ADD ========== */

  /**
   * @notice             adds a new Note for a user, stores the front end & DAO rewards, and mints & stakes payout & rewards
   * @param _user        the user that owns the Note
   * @param _payout      the amount of Pana due to the user
   * @param _expiry      the timestamp when the Note is redeemable
   * @param _marketID    the ID of the market deposited into
   * @return index_      the index of the Note in the user's array
   */
  function addNote(
    address _user, 
    uint256 _payout, 
    uint48 _expiry, 
    uint48 _marketID
  ) internal returns (uint256 index_) {
    // the index of the note is the next in the user's array
    index_ = notes[_user].length;

    // the new note is pushed to the user's array
    notes[_user].push(
      Note({
        payout: karsha.balanceTo(_payout),
        created: uint48(block.timestamp),
        matured: _expiry,
        redeemed: 0,
        marketID: _marketID
      })
    );
  }

/* ========== REDEEM ========== */

  /**
   * @notice             redeem notes for user
   * @param _user        the user to redeem for
   * @param _indexes     the note indexes to redeem
   * @return payout_     sum of payout sent, in Karsha
   */
  function redeem(address _user, uint256[] memory _indexes) public override returns (uint256 payout_) {
    uint48 time = uint48(block.timestamp);

    for (uint256 i = 0; i < _indexes.length; i++) {
      (uint256 pay, bool matured) = pendingFor(_user, _indexes[i]);

      if (matured) {
        notes[_user][_indexes[i]].redeemed = time; // mark as redeemed
        payout_ += pay;
      }
    }

    karsha.transfer(_user, payout_); // send payout as Karsha
  }

  /**
   * @notice             redeem all redeemable markets for user
   * @dev                if possible, query indexesFor() off-chain and input in redeem() to save gas
   * @param _user        user to redeem all notes for
   * @return             sum of payout sent, in Karsha
   */ 
  function redeemAll(address _user) external override returns (uint256) {
    return redeem(_user, indexesFor(_user));
  }

/* ========== TRANSFER ========== */

  /**
   * @notice             approve an address to transfer a note
   * @param _to          address to approve note transfer for
   * @param _index       index of note to approve transfer for
   */ 
  function pushNote(address _to, uint256 _index) external override {
    require(notes[msg.sender][_index].created != 0, "Depository: note not found");
    noteTransfers[msg.sender][_index] = _to;
  }

  /**
   * @notice             transfer a note that has been approved by an address
   * @param _from        the address that approved the note transfer
   * @param _index       the index of the note to transfer (in the sender's array)
   */ 
  function pullNote(address _from, uint256 _index) external override returns (uint256 newIndex_) {
    require(noteTransfers[_from][_index] == msg.sender, "Depository: transfer not found");
    require(notes[_from][_index].redeemed == 0, "Depository: note redeemed");

    newIndex_ = notes[msg.sender].length;
    notes[msg.sender].push(notes[_from][_index]);

    delete notes[_from][_index];
  }

/* ========== VIEW ========== */

  // Note info

  /**
   * @notice             all pending notes for user
   * @param _user        the user to query notes for
   * @return             the pending notes for the user
   */
  function indexesFor(address _user) public view override returns (uint256[] memory) {
    Note[] memory info = notes[_user];

    uint256 length;
    for (uint256 i = 0; i < info.length; i++) {
        if (info[i].redeemed == 0 && info[i].payout != 0) length++;
    }

    uint256[] memory indexes = new uint256[](length);
    uint256 position;

    for (uint256 i = 0; i < info.length; i++) {
        if (info[i].redeemed == 0 && info[i].payout != 0) {
            indexes[position] = i;
            position++;
        }
    }

    return indexes;
  }

  /**
   * @notice             calculate amount available for claim for a single note
   * @param _user        the user that the note belongs to
   * @param _index       the index of the note in the user's array
   * @return payout_     the payout due, in Karsha
   * @return matured_    if the payout can be redeemed
   */
  function pendingFor(address _user, uint256 _index) public view override returns (uint256 payout_, bool matured_) {
    Note memory note = notes[_user][_index];
    payout_ = note.payout;
    matured_ = note.redeemed == 0 && note.matured <= block.timestamp && note.payout != 0;
  }
}

