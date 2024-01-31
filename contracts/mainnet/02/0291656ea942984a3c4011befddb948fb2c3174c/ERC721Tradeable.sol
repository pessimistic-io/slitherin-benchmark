// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./SafeMath.sol";

import "./ContentMixin.sol";
import "./NativeMetaTransaction.sol";

//    .-..    ___ .-.     ___  ___  
//   /    \  (   )   \   (   )(   ) 
//  ' .-,  ;  | ' .-. ;   | |  | |  
//  | |  . |  |  / (___)  | |  | |  
//  | |  | |  | |         | |  | |  
//  | |  | |  | |         | |  | |  
//  | |  ' |  | |         | |  ; '  
//  | `-'  '  | |         ' `-'  /  
//  | \__.'  (___)         '.__.'   
//  | |                             
// (___)     

contract OwnableDelegateProxy {}
/**
 * Used to delegate ownership of a contract to another address, to save on unneeded transactions to approve contract use for users
 */
contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract ERC721Tradeable is ERC721, ContextMixin, NativeMetaTransaction, Ownable {
  using SafeMath for uint256;
  using Counters for Counters.Counter;

  //Mint price is 1 free, then 0.001 for 1, 0.003 for 3, 0.006 for 6 and 0.01 for 10
  uint256 internal constant MAX_SUPPLY = 3000;
  uint256 internal constant MAX_PER_TX = 20;
  uint256 internal constant PRICE = 1000000;
  uint256 internal constant MAX_PER_WALLET = 100;
  string public _contractURI;
  string internal _baseTokenURI;
  bool internal _isActive;
  string internal name_;
  string internal symbol_;
  uint256 internal MAX_FREE_PER_WALLET = 1;
  uint256 internal MAX_FREE_PER_WALLET_PHASE_2 = 1;
  address proxyRegistryAddress;
  
  Counters.Counter internal _nextTokenId;
     
    constructor(
        string memory _name,
        string memory _symbol,
        address _proxyRegistryAddress
    ) ERC721(_name, _symbol) {
        proxyRegistryAddress = _proxyRegistryAddress;
        _nextTokenId.increment();
        _initializeEIP712(_name);
        name_ = _name;
        symbol_ = _symbol;
    }

    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal override {
      _safeMint(to, tokenId, data);
    }

    function name() public view virtual override returns (string memory) {
        return name_;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        //metadata
        string memory base = _baseTokenURI;
        return string.concat(
          string.concat(base, Strings.toString(id)),
          ".json");
    }

    function setFreePerWallet(uint256 amount) public onlyOwner {
      MAX_FREE_PER_WALLET = amount;
    }

    function setFreePerWalletPhase(uint256 amount) public onlyOwner {
      MAX_FREE_PER_WALLET_PHASE_2 = amount;
    }

    /**
      * @dev Returns the symbol of the token, usually a shorter version of the
      * name.
      */
    function symbol() public view virtual override returns (string memory) {
        return symbol_;
    }

    function mintPriceInWei() public view virtual returns (uint256) {
        return SafeMath.mul(PRICE, 1e9);
    }

    function maxFreePerAcc() public view virtual returns (uint256) {
        return MAX_FREE_PER_WALLET;
    }
}

