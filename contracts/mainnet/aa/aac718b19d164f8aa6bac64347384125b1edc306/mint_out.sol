pragma solidity ^0.8.4;
// SPDX-Licence-Identifier: RIGHT-CLICK-SAVE-ONLY

import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./Strings.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

import "./community_interface.sol";


import "./recovery.sol";


import "./configuration.sol";

import "./token_interface.sol";

import "./console.sol";


contract freak_out is Ownable, recovery {
    using SafeMath for uint256;
    using Strings  for uint256;

    uint256[]                   public prices = [5e16,4e16,3e16,2e16,1e16,0];
    uint16[]                    public quants = [8,8,8,8,8,8];

    token_interface             public _token;

  

    mapping(address => mapping(uint16=>uint16))  public saleClaimed;
    mapping(address => mapping(uint16=>uint16))  public presaleClaimed;

    uint16 constant            public _maxSupply = 7000;
    uint16                     public _next = 146;
    uint16                     public _clientMint = 200;
    uint16                     public _clientMinted;
    


    

    address payable[]           public   _wallets;
    uint16[]                    public   _shares;
    

    event Allowed(address,bool);

     modifier onlyAllowed() {
        require(_token.permitted(msg.sender) || (msg.sender == owner()),"Unauthorised");
        _;
    }

    constructor( token_interface _token_ , address payable[] memory wallets, uint16[] memory shares) {
        require(wallets.length == shares.length,"wallets and shares lengths not equal");
        _token = _token_;
  
       
        uint total = 0;
        for (uint pos = 0; pos < shares.length; pos++) {
            total += shares[pos];
        }
        require (total == 1000, "shares must total 1000");
        _wallets = wallets;
        _shares = shares;

        _next = uint16(IERC721Enumerable(address(_token)).totalSupply());
    }

    receive() external payable {
        _split(msg.value);
    }

    function _split(uint256 amount) internal {
        bool sent;
        uint256 _total;
        for (uint256 j = 0; j < _wallets.length; j++) {
            uint256 _amount = amount * _shares[j] / 1000;
            if (j == _wallets.length-1) {
                _amount = amount - _total;
            } else {
                _total += _amount;
            }
            ( sent, ) = _wallets[j].call{value: _amount}(""); // don't use send or xfer (gas)
            require(sent, "Failed to send Ether");
        }
    }

 

    // make sure this respects ec_limit and client_limit
    function mint(uint16 numberOfCards) external payable {
        uint16 maxQuantity = 8;
       
        
        uint256 price = 0;
        uint16  tier  = 8;
        
        uint16 sc = saleClaimed[msg.sender][tier] += numberOfCards;
        require(sc <= maxQuantity,"Number exceeds max sale per address in this tier");
        _mintPayable(numberOfCards, msg.sender, price); 
    }

 
 




    function _mintPayable(uint16 numberOfCards, address recipient, uint256 price) internal {
        uint256 amountToPay = uint256(numberOfCards) * price;
        require(msg.value >= amountToPay,"price not met");
        _mintCards(numberOfCards,recipient);
        _split(msg.value);
    }

    function _mintCards(uint16 numberOfCards, address recipient) internal {
        require((_next += numberOfCards) < _maxSupply,"This exceeds maximum number of user mintable cards");
        _token.mintCards(numberOfCards,recipient);
    }


 
 

}
