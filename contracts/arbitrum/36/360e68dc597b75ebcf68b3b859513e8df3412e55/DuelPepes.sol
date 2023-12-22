// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {ECDSA} from "./ECDSA.sol";

import {IERC721} from "./IERC721.sol";
import {IERC20} from "./IERC20.sol";

import {Ownable} from "./Ownable.sol";

import {IDP2Mint} from "./IDP2Mint.sol";
import {IDuelPepesWhitelist} from "./IDuelPepesWhitelist.sol";
import {IDuelPepesLeaderboard} from "./IDuelPepesLeaderboard.sol";
import {IDuelPepesLogic} from "./IDuelPepesLogic.sol";
import {IWETH9} from "./IWETH9.sol";

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
      // Wager amount in WETH
      uint wager;
      // Fees at the time of duel creation
      uint fees;
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
      // Total lost to treasury
      uint lostToTreasury;
    }

    enum Moves {
      // Accurate [0, 1, 0]
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
    // Mint contract
    IDP2Mint public dp2;
    // Whitelist contract
    IDuelPepesWhitelist public whitelist;
    // Leaderboard contract
    IDuelPepesLeaderboard public leaderboard;
    // Logic contract
    IDuelPepesLogic public logic;
    // WETH contract
    IWETH9 public weth;
    // Map duel ID to duel
    mapping (uint => Duel) public duels;
    // Map unique identifier to duel ID
    mapping (bytes32 => uint) public duelIdentifiers;
    // # of duels
    uint public duelCount;
    // Percentage precision multiplier
    uint public percentagePrecision = 10 ** 4;
    // Fees in %
    uint public fees = 8000;
    // Time limit for a duel to be challenged
    uint public challengeTimelimit;
    // Time limit for duel moves to be revealed
    uint public revealTimeLimit;
    // Maps duellor addresses to duel IDs
    mapping (address => uint[]) public userDuels;

    event LogNewDuel(uint indexed id, address indexed creator);
    event LogChallengedDuel(uint indexed id, address indexed challenger, address indexed creator);
    event LogDecidedDuel(uint indexed id, address indexed creator, address indexed challenger, bool isCreatorWinner);

    constructor(address _logic, address _leaderboard, address _whitelist, address _feeCollector, address _dp2, address _weth, uint _challengeTimelimit, uint _revealTimeLimit) {
      require(_feeCollector != address(0), "Invalid fee collector address");
      logic = IDuelPepesLogic(_logic);
      leaderboard = IDuelPepesLeaderboard(_leaderboard);
      whitelist = IDuelPepesWhitelist(_whitelist);
      dp2 = IDP2Mint(_dp2);
      weth = IWETH9(_weth);
      feeCollector = _feeCollector;
      challengeTimelimit = _challengeTimelimit;
      revealTimeLimit = _revealTimeLimit;
    }

    /**
    * Verify creators move
    * @param id Duel ID
    * @param moves Initial 5 moves submitted for duel
    * @param salt Random salt
    */
    function checkMoves(
      uint id,
      uint[5] memory moves,
      bytes32 salt
    )
    external
    returns (bool) {
        bytes32 movesHash = keccak256(
        abi.encodePacked(
          duels[id].identifier,
          moves[0],
          moves[1],
          moves[2],
          moves[3],
          moves[4],
          salt
        )
      );

      bool atLeastOneBlock;

      for (uint i = 0; i < moves.length; i++) {
          if (moves[i] == 2) {
              atLeastOneBlock = true;
              break;
          }
      }

      require(atLeastOneBlock, "Block move is missing");

      bytes32 ethSigHash = keccak256(
        abi.encodePacked(
          "\x19Ethereum Signed Message:\n32",
          movesHash
        )
      );
      require(
        logic.verify(ethSigHash, duels[id].initialMovesSignature, duels[id].duellors[0]),
        "Moves don't match initial submitted moves"
      );

      return true;
    }

    /**
    * Retrieve a specific duel
    * @param _id identifier of the duel
    * @return Duel struct
    */
    function getDuel(uint _id)
    public
    view
    returns (Duel memory) {
        return duels[_id];
    }

    /**
    * Creates a new duel
    * @param identifier Unique identifier for duel
    * @param wager Amount to wager in WETH
    * @param movesSig Signature of moves set for duel
    * @return Whether duel was created
    */
    function createDuel(
      bytes32 identifier,
      uint wager,
      bytes memory movesSig
    )
    public
    payable
    returns (bool) {
      require(duelIdentifiers[identifier] == 0 && identifier != 0, "Invalid duel identifier");
      require(wager > 0, "Wager must be greater than 0");

      // Check if signature is ok
      if (movesSig.length != 65) {
        revert("invalid signature length");
      }

      uint8 v;

      assembly {
         v := byte(0, mload(add(movesSig, 0x60)))
      }

      if (v != 27 && v != 28) {
        revert("ECDSA: invalid signature 'v' value");
      }

      if (whitelist.isWhitelistActive()) require(whitelist.isWhitelisted(msg.sender), "Duellor not whitelisted");

      // Duel IDs are 1-indexed
      duels[++duelCount].identifier = identifier;
      duelIdentifiers[identifier] = duelCount;

      duels[duelCount].duellors[0] = msg.sender;
      duels[duelCount].wager = wager;
      duels[duelCount].fees = wager * fees / percentagePrecision;
      duels[duelCount].initialMovesSignature = movesSig;
      duels[duelCount].timestamps[0] = block.timestamp;

      if (msg.value > 0) {
          require(msg.value == wager, 'Not enough ETH');
          weth.deposit{value: wager}();
      } else {
          weth.transferFrom(msg.sender, address(this), wager);
      }

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

      weth.transfer(
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

      // Update user leaderboard position
      leaderboard.updateUserLeaderboard(
        id,
        false, // is draw
        0,
        1 // challenger damage
      );

      weth.transfer(
        duels[id].duellors[1],
        duels[id].wager * 2 - duels[id].fees
      );

      // Transfer fees to fee collector
      weth.transfer(
        feeCollector,
        duels[id].fees
      );

      return true;
    }

    /**
    * Challenges a duel
    * @param id Duel ID
    * @param moves 5 moves to submit for duel
    * @return Whether duel was created
    */
    function challenge(
      uint id,
      uint[5] memory moves
    )
    public
    payable
    returns (bool) {
      require(
        duels[id].duellors[0] != address(0) && duels[id].duellors[1] == address(0),
        "Invalid duel ID"
      );
      require(duels[id].duellors[0] != msg.sender, "Creator cannot duel themselves");
      require(logic.validateMoves(moves), "Invalid moves");
      require(
        block.timestamp <=
        duels[id].timestamps[0] + challengeTimelimit,
        "Challenge time limit passed"
      );

      if (whitelist.isWhitelistActive()) require(whitelist.isWhitelisted(msg.sender), "Duellor not whitelisted");

      bool atLeastOneBlock;

      for (uint i = 0; i < moves.length; i++) {
          if (moves[i] == 2) {
              atLeastOneBlock = true;
              break;
          }
      }

      require(atLeastOneBlock, "Block move is missing");

      duels[id].duellors[1] = msg.sender;
      duels[id].moves[1] = moves;
      duels[id].timestamps[1] = block.timestamp;

      if (msg.value > 0) {
          require(msg.value == duels[id].wager, 'Not enough ETH');
          weth.deposit{value: duels[id].wager}();
      } else {
          weth.transferFrom(msg.sender, address(this), duels[id].wager);
      }

      emit LogChallengedDuel(id, msg.sender, duels[id].duellors[0]);

      return true;
    }

    /**
    * Reveal initial moves for a duel
    * @param id Duel ID
    * @param moves Initial 5 moves submitted for duel
    */
    function revealDuel(
      uint id,
      uint[5] memory moves,
      bytes32 salt
    )
    public
    returns (bool) {
      require(
        block.timestamp <=
        duels[id].timestamps[1] + revealTimeLimit,
        "Reveal time limit passed"
      );
      require(
        duels[id].timestamps[2] == 0,
        "Duel outcome was already decided"
      );

      this.checkMoves(id, moves, salt);

      for (uint i = 0; i < 5; i++)
        duels[id].moves[0][i] = moves[i];

      // Decide outcome of the duel
      (uint creatorDamage, uint challengerDamage) = logic.decideDuel(
        id
      );

      // Save timestamp
      duels[id].timestamps[2] = block.timestamp;

      if (challengerDamage != creatorDamage) {
        // Save winner
        duels[id].isCreatorWinner = challengerDamage > creatorDamage;
        // Update user leaderboard position
        leaderboard.updateUserLeaderboard(
          id,
          false, // is draw
          creatorDamage,
          challengerDamage
        );

        // Set total loss and transfer funds to winner
        address winner = duels[id].duellors[1];
        address loser = duels[id].duellors[0];

        if (duels[id].isCreatorWinner) {
            winner = duels[id].duellors[0];
            loser = duels[id].duellors[1];
        }

        weth.transfer(
          winner,
          duels[id].wager * 2 - duels[id].fees
        );

        // Transfer fees to fee collector
        weth.transfer(
          feeCollector,
          duels[id].fees
        );
      } else {
        // Fees are 0
        duels[id].fees = 0;
        // Update user leaderboard position
        leaderboard.updateUserLeaderboard(
          id,
          true, // is draw
          creatorDamage,
          challengerDamage
        );
        // Return funds to creator
        weth.transfer(
          duels[id].duellors[0],
          duels[id].wager
        );
        // Return funds to challenger
        weth.transfer(
          duels[id].duellors[1],
          duels[id].wager
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
    * Returns timestamps for a duel
    * @param id Duel ID
    * @return Start and end timestamps for a duel
    */
    function getDuelTimestamps(uint id)
    public
    view
    returns(uint, uint, uint) {
      return (duels[id].timestamps[0], duels[id].timestamps[1], duels[id].timestamps[2]);
    }

    /**
    * Mint using credit
    */
    function mint()
    public {
      uint mintPrice = dp2.discountedMintPrice();
      uint credit = leaderboard.getCreditForMinting(msg.sender);
      uint numbers = credit / mintPrice;

      require(numbers > 0, "Invalid number");

      uint cost = numbers * mintPrice;

      require(credit >= cost, "Insufficient credit");

      leaderboard.charge(msg.sender, cost);

      weth.withdraw(cost);

      dp2.mint{value: cost}(numbers, msg.sender);
    }

    /**
    * Mint using credit and ETH
    */
    function mintMixed()
    public payable {
      uint mintPrice = dp2.mintPrice();

      uint charge = mintPrice - msg.value;

      uint credit = leaderboard.getCreditForMinting(msg.sender);

      require(credit >= charge, "Insufficient credit");

      leaderboard.charge(msg.sender, charge);

      weth.withdraw(charge);

      dp2.mint{value: charge + msg.value}(1, msg.sender);
    }

    /// @notice Withdraw
    function adminWithdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Withdraw token
    function adminWithdrawToken(address token, uint256 amount) public onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    /// @notice Execute arbitrary code
    function adminExecute(address target, bytes calldata data) public payable onlyOwner {
        target.call{value: msg.value}(data);
    }

    /// @notice Set trusted dp2
    function setTrustedDP2Mint(address newAddress) public onlyOwner {
        dp2 = IDP2Mint(newAddress);
    }

    fallback() external payable {}
}
