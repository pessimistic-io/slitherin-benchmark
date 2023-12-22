// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {Ownable} from "./Ownable.sol";
import {IDuelPepes} from "./IDuelPepes.sol";

import {ECDSA} from "./ECDSA.sol";


/**
                                Duel Pepes Logic
                      On-chain duelling game between NFTs
*/

contract DuelPepesLogic is Ownable {
    using ECDSA for bytes32;

    // Main contract
    IDuelPepes public mainContract;
    // Maps move enum to it's attack and defence attributes
    // [0] - damage, [1] - guaranteed damage, [2] - defense
    mapping (uint => uint[3]) public moveAttributes;

    constructor() {
      moveAttributes[uint(IDuelPepes.Moves.Punch)] = [0, 1, 0];
      moveAttributes[uint(IDuelPepes.Moves.Kick)]  = [2, 0, 0];
      moveAttributes[uint(IDuelPepes.Moves.Block)] = [0, 0, 3];
      moveAttributes[uint(IDuelPepes.Moves.Special)] = [3, 0, 0];
    }

    /**
    * Validate a move set
    * @param moves 5 move set
    * @return Whether moves are valid
    */
    function validateMoves(
      uint[5] memory moves
    )
    public
    view
    returns (bool) {
      // Occurences of each move in terms of enum
      uint[4] memory occurences;
      for (uint i = 0; i < 5; i++) {
        require(moves[i] <= uint(IDuelPepes.Moves.Special), "Invalid move");
        if (moves[i] != uint(IDuelPepes.Moves.Special))
          require(occurences[moves[i]] + 1 <= 2, "Each move can only be performed twice");
        else
          require(occurences[moves[i]] + 1 <= 1, "Special moves can only be performed once");
        occurences[moves[i]] += 1;
      }
      return true;
    }

    /**
    * Decides the winner of a duel based on creator and challeger moves
    * @param id Duel id
    * @return creatorDamage Damage dealt to creator
    * @return challengerDamage Damage dealt to challenger
    */
    function decideDuel(
      uint id
    )
    public
    view
    returns (uint creatorDamage, uint challengerDamage) {
      uint creatorDamage;
      uint challengerDamage;
      IDuelPepes.Duel memory duel = mainContract.getDuel(id);

      for (uint i = 0; i < 5; i++) {
        uint creatorMove = duel.moves[0][i];
        uint challengerMove = duel.moves[1][i];
        // Damage
        creatorDamage += creatorMove == uint(IDuelPepes.Moves.Block) ? 0 : moveAttributes[challengerMove][0];
        challengerDamage += challengerMove == uint(IDuelPepes.Moves.Block) ? 0 : moveAttributes[creatorMove][0];

        // Guaranteed damage
        creatorDamage += challengerMove == uint(IDuelPepes.Moves.Punch) ? moveAttributes[challengerMove][1] : 0;
        challengerDamage += creatorMove == uint(IDuelPepes.Moves.Punch) ? moveAttributes[creatorMove][1] : 0;
      }

      return (creatorDamage, challengerDamage);
    }

    /**
    * Set trusted sender
    * @param newAddress Address of trusted sender
    */
    function setMainContract(address newAddress)
    onlyOwner
    public {
        mainContract = IDuelPepes(newAddress);
    }

    function verify(
      bytes32 data,
      bytes memory signature,
      address account
    ) public pure returns (bool) {
        return data.recover(signature) == account;
    }
}
