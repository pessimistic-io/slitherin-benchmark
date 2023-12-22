// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ECDSA.sol";

import {IERC721} from "./IERC721.sol";
import {IERC20} from "./IERC20.sol";

import {Ownable} from "./Ownable.sol";

/**
                                Duel Pepes
                      On-chain duelling game between NFTs
*/

contract DuelPepes is Ownable {

    using ECDSA for bytes32;

    struct Duel {
      // unique identifier for duel (salt)
      bytes32 identifier;
      // 0 index = creator, 1 index = challenger
      address[2] duellors;
      // Wager amount in token
      uint wager;
      // Token to wager in
      address token;
      // Fees at the time of duel creation
      uint fees;
      // NFTs duelling. 
      // Collections = address of collection duelling
      // IDs = # id of nfts in collections
      // 0 index = creator, 1 index = challenger
      address[2] collections;
      uint[2] ids;
      // Initial hashed move set signature when creating duel
      bytes initialMovesSignature;
      // Moves selected by duel participants
      // 0 index = creator, 1 index = challenger
      uint[5][2] moves;
      // Who won the duel
      bool isCreatorWinner;
      // 0 index - Time created, 1 index - time challenged, 2 - time decided
      uint[3] timestamps;
    }

    struct LeaderboardPosition {
      // 0 - Total damage incurred, 1 - Total damage dealt
      uint[2] damage;
      // Total wins
      uint wins;
      // Total losses
      uint losses;
      // Total draws
      uint draws;
      // Total winnings from wagers
      uint winnings;
    }

    enum Moves {
      // Accurate [1, 1, 0]
      Punch,
      // Strength [2, 0, 0]
      Kick,
      // Defense [0, 0, 3]
      Block,
      // Special attack [3, 0, 0]
      Special
    }

    // Fee collector address
    address public feeCollector;
    // Map duel ID to duel
    mapping (uint => Duel) public duels;
    // Map unique identifier to duel ID
    mapping (bytes32 => uint) public duelIdentifiers;
    // Whitelisted collections
    mapping (address => bool) public whitelistedCollections;
    // # of duels 
    uint public duelCount;
    // Fees in %
    uint public fees;
    // Percentage precision multiplier
    uint public percentagePrecision = 10 ** 4;
    // Time limit for a duel to be challenged
    uint public challengeTimelimit = 12 hours;
    // Time limit for duel moves to be revealed
    uint public revealTimeLimit = 12 hours;
    // Maps duellor addresses to duel IDs
    mapping (address => uint[]) public userDuels;
    // Maps move enum to it's attack and defence attributes
    // [0] - damage, [1] - guaranteed damage, [2] - defense
    mapping (uint => uint[3]) public moveAttributes;
    // Leaderboard for NFTs
    // mapping (Collection => Id)
    mapping (address => mapping(uint => LeaderboardPosition)) public nftLeaderboard;
    // Leaderboard for users
    mapping (address => LeaderboardPosition) public userLeaderboard;

    event LogNewDuel(uint indexed id, address indexed creator);
    event LogChallengedDuel(uint indexed id, address indexed challenger, address indexed creator);
    event LogDecidedDuel(uint indexed id, address indexed creator, address indexed challenger, bool isCreatorWinner);
    event LogAddToWhitelist(address collection);

    constructor(address _feeCollector) {
      require(_feeCollector != address(0), "Invalid fee collector address");
      feeCollector = _feeCollector;
      moveAttributes[uint(Moves.Punch)] = [1, 1, 0];
      moveAttributes[uint(Moves.Kick)]  = [2, 0, 0];
      moveAttributes[uint(Moves.Block)] = [0, 0, 3];
      moveAttributes[uint(Moves.Special)] = [3, 0, 0];
    }

    /**
    * Adds a new collection to the whitelist
    * @param _collection Address of collection
    * @return Whether collection was added
    */
    function addToWhitelist(address _collection)
    public
    onlyOwner
    returns (bool) {
      require(_collection != address(0), "Invalid address");
      require(!whitelistedCollections[_collection], "Collection already whitelisted");

      whitelistedCollections[_collection] = true;

      emit LogAddToWhitelist(_collection);

      return true;
    }

    /**
    * Creates a new duel
    * @param identifier Unique identifier for duel
    * @param wager Amount to wager in `token`
    * @param token Token to wager in
    * @param collection Valid NFT collection to duel
    * @param nftId ID of NFT in `collection` to duel
    * @param movesSig Signature of moves set for duel
    * @return Whether duel was created
    */
    function createDuel(
      bytes32 identifier,
      uint wager,
      address token,
      address collection,
      uint nftId,
      bytes memory movesSig
    )
    public
    returns (bool) {
      require(duelIdentifiers[identifier] == 0 && identifier != 0, "Invalid duel identifier");
      require(wager > 0, "Wager must be greater than 0");
      require(token != address(0), "Invalid token");
      require(whitelistedCollections[collection], "Collection not whitelisted for duels");
      require(IERC721(collection).ownerOf(nftId) == msg.sender, "Sender does not own NFT");

      // Duel IDs are 1-indexed
      duels[++duelCount].identifier = identifier;
      duelIdentifiers[identifier] = duelCount;

      duels[duelCount].duellors[0] = msg.sender;
      duels[duelCount].wager = wager;
      duels[duelCount].token = token;
      duels[duelCount].fees = wager * 2 * fees / percentagePrecision;
      duels[duelCount].collections[0] = collection;
      duels[duelCount].ids[0] = nftId;
      duels[duelCount].initialMovesSignature = movesSig;
      duels[duelCount].timestamps[0] = block.timestamp;
      
      IERC20(token).transferFrom(msg.sender, address(this), wager);

      emit LogNewDuel(duelCount, msg.sender);

      return true;
    }

    /**
    * Recover funds from a non-matched duel
    * @param id Duel id
    */
    function undoDuel(
      uint id
    )
    public
    returns (bool) {
      require(
        block.timestamp >
        duels[id].timestamps[0] + revealTimeLimit,
        "Challenge time limit not passed"
      );
      require(
        duels[id].duellors[1] == address(0)
      );
      require(
        duels[id].timestamps[2] == 0,
        "Duel outcome was already decided"
      );

      // Save timestamp
      duels[id].timestamps[2] = block.timestamp;

      IERC20(duels[id].token).transfer(
        duels[id].duellors[0],
        duels[id].wager
      );

      return true;
    }

    /**
    * Claim funds when opponent does not reveal within the time window
    * @param id Duel id
    */
    function claimForfeit(
      uint id
    )
    public
    returns (bool) {
      require(
        block.timestamp >
        duels[id].timestamps[0] + revealTimeLimit,
        "Reveal time limit not passed"
      );

      require(
        duels[id].timestamps[2] == 0,
        "Duel outcome was already decided"
      );

      // Save timestamp
      duels[id].timestamps[2] = block.timestamp;

      // Save winner
      duels[id].isCreatorWinner = false;

      // Update NFT leaderboard position
      _updateNftLeaderboard(
        id,
        false, // is draw
        0,
        1 // challenger damage
      );

      // Update user leaderboard position
      _updateUserLeaderboard(
        id,
        false, // is draw
        0,
        1 // challenger damage
      );

      // Transfer funds to winner
      IERC20(duels[id].token).transfer(
        duels[id].duellors[1],
        duels[id].wager * 2 - duels[id].fees
      );

      return true;
    }

    /**
    * Challenges a duel
    * @param id Duel ID
    * @param collection Valid NFT collection to duel
    * @param nftId ID of NFT in `collection` to duel
    * @param moves 5 moves to submit for duel
    * @return Whether duel was created
    */
    function challenge(
      uint id,
      address collection,
      uint nftId,
      uint[5] memory moves
    )
    public
    returns (bool) {
      require(
        duels[id].duellors[0] != address(0) && duels[id].duellors[1] == address(0), 
        "Invalid duel ID"
      );
      require(duels[id].duellors[0] != msg.sender, "Creator cannot duel themselves");
      require(whitelistedCollections[collection], "Collection not whitelisted for duels");
      require(IERC721(collection).ownerOf(nftId) == msg.sender, "Sender does not own NFT");
      require(validateMoves(moves), "Invalid moves");
      require(
        block.timestamp <= 
        duels[id].timestamps[0] + challengeTimelimit, 
        "Challenge time limit passed"
      );

      duels[id].duellors[1] = msg.sender;
      duels[id].collections[1] = collection;
      duels[id].ids[1] = nftId;
      duels[id].moves[1] = moves;
      duels[id].timestamps[1] = block.timestamp;
      
      IERC20(duels[id].token).transferFrom(msg.sender, address(this), duels[id].wager);

      emit LogChallengedDuel(id, msg.sender, duels[id].duellors[0]);

      return true;
    }

    /**
    * Reveal initial moves for a duel. Receive a bonus for revealing in time if you lose.
    * @param id Duel ID
    * @param moves Initial 5 moves submitted for duel
    */
    function revealDuel(
      uint id,
      uint[5] memory moves
    )
    public
    returns (bool) {
      require(msg.sender == duels[id].duellors[0], "Invalid sender");
      require(
        block.timestamp <= 
        duels[id].timestamps[1] + revealTimeLimit, 
        "Reveal time limit passed"
      );
      require(
        duels[id].timestamps[2] == 0,
        "Duel outcome was already decided"
      );

      bytes32 movesHash = keccak256(
        abi.encodePacked(
          duels[id].identifier,
          moves[0],
          moves[1],
          moves[2],
          moves[3],
          moves[4]
        )
      );
      bytes32 ethSigHash = keccak256(
        abi.encodePacked(
          "\x19Ethereum Signed Message:\n32", 
          movesHash
        )
      );
      require(
        verify(ethSigHash, duels[id].initialMovesSignature, msg.sender), 
        "Moves don't match initial submitted moves"
      );

      // Save creator moves
      for (uint i = 0; i < 5; i++)
        duels[id].moves[0][i] = moves[i];

      // Decide outcome of the duel
      (uint creatorDamage, uint challengerDamage) = decideDuel(
        id
      );

      // Save timestamp
      duels[id].timestamps[2] = block.timestamp;

      if (challengerDamage != creatorDamage) {
        // Save winner
        duels[id].isCreatorWinner = challengerDamage > creatorDamage;
        // Update NFT leaderboard position
        _updateNftLeaderboard(
          id,
          false, // is draw
          creatorDamage,
          challengerDamage
        );
        // Update user leaderboard position
        _updateUserLeaderboard(
          id,
          false, // is draw
          creatorDamage,
          challengerDamage
        );

        // Transfer funds to winner
        IERC20(duels[id].token).transfer(
          duels[id].duellors[duels[id].isCreatorWinner ? 0 : 1],
          duels[id].wager * 2 - duels[id].fees
        );

        uint256 revealTimeRemaining = duels[id].timestamps[1] + revealTimeLimit - block.timestamp;

        // max 20% bonus linear decreasing if you lose but reveal immediately
        uint256 bonus;

        if (duels[id].isCreatorWinner) {
           bonus = 0;
        } else {
           bonus = (duels[id].fees * 20 / 100) * revealTimeRemaining / revealTimeLimit;

           // Transfer bonus to revealer
           IERC20(duels[id].token).transfer(
             duels[id].duellors[0],
             bonus
           );
        }

        // Transfer fees to fee collector
        IERC20(duels[id].token).transfer(
          feeCollector,
          duels[id].fees - bonus
        );
      } else {
        // Update NFT leaderboard
        _updateNftLeaderboard(
          id,
          true, // is draw
          creatorDamage,
          challengerDamage
        );
        // Update user leaderboard position
        _updateUserLeaderboard(
          id,
          false, // is draw
          creatorDamage,
          challengerDamage
        );
        // Return funds to creator (minus fees)
        IERC20(duels[id].token).transfer(
          duels[id].duellors[0],
          duels[id].wager - (duels[id].fees/2)
        );
        // Return funds to challenger (minus fees)
        IERC20(duels[id].token).transfer(
          duels[id].duellors[1],
          duels[id].wager - (duels[id].fees/2)
        );
        // Transfer fees to fee collector
        IERC20(duels[id].token).transfer(
          feeCollector,
          duels[id].fees
        );
      }

      emit LogDecidedDuel(
        id, 
        duels[id].duellors[0], 
        duels[id].duellors[1], 
        duels[id].isCreatorWinner
      );

      return true;
    }

    /**
    * Updates leaderboard position for NFTs involved in a decided duel
    * @param id Duel ID
    * @param isDraw Whether the duel was a draw
    * @param creatorDamage Damaged dealt to creator
    * @param challengerDamage Damaged dealt to challenger
    */
    function _updateNftLeaderboard(
      uint id,
      bool isDraw,
      uint creatorDamage,
      uint challengerDamage
    ) internal {
        // Add to NFT leaderboard position
        // Damage incurred by creator
        nftLeaderboard
          [duels[id].collections[0]]
          [duels[id].ids[0]].damage[0] = creatorDamage;
        // Damage incurred by challenger
        nftLeaderboard
          [duels[id].collections[1]]
          [duels[id].ids[1]].damage[0] = challengerDamage;
        // Damage dealt by creator
        nftLeaderboard
          [duels[id].collections[0]]
          [duels[id].ids[0]].damage[1] = challengerDamage;
        // Damage dealt by challenger
        nftLeaderboard
          [duels[id].collections[1]]
          [duels[id].ids[1]].damage[1] = creatorDamage;
        if (!isDraw) {
          uint winner = duels[id].isCreatorWinner ? 0 : 1;
          uint loser = duels[id].isCreatorWinner ? 1 : 0;
          // Add to stats
          nftLeaderboard
            [duels[id].collections[winner]]
            [duels[id].ids[winner]].wins += 1;
          nftLeaderboard
            [duels[id].collections[loser]]
            [duels[id].ids[loser]].losses += 1;
          nftLeaderboard
            [duels[id].collections[winner]]
            [duels[id].ids[winner]].winnings += duels[id].wager * 2 - duels[id].fees;
        } else {
          nftLeaderboard
            [duels[id].collections[0]]
            [duels[id].ids[0]].draws += 1;
          nftLeaderboard
            [duels[id].collections[1]]
            [duels[id].ids[1]].draws += 1;
        }
    }

    /**
    * Updates leaderboard position for users involved in a decided duel
    * @param id Duel ID
    * @param isDraw Whether the duel was a draw
    * @param creatorDamage Damaged dealt to creator
    * @param challengerDamage Damaged dealt to challenger
    */
    function _updateUserLeaderboard(
      uint id,
      bool isDraw,
      uint creatorDamage,
      uint challengerDamage
    ) internal {
        // Add to NFT leaderboard position
        // Damage incurred by creator
        userLeaderboard
          [duels[id].duellors[0]].damage[0] = creatorDamage;
        // Damage incurred by challenger
        userLeaderboard
          [duels[id].duellors[1]].damage[0] = challengerDamage;
        // Damage dealt by creator
        userLeaderboard
          [duels[id].duellors[0]].damage[1] = challengerDamage;
        // Damage dealt by challenger
        userLeaderboard
          [duels[id].duellors[1]].damage[1] = creatorDamage;
        if (!isDraw) {
          uint winner = duels[id].isCreatorWinner ? 0 : 1;
          uint loser = duels[id].isCreatorWinner ? 1 : 0;
          // Add to stats
          userLeaderboard
            [duels[id].duellors[winner]].wins += 1;
          userLeaderboard
            [duels[id].duellors[loser]].losses += 1;
          userLeaderboard
            [duels[id].duellors[winner]].winnings += duels[id].wager * 2 - duels[id].fees;
        } else {
          userLeaderboard
            [duels[id].duellors[0]].draws += 1;
          userLeaderboard
            [duels[id].duellors[1]].draws += 1;
        }
    }

    function verify(
      bytes32 data, 
      bytes memory signature, 
      address account
    ) public pure returns (bool) {
        return data.recover(signature) == account;
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
        require(moves[i] <= uint(Moves.Special), "Invalid move");
        if (moves[i] != uint(Moves.Special))
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

      for (uint i = 0; i < 5; i++) {
        uint creatorMove = duels[id].moves[0][i];
        uint challengerMove = duels[id].moves[1][i];
        // Damage
        creatorDamage += creatorMove == uint(Moves.Block) ? 0 : moveAttributes[challengerMove][0];
        challengerDamage += challengerMove == uint(Moves.Block) ? 0 : moveAttributes[creatorMove][0];

        // Guaranteed damage
        creatorDamage += challengerMove == uint(Moves.Punch) ? moveAttributes[challengerMove][1] : 0;
        challengerDamage += creatorMove == uint(Moves.Punch) ? moveAttributes[creatorMove][1] : 0;
      }

      return (creatorDamage, challengerDamage);
    }
}
