// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IBattleflyGame.sol";
import { MerkleProof } from "./MerkleProof.sol";
import "./ERC20.sol";

contract BattleflyPublicMint is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    mapping(address => bool) public HasMinted;

    bytes32 public merkleRootBattlefly;

    mapping(address => bool) private adminAccess;
    IBattleflyGame Game;
    uint256 public StartTime;
    uint256 public EndTime;
    uint256 public BattleflyType;
    uint256 public MinMagicAmountHolder;
    ERC20 MagicToken;
    mapping(bytes32 => bool) public HasMintedTicket;

    event PublicMintBattlefly(address indexed to, uint256 battleflyType, uint256 battleflyId, bytes32 indexed ticket);

    function initialize(address battleflyGameContractAddress, address magicTokenAddress) public initializer {
        __Ownable_init();
        Game = IBattleflyGame(battleflyGameContractAddress);
        MagicToken = ERC20(magicTokenAddress);
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    function setMerkleRootBattlefly(bytes32 merkleRoot) external onlyAdminAccess {
        merkleRootBattlefly = merkleRoot;
    }

    function setHasMinted(address user, bool value) external onlyAdminAccess {
        HasMinted[user] = value;
    }

    function setMinting(
        uint256 start,
        uint256 end,
        uint256 minMagicAmountHolder,
        uint256 battleflyType
    ) external onlyAdminAccess {
        StartTime = start;
        EndTime = end;
        MinMagicAmountHolder = minMagicAmountHolder;
        BattleflyType = battleflyType;
    }

    function mintBattlefly(bytes32 ticket, bytes32[] calldata proof) external {
        address to = _msgSender();
        require(block.timestamp >= StartTime, "Not start yet");
        require(block.timestamp <= EndTime, "Already finished");
        require(HasMinted[to] == false, "Already minted");
        require(HasMintedTicket[ticket] == false, "Already minted - ticket");

        if (MinMagicAmountHolder != 0)
            require(MagicToken.balanceOf(_msgSender()) >= MinMagicAmountHolder, "You must hold an amount of Magic");

        bytes32 leaf = keccak256(abi.encodePacked(ticket));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRootBattlefly, leaf);
        require(isValidLeaf, "Not in merkle");

        HasMinted[to] = true;
        HasMintedTicket[ticket] = true;
        uint256 battleflyId = Game.mintBattlefly(to, BattleflyType);

        emit PublicMintBattlefly(to, BattleflyType, battleflyId, ticket);
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

