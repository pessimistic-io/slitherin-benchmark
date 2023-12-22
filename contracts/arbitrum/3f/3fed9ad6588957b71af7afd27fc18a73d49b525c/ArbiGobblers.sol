pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC721.sol";
import "./LogisticVRGDA.sol";
import "./IASTRO.sol";
import "./ISpaceShip.sol";
import "./IRandomizer.sol";
import "./IArbiGobblers.sol";
import "./ITraits.sol";
import "./PaymentSplitter.sol";
import {toWadUnsafe, toDaysWadUnsafe} from "./SignedWadMath.sol";

contract ArbiGobblers is ERC721, IArbiGobblers, LogisticVRGDA, Ownable, Pausable, PaymentSplitter {

  /// GAME VARIABLES 

  /// @notice max number of tokens that can be minted - 10k in prod.
  uint256 public immutable MAX_TOKEN = 10000;
  /// @notice max number of tokens that can be minted from $ASTRO.
  uint256 public MAX_MINTABLE = 5000;
  /// @notice max number of tokens that can be claimed from airdrop.
  uint256 public immutable MAX_AIRDROP = 1800;
  /// @notice max number of tokens that can be minted from dutch auction.
  uint256 public immutable MAX_MINT_DA = 3000;

  /// @notice number of tokens that have been minted.
  uint256 public MINTED;
  /// @notice number of tokens that have been minted in dutch auction.
  uint256 public MINTED_DA;
  /// @notice number of tokens that have been minted in $ASTRO.
  uint256 public MINTED_ASTRO;

  bool public gameOpen = false;
  bool public dutchAuctionOpen = false;
  bool public whitelistMintOpen = false;
  bool public freemintOpen = false;
  /// @notice block timestamp when mint begins.
  uint256 public mintStart;

  /// @notice num of human minted since start.
  uint256 public numHumanMinted;
  /// @notice num of ArbiGobbler minted since start.
  uint256 public numArbiGobblerMinted;
  /// @notice num of human stolen since start.
  uint256 public numHumanStolen;
  /// @notice num of ArbiGobbler stolen since start.
  uint256 public numArbiGobblerStolen;
  /// @notice Number of ArbiGobblers minted from astro.
  uint256 public numMintedFromAstro;
  /// checkpoint if reserver ArbiGobblers has been claimed already.
  bool public reservedArbiGobblersClaimed = false;
  
  /// Dutch Auction variables
  uint private constant DURATION = 2 days;
  uint public  startingPrice;
  uint public  discountRate;
  uint public  startAt;
  uint public  expiresAt;

  bool private _reentrant = false;

  /// MAPPINGS

  /// return the ticket id for a user to get his random number to prepare a free claim.
  mapping(address => uint256) public userRandTicketClaim;
    /// return the ticket id for a user to get his random number to prepare a dutch auction mint.
  mapping(address => uint256) public userRandTicketDA;
    /// return the ticket id for a user to get his random number to prepare an $ASTRO mint.
  mapping(address => uint256) public userRandTicketAstro;
    /// return the ticket id for a user to get his random number to prepare a mint from reserve.
  mapping(address => uint256) public userRandTicketReserve;

  /// return true if address prepared a Dutch Auction mint.
  mapping(address => bool) public userDAPass;
  /// return true if address prepared an airdrop claim.
  mapping(address => bool) public userClaimPass;
  /// return true if address prepared an Astro mint.
  mapping(address => bool) public userAstroPass;
  /// return true if address is whitelisted
  mapping(address => bool) public isWhitelisted;
  /// return how many mint have been claimed for free by the address owner.
  mapping(address=> uint) public claimedForFree;

  // Token ids => Class ID unique ID for Humans.
  mapping(uint256 => uint256) private humanIds;
  // Token ids => Class ID unique ID for ArbiGobblers.
  mapping(uint256 => uint256) private arbiGobblerIds;
  /// Gen of the Token ID
  mapping(uint256 => uint8) public gen;
  // mapping from tokenId to a struct containing the token's traits.
  mapping(uint256 => HumanArbiGobblers) private tokenTraits;

  /// Interfaces

  IASTRO private astroToken;
  ISpaceShip public spaceShip;
  ITraits public traits;
  IRandomizer public randomizer;

  /// EVENTS 

  event ClaimAirdropPrepared();
  event MintFromDAPrepared();
  event MintFromAstroPrepared();

  event ArbiGobblerAirdroped(uint256 tokenId, address who);
  event ArbiGobblerDAMinted(uint256 tokenId, address who);

  event ArbiGobblerMinted(uint256 tokenId, address who);
  event HumanStolen(uint256 tokenId);
  event ArbiGobblerStolen(uint256 tokenId);

  event MintReservedArbiGobblersPrepared();
  event ArbiGobblerReservedMinted();

  constructor(
    IASTRO _astroToken,
    ITraits _traits,
    IRandomizer _randomizer,
    address[] memory payees,
    uint256[] memory shares
  )
  PaymentSplitter(
    payees, 
    shares
  )

  ERC721("Arbi Gobblers", "ARBIGOBBLERS")
  LogisticVRGDA(
    69.42e18, // Target price.
    0.31e18, // Price decay percent.
    // Max gobblers mintable via VRGDA.
    toWadUnsafe(MAX_MINTABLE), // To define 
    0.0023e18 // Time scale.
  ) 
  {
    astroToken = _astroToken;
    traits = _traits;
    randomizer = _randomizer;
  }
    
  /*** MINT LOGIC ***/

  /**  PREPARE FUNCTIONS **/

  function prepareClaimAirdrop() external whenNotPaused onlyEOA {
    require(userRandTicketClaim[msg.sender] == 0, "Must use ticket first");

    require(MINTED < MAX_AIRDROP, "GEN0 is closed");
    // If minting has not yet begun, revert.
    require(whitelistMintOpen, "Mint start pending");
    if (!freemintOpen) {
      require(isWhitelisted[msg.sender], "Not whitelisted!");
    }
    // If the user has already claimed, revert.
    require(claimedForFree[msg.sender] < 4, "Already claimed all");

    userRandTicketClaim[msg.sender] = randomizer.requestRandomNumber();
    userClaimPass[msg.sender] = true;

    emit ClaimAirdropPrepared();
  }

  function prepareMintFromDA() payable external whenNotPaused onlyEOA {
    require(userRandTicketDA[msg.sender] == 0, "Must use ticket first");

    require(MINTED_DA < MAX_MINT_DA, "Dutch Auction sold out");
    require(dutchAuctionOpen, "The auction is now closed");
    require(block.timestamp < expiresAt, "The auction has ended");

    uint price = getPriceDA();
    require(msg.value >= price, "Not enough ETH");

    // Restarting the DA 
    startAt = block.timestamp;

    // Requesting random number
    userRandTicketDA[msg.sender] = randomizer.requestRandomNumber();
    userDAPass[msg.sender] = true;

    emit MintFromDAPrepared();
  }

  function prepareMintAstro() external whenNotPaused onlyEOA {
    require(userRandTicketAstro[msg.sender] == 0, "Must use ticket first");

    require(gameOpen, "Game is closed");
    // if amount of token minted is equal to max supply, revert.
    require(MINTED < MAX_TOKEN, "Sold out max supply reached");
    require(MINTED_ASTRO < MAX_MINTABLE, "Sold out max mintable from $ASTRO reached");

    uint256 currentPrice = ArbiGobblerPrice();
    astroToken.burnForArbiGobbler(msg.sender, currentPrice);
    
    userRandTicketAstro[msg.sender] = randomizer.requestRandomNumber();
    userAstroPass[msg.sender] = true;

    emit MintFromAstroPrepared();
  }

  //** MINT FUNCTIONS **/

  function claimAirdrop() external whenNotPaused onlyEOA {
    require(whitelistMintOpen, "Mint start pending");

    if (!freemintOpen) {
      require(isWhitelisted[msg.sender], "Not whitelisted!");
    }

    require(userClaimPass[msg.sender], "You need to prepare your mint!");
    // If minting has not yet begun, revert.
    // If the user has already claimed, revert.
    require(claimedForFree[msg.sender] < 4, "Already claimed all");

    require(userRandTicketClaim[msg.sender] != 0, "User has no tickets to open.");
    require(randomizer.isRandomReady(userRandTicketClaim[msg.sender]), "Random not ready, try again.");

    uint256 rand = randomizer.revealRandomNumber(userRandTicketClaim[msg.sender]);
    uint256 random = uint256(keccak256(abi.encode(rand, 0))) % 1000;
    uint256 tokenId = MINTED+1;

    generate(tokenId, random);

    if (tokenTraits[tokenId].isHuman) {
      numHumanMinted++;
      humanIds[tokenId] = numHumanMinted;
    } else {
      numArbiGobblerMinted++;
      arbiGobblerIds[tokenId] = numArbiGobblerMinted;

    } 

    claimedForFree[msg.sender]++;

    MINTED++;

    userRandTicketClaim[msg.sender] = 0;
    userClaimPass[msg.sender] = false;
    gen[tokenId] = 0;

    _safeMint(msg.sender, tokenId);

    emit ArbiGobblerAirdroped(tokenId, msg.sender);
  }

  function mintFromDA() external whenNotPaused onlyEOA {
    require(userDAPass[msg.sender], "You need to prepare your mint!");
    require(userRandTicketDA[msg.sender] != 0, "No random tickets.");
    require(randomizer.isRandomReady(userRandTicketDA[msg.sender]), "Random not ready, try again.");
    
    uint256 rand = randomizer.revealRandomNumber(userRandTicketDA[msg.sender]);
    uint256 random = uint256(keccak256(abi.encode(rand, 0))) % 1000;
    uint256 tokenId = MINTED+1;

    generate(tokenId, random);

    if (tokenTraits[tokenId].isHuman) {
      numHumanMinted++;
      humanIds[tokenId] = numHumanMinted;
    } else {
      numArbiGobblerMinted++;
      arbiGobblerIds[tokenId] = numArbiGobblerMinted;
    } 

    MINTED++;
    MINTED_DA++;

    userRandTicketDA[msg.sender] = 0;
    userDAPass[msg.sender] = false; 
    gen[tokenId] = 1;

    _safeMint(msg.sender, tokenId);

    emit ArbiGobblerDAMinted(tokenId, msg.sender);
  }

  function mintFromAstro() external whenNotPaused onlyEOA {
    require(userAstroPass[msg.sender], "You need to prepare your mint!");
    require(userRandTicketAstro[msg.sender] != 0, "User has no tickets to open.");
    require(gameOpen, "Game is closed");
    require(randomizer.isRandomReady(userRandTicketAstro[msg.sender]), "Random not ready, try again.");

    uint256 rand = randomizer.revealRandomNumber(userRandTicketAstro[msg.sender]);
    uint256 random = uint256(keccak256(abi.encode(rand, 0))) % 1000;
    uint256 tokenId = MINTED+1;

    generate(tokenId, random);

    address recipient = selectRecipient(random);
    if (tokenTraits[tokenId].isHuman) {
      numHumanMinted++;
      humanIds[tokenId] = numHumanMinted;
      if (recipient != msg.sender) {
        emit HumanStolen(tokenId);
        numHumanStolen++;
      }
    } else {
      numArbiGobblerMinted++;
      arbiGobblerIds[tokenId] = numArbiGobblerMinted;

      if (recipient != msg.sender) {
        emit ArbiGobblerStolen(tokenId);
        numArbiGobblerStolen++;
      }
    }

    numMintedFromAstro++;
    MINTED++;
    MINTED_ASTRO++;
    userRandTicketAstro[msg.sender] = 0;
    userAstroPass[msg.sender] = false;
    gen[tokenId] = 2;

    _safeMint(recipient, tokenId);

    emit ArbiGobblerMinted(tokenId, recipient);
  }
  
  function prepareMintReservedArbiGobblers() external onlyOwner {
    require(userRandTicketReserve[msg.sender] == 0, "Must use ticket first");
    require(MINTED < MAX_TOKEN, "Sold out");
    require (reservedArbiGobblersClaimed == false, "Reserved ArbiGobbler Already Claimed");

    userRandTicketReserve[msg.sender] = randomizer.requestRandomNumber();

    emit MintReservedArbiGobblersPrepared();
  }

  function mintReservedArbiGobblers(uint256 numArbiGobblers, address to) external onlyOwner {
    require (reservedArbiGobblersClaimed == false, "Reserved ArbiGobbler Already Claimed");
    require(userRandTicketReserve[msg.sender] != 0, "User has no tickets to open.");

    require(randomizer.isRandomReady(userRandTicketReserve[msg.sender]), "Random not ready, try again.");

    uint256 rand = randomizer.revealRandomNumber(userRandTicketReserve[msg.sender]);
    uint256 random = uint256(keccak256(abi.encode(rand, 0))) % 1000;
    uint256 tokenId;

    for (uint i; i<numArbiGobblers;i++){
      tokenId = MINTED+1;

      uint256 newrand = random * tokenId;

      MINTED++;

      generate(tokenId, newrand);
      userRandTicketReserve[msg.sender] = 0;
      
      if (tokenTraits[tokenId].isHuman) {
        numHumanMinted++;
        humanIds[tokenId] = numHumanMinted;
      } else {
        numArbiGobblerMinted++;
        arbiGobblerIds[tokenId] = numArbiGobblerMinted;
      } 

      // TO DO mint separatly on each addresses 
      _safeMint(to, tokenId);
      
    }
    reservedArbiGobblersClaimed = true;

    emit ArbiGobblerReservedMinted();
  }

  /*** INTERNAL ***/
  
  function generate(uint256 tokenId, uint256 random) internal returns (HumanArbiGobblers memory t) {
    t = selectTraits(random);
    tokenTraits[tokenId] = t;

    return t;
  }
  
  function selectTrait(uint16 random) internal view returns (uint8) {
    return traits.selectLevel(random);
  }
  
  function selectRecipient(uint256 random) internal view returns (address) {
    if (((random >> 245) % 10) != 0) return msg.sender;

    address human = spaceShip.randomAlienOwner(random >> 144);
    if (human == address(0x0)) return msg.sender;

    return human;
  }
  
  function selectTraits(uint256 random) internal view returns (HumanArbiGobblers memory t) {
    t.isHuman = (random & 0xFFFF) % 10 != 0;
    if (t.isHuman) {
      t.levelIndex = traits.selectLevel(uint16(random & 0xFFFF));
    }
  }
  
  /*** READ ***/
  function getGen(uint256 tokenId) external view returns(uint8){
    return gen[tokenId];
  }
  function getClassId(uint256 tokenId) external view override returns(uint256){
    if (tokenTraits[tokenId].isHuman) {
      return humanIds[tokenId];
    } else {
      return arbiGobblerIds[tokenId];
    }
  }

  function getTokenTraits(uint256 tokenId) external view override returns (HumanArbiGobblers memory) {
    return tokenTraits[tokenId];
  }
  
  /// @notice ArbiGobbler pricing in terms of goo.
  /// @dev Will revert if called before minting starts
  /// or after all ArbiGobblers have been minted via VRGDA.
  /// @return Current price of a ArbiGobbler in terms of goo.
  function ArbiGobblerPrice() public view returns (uint256) {
    // We need checked math here to cause underflow
    // before minting has begun, preventing mints.
    uint256 timeSinceStart = block.timestamp - mintStart;

    return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), numMintedFromAstro);
  }

  function getPriceDA() public view returns (uint) {
    uint timeElapsed = block.timestamp - startAt;
    uint discount = discountRate * timeElapsed;
    if(startingPrice - discount < startingPrice / 2){
      return startingPrice / 2;
    }
    return startingPrice - discount;
  }
  
  /*** ADMIN ***/
  
  function startDutchAuction(uint _startingPrice, uint _discountRate) external onlyOwner {
    startingPrice = _startingPrice; // Price in gwei
    discountRate = _discountRate;
    startAt = block.timestamp;
    expiresAt = block.timestamp + DURATION;
    dutchAuctionOpen = true;
  }

  function setSpaceShip(address _spaceShip) external onlyOwner {
    spaceShip = ISpaceShip(_spaceShip);
  }
  
  function setWhitelist(address[] memory _whitelist) external onlyOwner {
    for (uint256 i = 0; i < _whitelist.length; i++) {
      isWhitelisted[_whitelist[i]] = true;
    }
  }

  function setMintStart(uint256 _mintStart) external onlyOwner{
    mintStart = _mintStart;
  }

  function setDutchAuctionOpen(bool val) external onlyOwner {
    dutchAuctionOpen = val;
  }
  
  function setWhitelistOpen(bool val) external onlyOwner {
    whitelistMintOpen = val;
  }

  function setFreeMintOpen(bool val) external onlyOwner {
    freemintOpen = val;
  }

  function setOpenGame(bool val) external onlyOwner {
    gameOpen = val;
  }
  
  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }
  
  function transferFrom(
      address from,
      address to,
      uint256 tokenId
  ) public virtual override nonReentrant {
    // Hardcode the Ship's approval so that users don't have to waste gas approving
    if (msg.sender != address(spaceShip))
    require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
    _transfer(from, to, tokenId);
  }
  
  /*** RENDER ***/
  
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
    return traits.tokenURI(tokenId);
  }

  /*** MODIFIERS ***/

  modifier onlyEOA() {
    require(tx.origin == _msgSender(), "Only EOA");
    _;
  }

  modifier nonReentrant() {
    require(!_reentrant, "No reentrancy");
    _reentrant = true;
    _;
    _reentrant = false;
  }
}

