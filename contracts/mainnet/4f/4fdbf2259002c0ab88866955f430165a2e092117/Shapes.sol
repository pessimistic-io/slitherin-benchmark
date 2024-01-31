// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IERC721.sol";
import "./Base64.sol";
import "./Counters.sol";
import "./IShape.sol";

import {Utils} from "./Utils.sol";

contract Shapes is 
  Initializable, 
  ERC721Upgradeable, 
  ERC721EnumerableUpgradeable, 
  OwnableUpgradeable 
{

  // how it ends
  uint public constant FINAL_SUPPLY = 2048;

  // cant transfer to address zero
  address constant public BURN_ADDRESS = 0x0000000000000000000000000000000000000001;
  
  // used to parse seed/shape
  uint constant private SEED_RANGE = 10000000000;
  
  // some pre-parsed json elements
  string constant description = "Shapes 2048 by makio135 & clemsos";
  string constant jsonHeader = "data:application/json;base64,";

  // contructor arg
  uint public maxSupply;
  
  // timestamp in sec 
  uint public deadline;
  
  // store SVG contracts
  address[] public shapesAddresses;
  
  // index of the shape to use at mint
  uint public defaultShapeIndex;

  // address of SLASHES contract
  address public slashesAddress;

  // (tokenId => {index of SVG contract in shapesAddresses}000000{seed})
  mapping (uint => uint[]) public seeds;

  // (tokenId => timestamp)
  mapping (uint => uint) changeDeadline;

  // (tokenId => boolean)
  mapping (uint => bool) isLocked;

  // auto increment token ids
  using Counters for Counters.Counter;
  Counters.Counter private _nextTokenId;

  // auto increment seed
  using Counters for Counters.Counter;
  Counters.Counter private _nextSeed;

  // mint price
  uint public priceToMint;
  
  // price to change shape or seed
  uint public priceToUpdate;

  // one day in seconds
  uint interval;
  
  // 66 premint: 64 archival, 1 test, 1 stolen by a bot !
  // 1024 limit number of mint
  uint constant MAX_MINT = 958;
  
  // track number of mints
  uint public mints;

  // allowList utils
  mapping(address => uint8) public allowList;

  // emit some events
  event TokenChanged(uint tokenId, uint seed, uint shapeIndex);
  
  // errors
  error SoldOut();
  error SalesNotOpen();
  error CanNotChange();
  error InsufficientPrice();
  error WithdrawFailed(uint balance);
  error WrongNumber();
  error ZeroAddress();
  error Unauthorized();
  error Ended();
  error NoMintLeft();

  // modifiers
  function _salesIsOpen(uint numberOfMints) private view {
    if(totalSupply() == FINAL_SUPPLY) {
      revert SoldOut();
    }
    if(totalSupply() >= maxSupply) {
      revert SalesNotOpen();
    }
    if(mints + numberOfMints > MAX_MINT) {
      revert NoMintLeft();
    }
  }

  function _projectNotEnded() private view {
    if(block.timestamp > deadline) {
      revert Ended();
    }
  }

  function _canBeChanged(uint _tokenId) internal view {
    if(ownerOf(_tokenId) != msg.sender) {
      revert Unauthorized();
    }
    if(msg.value < priceToUpdate) { 
      revert InsufficientPrice(); 
    }
  }

  function initialize() public initializer {

      // initialize
      ERC721Upgradeable.__ERC721_init("SHAPES", "SHAPES");
      OwnableUpgradeable.__Ownable_init();

      // default to 31 Jan 2024 00:00:00 GMT
      deadline = 1706655600;

      // initially dont allow any supply
      maxSupply = 2048;

      // default settings
      priceToMint = 0.3 ether;
      priceToUpdate = 0.01 ether;
      interval = 60 * 60; // default to one hour

      // nextTokenId is initialized to 1, since starting at 0 leads to higher gas cost for the first minter
      _nextTokenId.increment();

      // seed follow tokenId pattern to avoid duplicates
      _nextSeed.increment();

  }

  function setAllowList(address[] calldata addresses) public onlyOwner {
    for (uint8 i = 0; i < addresses.length; i++) {
      allowList[addresses[i]] = allowList[addresses[i]] != 0 ? allowList[addresses[i]] : 1;
    }
  }

  // will remove only if not already minted
  function removeFromAllowlist(address[] calldata addresses) public onlyOwner {
    for (uint8 i = 0; i < addresses.length; i++) {
      if(allowList[addresses[i]] != 2) {
        allowList[addresses[i]] = 0;
      }
    }
  }

  /**
  * NFT functions 
  */
  function mint(
    address _recipient, 
    uint _shapeIndex
  ) payable public returns (uint256) {
    _salesIsOpen(1);
    _projectNotEnded();

    if(allowList[msg.sender] != 1 && msg.value < priceToMint) {
      revert InsufficientPrice();
    }
    
    uint tokenId = _mintShape(_recipient, _shapeIndex, 0);
    mints = mints + 1;

    if(allowList[msg.sender] == 1) {
      allowList[msg.sender] = 2;
    }
    return tokenId;
  }

  function _mintShape(
    address _recipient, 
    uint _shapeId,
    uint _seed // set to 0 to make seed random
    ) internal returns (uint currentTokenId) 
    {
    currentTokenId = _nextTokenId.current();
    uint parsedSeed; 
    
    if(_seed == 0) {
      // we skip the first 1024 to make sure we dont get identical slashes
      parsedSeed = _shapeId * SEED_RANGE + 1024 + _nextSeed.current();
      _nextSeed.increment();
    } else {
      // assign existing seed
      parsedSeed = _shapeId * SEED_RANGE + _seed;
    }

    // store seed
    seeds[currentTokenId].push(parsedSeed);

    // mint the token
    _safeMint(_recipient, currentTokenId);
    _nextTokenId.increment();
    return currentTokenId;
  }
  
  function totalSupply() public view override returns (uint256) {
    return _nextTokenId.current() - 1;
  }

  function _beforeTokenTransfer(
      address from,
      address to,
      uint256 tokenId
    ) internal
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable) 
    {
      super._beforeTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
      public
      view
      override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
      returns (bool)
    {
      return super.supportsInterface(interfaceId);
  }

  function contractURI() 
    public 
    view 
    returns (string memory) 
    {
      // generate random thumbnail
      IShape svg = IShape(shapesAddresses[0]);
      string memory svgString;
      string memory attributes;
      (svgString, attributes) = svg.generateSVG(block.timestamp % _nextTokenId.current());

      return string(
          abi.encodePacked(
              jsonHeader,
              Base64.encode(
                  bytes(
                      abi.encodePacked(
                        '{"name": "Shapes","description":"',
                        description,
                        '","image":"',
                        svgString,
                        '", "external_link": "https://makio135.com/shapes2048"}'
                        )
                  )
              )
          )
      );
  }

  function tokenURI(uint256 tokenId) 
    public 
    view 
    virtual 
    override (ERC721Upgradeable)
    returns (string memory) 
    {
      
      // doesnt revert even if the token doesnt exist
      if (tokenId > totalSupply()) return '{}';
      
      (string memory svgString, string memory attributes) = IShape(
        shapesAddresses[shape(tokenId)]
      ).generateSVG(
        seed(tokenId)
      );

      return string(
          abi.encodePacked(
              jsonHeader,
              Base64.encode(
                  bytes(
                      abi.encodePacked(
                        '{"description": "',
                        description,
                        '","name":"Shapes #',
                        Utils.uint2str(tokenId),
                        '","image":"',
                        svgString,
                        '","attributes":[{"trait_type":"countChanges","value":',
                        Utils.uint2str(seeds[tokenId].length),
                        '},',
                        attributes,
                        ']}'
                      )
                  )
              )
          )
      );
  }
  
  /**
   * Admin features
   */
  function setPriceToUpdate(uint _priceToUpdate) public onlyOwner {
    priceToUpdate = _priceToUpdate;
  }

  function withdraw(address payable recipient, uint256 amount) public onlyOwner {
      if(recipient == address(0)) {
        revert ZeroAddress();
      }

      uint balance = address(this).balance;
      if(balance == 0) { 
        revert WithdrawFailed(0); 
      }
      
      (bool succeed, ) = recipient.call{value: amount}("");
      if(!succeed) {
        revert WithdrawFailed(balance);
      }
  }

  // shapes address should be as follow: [ slashesV1, slashesV2, arcs... ]
  function setShapesAddresses(address[] calldata _shapesAddresses) public onlyOwner {
    shapesAddresses = _shapesAddresses;
  }

  function updateDeadline(uint _deadline) public onlyOwner {
    deadline = _deadline;
  }

  /**
   * Getters
   */
  function seed(uint _tokenId) public view returns (uint) {
    return seeds[_tokenId][seeds[_tokenId].length - 1] % SEED_RANGE;
  }
  
  function shape(uint _tokenId) public view returns (uint) {
    return seeds[_tokenId][seeds[_tokenId].length - 1] / SEED_RANGE;
  }

  function countChanges(uint _tokenId) public view returns (uint) {
    return seeds[_tokenId].length;
  }
  
  /**
   * User features
   */

  function changeToken(
    uint _tokenId, 
    uint _shapeIndex
  ) public payable {
    _canBeChanged(_tokenId);

    // we skip the first 1024 to make sure we dont get identical slashes
    uint newSeed = 1024 + _nextSeed.current();

    // make sure shape exists
    if(_shapeIndex > shapesAddresses.length - 1) {
      revert WrongNumber();
    }

    seeds[_tokenId].push(_shapeIndex * SEED_RANGE + newSeed);

    emit TokenChanged(_tokenId, newSeed, _shapeIndex);
    _nextSeed.increment();
  }

  function selectSeed(uint _tokenId, uint _seed) public {
    _projectNotEnded();
    
    if(ownerOf(_tokenId) != msg.sender) {
      revert Unauthorized();
    }

    bool seedFound;
    for (uint256 i = 0; i < seeds[_tokenId].length - 1; i++) {
      // if seed is found move all elements to the left, starting from the `index + 1`
      if(seedFound) {
        seeds[_tokenId][i] = seeds[_tokenId][i + 1];
      } else if(seeds[_tokenId][i] == _seed) {
        seedFound = true;
        seeds[_tokenId][i] = seeds[_tokenId][i + 1];
      } 
      
    }

    if(seedFound) {
      // set _seed as the last seed
      seeds[_tokenId][seeds[_tokenId].length - 1] = _seed;
      emit TokenChanged(_tokenId, _seed % SEED_RANGE, _seed / SEED_RANGE);
    }
  }

}
