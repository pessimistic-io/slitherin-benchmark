// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./AccessControl.sol";
import "./Strings.sol";
import "./SafeMath.sol";
import "./IERC1155Receiver.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./ERC1155Tradable.sol";

/**
 * @title NftPack 
 * NftPack - a randomized and openable lootbox of Nfts
 */

contract NftPacks is Ownable, Pausable, AccessControl, ReentrancyGuard, VRFConsumerBaseV2, IERC1155Receiver {
  using Strings for string;
  using SafeMath for uint256;

  ERC1155Tradable public nftContract;

  // amount of items in each grouping/class
  mapping (uint256 => uint256) public Classes;
  bool[] public Option;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");

  uint256 constant INVERSE_BASIS_POINT = 10000;
  bool internal allowMint;

  // Chainlink VRF
  VRFCoordinatorV2Interface COORDINATOR;
  uint64 subscriptionId;
  bytes32 internal keyHash;
  address internal vrfCoordinator;
  uint32 internal callbackGasLimit = 1500000;
  uint16 requestConfirmations = 3;
  // uint256[] private _randomWords;
  uint256 private _randomness;
  uint256 private _seed;
  

  event PackOpenStarted(address indexed user, uint256 optionId, uint256 amount, uint256 requestId, uint256 timestamp);
  event PackOpened(uint256 indexed optionId, address indexed user, uint256 qty, uint256 nftsMinted, uint256[] nftIds);
  event PackOptionsSet(uint256 groupingId, uint256 optionId, uint32 maxPerOpen, bool hasGuaranteed, uint16[] probabilities, uint16[] guarantees ); 
  event ResetClass(uint256 groupingId, uint256 classId); 
  event ClassTokensSet(uint256 groupingId, uint256 classId, uint256[] nftIds);
  event SetNftContract(address indexed user, ERC1155Tradable nftContract);
  

  struct OptionSettings {
    // which group of classes this belongs to 
    uint256 groupingId;
    // Number of items to send per open.
    // Set to 0 to disable this Option.
    uint32 maxQuantityPerOpen;
    // Probability in basis points (out of 10,000) of receiving each class (descending)
    uint16[] classProbabilities; // NUM_CLASSES
    // Whether to enable `guarantees` below
    bool hasGuaranteedClasses;
    // Number of items you're guaranteed to get, for each class
    uint16[] guarantees; // NUM_CLASSES
  }

  /** 
   * @dev info on the current pack being opened 
   */
  struct PackQueueInfo {
    address userAddress; //user opening the pack
    uint256 optionId; //packId being opened
    uint256 amount; //amount of packs
  }

  uint256 private defaultNftId = 71;

  mapping (uint256 => OptionSettings) public optionToSettings;
  mapping (uint256 => mapping (uint256 => uint256[])) public classToTokenIds;

  // keep track of the times each token is minted, 
  // if internalMaxSupply is > 0 we use the internal data
  // if it is 0 we will use supply of the NFT contract instead
  mapping (uint256 => mapping (uint256 =>  mapping (uint256 => uint256)))  public internalMaxSupply;
  mapping (uint256 => mapping (uint256 =>  mapping (uint256 => uint256))) public internalTokensMinted;
  
  mapping (address => uint256[]) public lastOpen;
  mapping (address => uint256) public isOpening;
  mapping(uint256 => PackQueueInfo) private packQueue;


  constructor(
    ERC1155Tradable _nftAddress,
    address _vrfCoordinator,
    bytes32 _vrfKeyHash, 
    uint64 _subscriptionId
  ) VRFConsumerBaseV2(
    _vrfCoordinator
  ) {

    nftContract = _nftAddress;

    COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    subscriptionId = _subscriptionId;
    vrfCoordinator = _vrfCoordinator;
    keyHash = _vrfKeyHash;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);

  }

   /** 
     * @notice Modifier to only allow updates by the VRFCoordinator contract
     */
    modifier onlyVRFCoordinator {
        require(msg.sender == vrfCoordinator, 'Fulfillment only allowed by VRFCoordinator');
        _;
    }

    // modifier for functions only the team can call
    modifier onlyTeam() {
        require(hasRole(TEAM_ROLE,  msg.sender) || msg.sender == owner(), "Caller not in Team");
        _;
    }

  /**
   * @dev Add a Class Id
   */
   function setClassLength(uint256 _groupingId, uint256 _classLength) public onlyOwner {
      Classes[_groupingId] = _classLength;
   }


  /**
   * @dev If the tokens for some class are pre-minted and owned by the
   * contract owner, they can be used for a given class by setting them here
   */
  function setClassForTokenId(
    uint256 _groupingId,
    uint256 _classId,
    uint256 _tokenId,
    uint256 _amount
  ) public onlyOwner {
    _addTokenIdToClass(_groupingId, _classId, _tokenId, _amount);
  }

  /**
   * @dev bulk replace all tokens for a class
   */
  function setClassTokenIds(
    uint256 _groupingId,
    uint256 _classId,
    uint256[] calldata _tokenIds
  ) public onlyOwner {
    classToTokenIds[_groupingId][_classId] = _tokenIds;
    emit ClassTokensSet(_groupingId,_classId,_tokenIds);
  }

 
  /**
   * @dev Remove all token ids for a given class, causing it to fall back to
   * creating/minting into the nft address
   */
  function resetClass(
    uint256 _groupingId,
    uint256 _classId
  ) public onlyOwner {
    delete classToTokenIds[_groupingId][_classId];
    emit ResetClass(_groupingId,_classId);
  }

  /**
   * @param _groupingId The Grouping this Option is for
   * @param _optionId The Option to set settings for
   * @param _maxQuantityPerOpen Maximum number of items to mint per open.
   *                            Set to 0 to disable this pack.
   * @param _classProbabilities Array of probabilities (basis points, so integers out of 10,000)
   *                            of receiving each class (the index in the array).
   *                            Should add up to 10k and be descending in value.
   * @param _guarantees         Array of the number of guaranteed items received for each class
   *                            (the index in the array).
   */

  function setOptionSettings(
    uint256 _groupingId,
    uint256 _optionId,
    uint32 _maxQuantityPerOpen,
    uint16[] calldata _classProbabilities,
    uint16[] calldata _guarantees
  ) external onlyOwner {
    addOption(_optionId);
    // Allow us to skip guarantees and save gas at mint time
    // if there are no classes with guarantees
    bool hasGuaranteedClasses = false;
    for (uint256 i = 0; i < Classes[_groupingId]; i++) {
      if (_guarantees[i] > 0) {
        hasGuaranteedClasses = true;
      }
    }

    OptionSettings memory settings = OptionSettings({
      groupingId: _groupingId,
      maxQuantityPerOpen: _maxQuantityPerOpen,
      classProbabilities: _classProbabilities,
      hasGuaranteedClasses: hasGuaranteedClasses,
      guarantees: _guarantees
    });

    
    optionToSettings[_optionId] = settings;

    emit PackOptionsSet(_groupingId, _optionId, _maxQuantityPerOpen, hasGuaranteedClasses, _classProbabilities, _guarantees ); 
  }


  function getLastOpen(address _address) external view returns(uint256[] memory) {
    return lastOpen[_address];
  }

  function getIsOpening(address _address) external view returns(uint256) {
    return isOpening[_address];  
  }
  
  /**
   * @dev Add an option Id
   */
  function addOption(uint256 _optionId) internal onlyOwner{
    if(_optionId >= Option.length || _optionId == 0){
      Option.push(true);
    }
  }


  /**
   * @dev Open the NFT pack and send what's inside to _toAddress
   */

  
  function open(
    uint256 _optionId,
    address _toAddress,
    uint256 _amount
  ) external onlyRole(MINTER_ROLE) {
    _mint(_optionId, _toAddress, _amount, "");
  }


  /**
   * @dev Main minting logic for NftPacks
   */
  function _mint(
    uint256 _optionId,
    address _toAddress,
    uint256 _amount,
    bytes memory /* _data */
  ) internal whenNotPaused onlyRole(MINTER_ROLE) nonReentrant returns (uint256) {
    // Load settings for this box option
    
    OptionSettings memory settings = optionToSettings[_optionId];

    require(settings.maxQuantityPerOpen > 0, "NftPack#_mint: OPTION_NOT_ALLOWED");
    require(isOpening[_toAddress] == 0, "NftPack#_mint: OPEN_IN_PROGRESS");

   // require(LINK.balanceOf(address(this)) > linkFee, "Not enough LINK - fill contract with faucet");

    isOpening[_toAddress] = _optionId;
    uint256 _requestId = COORDINATOR.requestRandomWords(
      keyHash,
      subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      1
    );

    PackQueueInfo memory queue = PackQueueInfo({
      userAddress: _toAddress,
      optionId: _optionId,
      amount: _amount
    });
    
    packQueue[_requestId] = queue;
    
    emit PackOpenStarted(_toAddress, _optionId, _amount, _requestId, block.timestamp);
    
    return _requestId;
 
  }

  /**
   * @notice Callback function used by VRF Coordinator
  */
   function fulfillRandomWords(
    uint256 requestId,
    uint256[] memory randomWords
  ) internal override {

    // _randomWords = randomWords;
    _randomness = randomWords[0];
    
    PackQueueInfo memory _queueInfo = packQueue[requestId];
    doMint(_queueInfo.userAddress, _queueInfo.optionId, _queueInfo.amount);

  }

  function doMint(address _userAddress, uint256 _optionId, uint256 _amount) internal onlyVRFCoordinator {
    
    OptionSettings memory settings = optionToSettings[_optionId];
   
    isOpening[_userAddress] = 0;

    delete lastOpen[_userAddress];
    uint256 totalMinted = 0;
    // Iterate over the quantity of packs to open
    for (uint256 i = 0; i < _amount; i++) {
      // Iterate over the classes
      uint256 quantitySent = 0;
      if (settings.hasGuaranteedClasses) {
        // Process guaranteed token ids
        for (uint256 classId = 1; classId < settings.guarantees.length; classId++) {
            uint256 quantityOfGaranteed = settings.guarantees[classId];

            if(quantityOfGaranteed > 0) {
              lastOpen[_userAddress].push(_sendRandomNft(settings.groupingId, classId, _userAddress, quantityOfGaranteed));
              quantitySent += quantityOfGaranteed;    
            }
        }
      }

      // Process non-guaranteed ids
      while (quantitySent < settings.maxQuantityPerOpen) {
        uint256 quantityOfRandomized = 1;
        uint256 classId = _pickRandomClass(settings.classProbabilities);
        lastOpen[_userAddress].push(_sendRandomNft(settings.groupingId, classId, _userAddress, quantityOfRandomized));
        quantitySent += quantityOfRandomized;
      }
      totalMinted += quantitySent;
    }

    emit PackOpened(_optionId, _userAddress, _amount, totalMinted, lastOpen[_userAddress]);
  }

  function numOptions() external view returns (uint256) {
    return Option.length;
  }

  function numClasses(uint256 _groupingId) external view returns (uint256) {
    return Classes[_groupingId];
  }

  // Returns the tokenId sent to _toAddress
  function _sendRandomNft(
    uint256 _groupingId,
    uint256 _classId,
    address _toAddress,
    uint256 _amount
  ) internal returns (uint256) {
     // ERC1155Tradable nftContract = ERC1155Tradable(nftAddress);


    uint256 tokenId = _pickRandomNft(_groupingId, _classId);
      
      //super fullback to a set ID
      if(tokenId == 0){
        tokenId = defaultNftId;
      }

      if(nftContract.balanceOf(address(this),tokenId) > 0 ){
        nftContract.safeTransferFrom(address(this), _toAddress, tokenId, _amount, "0x0");
      } else {
        nftContract.mint(_toAddress, tokenId, _amount, "0x0");
      }
    

    return tokenId;
  }

  function _pickRandomClass(
    uint16[] memory _classProbabilities
  ) internal returns (uint256) {
    uint16 value = uint16(_random().mod(INVERSE_BASIS_POINT));
    // Start at top class (length - 1)
    for (uint256 i = _classProbabilities.length - 1; i > 0; i--) {
      uint16 probability = _classProbabilities[i];
      if (value < probability) {
        return i;
      } else {
        value = value - probability;
      }
    }
    return 1;
  }

  function _pickRandomNft(
    uint256 _groupingId,
    uint256 _classId
  ) internal returns (uint256) {

    uint256[] memory tokenIds = classToTokenIds[_groupingId][_classId];
    require(tokenIds.length > 0, "NftPack#_pickRandomNft: NO_TOKENS_ASSIGNED");
 
    uint256 randIndex = _random().mod(tokenIds.length);
    // ERC1155Tradable nftContract = ERC1155Tradable(nftAddress);

      for (uint256 i = randIndex; i < randIndex + tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i % tokenIds.length];

        // first check if we have a balance in the contract
        if(nftContract.balanceOf(address(this),tokenId)  > 0 ){
          return tokenId;
        }

        if(allowMint){
          uint256 curSupply;
          uint256 maxSupply;
          if(internalMaxSupply[_groupingId][_classId][tokenId] > 0){
            maxSupply = internalMaxSupply[_groupingId][_classId][tokenId];
            curSupply = internalTokensMinted[_groupingId][_classId][tokenId];
          } else {
            maxSupply = nftContract.tokenMaxSupply(tokenId);
            curSupply = nftContract.tokenSupply(tokenId);
          }

          uint256 newSupply = curSupply.add(1);
          if (newSupply <= maxSupply) {
            internalTokensMinted[_groupingId][_classId][tokenId] = internalTokensMinted[_groupingId][_classId][tokenId].add(1);
            return tokenId;
          }
        }


      }

      return 0;    
  }

  /**
   * @dev Take oracle return and generate a unique random number
   */
  function _random() internal returns (uint256) {
    uint256 randomNumber = uint256(keccak256(abi.encode(_randomness, _seed)));
    _seed += 1;
    return randomNumber;
  }

  function _addTokenIdToClass(uint256 _groupingId, uint256 _classId, uint256 _tokenId, uint256 _amount) internal {
    classToTokenIds[_groupingId][_classId].push(_tokenId);
    internalMaxSupply[_groupingId][_classId][_tokenId] = _amount;
  }

  /**
   * @dev set the nft contract address callable by owner only
   */
  function setNftContract(ERC1155Tradable _nftAddress) public onlyOwner {
      nftContract = _nftAddress;
      emit SetNftContract(msg.sender, _nftAddress);
  }

  function setDefaultNftId(uint256 _nftId) public onlyOwner {
      defaultNftId = _nftId;
  }
  
  function resetOpening(address _toAddress) public onlyTeam {
    isOpening[_toAddress] = 0;
  }

  function setAllowMint(bool _allowMint) public onlyOwner {
      allowMint = _allowMint;
  }


  // @dev transfer NFTs out of the contract to be able to move into packs on other chains or manage qty
  function transferNft(ERC1155Tradable _nftContract, uint256 _id, uint256 _amount) public onlyOwner {
      _nftContract.safeTransferFrom(address(this),address(owner()),_id, _amount, "0x00");
  }

  /**
   * @dev update the link fee amount
   */
  function setLinkGas(uint32 _callbackGasLimit) public onlyOwner {
      callbackGasLimit = _callbackGasLimit;
      // emit SetLinkFee(msg.sender, _linkFee);
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns(bytes4) {
      return 0xf23a6e61;
  }


  function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns(bytes4) {
      return 0xbc197c81;
  }

  function supportsInterface(bytes4 interfaceID) public view virtual override(AccessControl,IERC165) returns (bool) {
      return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
  }
}
